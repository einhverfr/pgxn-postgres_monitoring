 \echo Use "CREATE EXTENSION pg_monitoring" to load this file. \quit



CREATE OR REPLACE FUNCTION pg_monitoring_raw_table_load()
RETURNS SETOF pg_monitoring_table_load_lastvals
LANGUAGE SQL AS
$$
-- Copied and pasted from the MIT Licensed ScoutApp Plugin for monitoring
-- PostgreSQL, see https://github.com/scoutapp/scout-plugins
-- then modified somewhat.

WITH raw_stats AS (
     SELECT sum(idx_tup_fetch) as r_select_idx,
            sum(s.seq_tup_read) as r_select_seq,
            sum(s.n_tup_ins) as r_insert,
            sum(s.n_tup_upd) as r_update,
            sum(s.n_tup_upd) as r_delete
            
       FROM pg_stat_all_tables s
)
SELECT r_select_idx, r_select_seq, r_insert, r_update, r_delete,
       r_select_idx + r_select_seq + r_insert + r_update + r_delete
  FROM raw_stats;
$$;

CREATE OR REPLACE FUNCTION pg_monitoring_load_across_tables()
RETURNS SETOF pg_monitoring_table_load_lastvals
LANGUAGE sql AS
$$
-- gives delta since last run.
-- THIS IS NOT SAFE FOR CONCURRENT CALLS OBVIOUSLY
WITH rawstats as (
     select * from pg_monitoring_raw_table_load()
),
newstats AS (
      UPDATE pg_monitoring_table_load_lastvals
         SET rows_select_idx   = r.rows_select_idx,
             rows_select_scan  = r.rows_select_scan,
             rows_insert       = r.rows_insert,
             rows_update       = r.rows_update,
             rows_delete       = r.rows_delete
        FROM rawstats r
   RETURNING *
),
old_vals AS (select * from pg_monitoring_table_load_lastvals),
processed_vals AS (
      select c.rows_select_idx - o.rows_select_idx as rows_select_idx,
             c.rows_select_scan - o.rows_select_scan as rows_select_scan,
             c.rows_insert - o.rows_insert as rows_insert,
             c.rows_update - o.rows_update as rows_update,
             c.rows_delete - o.rows_delete as rows_delete
      FROM newstats c 
cross join old_vals o
)
SELECT rows_select_idx, rows_select_scan, rows_insert, rows_update,
       rows_delete, 
       rows_select_idx + rows_select_scan + rows_insert + rows_update
       + rows_delete as rows_total
  FROM processed_vals;
$$;

