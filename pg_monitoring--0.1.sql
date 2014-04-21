-- \echo Use "CREATE EXTENSION pg_monitoring" to load this file. \quit


CREATE TABLE pg_monitoring_last_run (
     proname name,
     runtime timestamp
);

-- this is a snapshot so no need for last run handling

CREATE OR REPLACE FUNCTION pg_monitoring_lag_info()
RETURNS TABLE (
            usename name,
   application_name text,
    client_hostname text, 
        client_addr inet,
        client_port int,
      backend_start timestamptz,
              state text,
      sync_priority int,
         sync_state text,
          total_lag double precision
)
LANGUAGE SQL AS
$$
SELECT usename, application_name, client_hostname, client_addr, client_port,
       backend_start, state, sync_priority, sync_state,
       ((cur_xlog * 255 * 16 ^ 6) + cur_offset) 
       - ((replay_xlog * 255 * 16 ^ 6) + replay_offset) as total_lag
FROM (
      SELECT usename, application_name, client_hostname, client_addr, 
             client_port, backend_start, state, sync_priority, sync_state,
             ('x' || lpad(split_part(replay_location, '/', 1), 8, '0')
             )::bit(32)::bigint AS replay_xlog,
             ('x' || lpad(split_part(replay_location, '/', 2), 8, '0')
             )::bit(32)::bigint AS replay_offset,
             ('x' || lpad(split_part(pg_current_xlog_location(), '/', 1), 
                          8, '0')
             )::bit(32)::bigint as cur_xlog,
             ('x' || lpad(split_part(pg_current_xlog_location(), '/', 2), 
                           8, '0')
             )::bit(32)::bigint as cur_offset
FROM pg_stat_replication) AS stats;
$$;



CREATE OR REPLACE FUNCTION pg_monitoring_time_since_replay()
RETURNS double precision
LANGUAGE SQL AS
$$ SELECT extract(epoch from now() - pg_last_xact_replay_timestamp()); $$;

COMMENT ON function pg_monitoring_lag_info() IS
$$This is a simple function to grab lag info in bytes.  This must be a 
function since it requires superuser privileges to run and we do not want to
run the monitoring as superuser.$$;

COMMENT ON FUNCTION pg_monitoring_time_since_replay()
IS $$ Simple function to grab time from last write on slave.  $$; 

CREATE TABLE pg_monitoring_table_load_lastvals (
    rows_select_idx numeric,
    rows_select_scan numeric,
    rows_insert numeric,
    rows_update numeric,
    rows_delete numeric,
    rows_total numeric
);

insert into pg_monitoring_table_load_lastvals (rows_total) values (null);

CREATE OR REPLACE FUNCTION pg_monitoring_load_across_tables()
RETURNS SETOF pg_monitoring_table_load_lastvals
LANGUAGE sql AS
$$
-- Copied and pasted from the MIT Licensed ScoutApp Plugin for monitoring
-- PostgreSQL, see https://github.com/scoutapp/scout-plugins
-- then modified  Takes delta since last run.

WITH rawstats as (
     SELECT sum(idx_tup_fetch) as r_select_idx,
            sum(s.seq_tup_read) as r_select_seq,
            sum(s.n_tup_ins) as r_insert,
            sum(s.n_tup_upd) as r_update,
            sum(s.n_tup_upd) as r_delete
       FROM pg_stat_all_tables s
),
newstats AS (
      UPDATE pg_monitoring_table_load_lastvals
         SET rows_select_idx   = r.r_select_idx,
             rows_select_scan  = r.r_select_seq,
             rows_insert       = r.r_insert,
             rows_update       = r.r_update,
             rows_delete       = r.r_delete
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

CREATE OR REPLACE FUNCTION pg_monitoring_load_across_databases()
RETURNS TABLE (
   numbackends bigint,
   xact_commit numeric,
   xact_rollback numeric,
   xact_total numeric,
   blks_read numeric,
   blks_hit numeric
)
LANGUAGE SQL AS
$$
-- Copied and pasted from the MIT Licensed ScoutApp Plugin for monitoring
-- PostgreSQL, see https://github.com/scoutapp/scout-plugins
SELECT             sum(numbackends) AS "numbackends", 
                   sum(xact_commit) AS "xact_commit", 
                 sum(xact_rollback) AS "xact_rollback", 
     sum(xact_commit+xact_rollback) AS "xact_total", 
                     sum(blks_read) AS "blks_read", 
                      sum(blks_hit) AS "blks_hit"
  FROM pg_stat_database;
$$;
