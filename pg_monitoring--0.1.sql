\echo Use "CREATE EXTENSION pg_monitoring" to load this file. \quit


-- As of Pg 9.2 at least, the pg_stat_replication view joins together several functions, not directly hitting relations
-- Wrapping this in a function thus poses no performance issues currently.  If this ever changes though, we may want to 
-- change our approach here.

CREATE OR REPLACE FUNCTION pg_monitoring_lag_info()
RETURNS TABLE (
            usename text,
   application_name text,
    client_hostname text, 
        client_addr inet,
        client_port int,
      backend_start timestamptz,
              state text,
      sync_priority int,
         sync_state text,
          total_lag numeric
)
LANGUAGE SQL AS
$$
SELECT client_hostname, client_addr,
       ((cur_xlog * 255 * 16 ^ 6) + cur_offset) 
       - ((replay_xlog * 255 * 16 ^ 6) + replay_offset) as total_lag,
FROM (
      SELECT client_hostname, client_addr,
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
RETURNS int LANGUAGE SQL AS
$$ SELECT extract(epoch from now() - pg_last_xact_replay_timestamp()); $$;

COMMENT ON function pg_monitoring_replication_lag_info() IS
$$This is a simple function to grab lag info in bytes.  This must be a 
function since it requires superuser privileges to run and we do not want to
run the monitoring as superuser.$$;

COMMENT ON FUNCTION pg_monitoring_time_since_replay()
IS $$ Simple function to grab time from last write on slave.  $$; 

CREATE OR REPLACE FUNCTION pg_monitoring_load_across_tables()
RETURNS TABLE (
    rows_select_idx bigint,
    rows_select_scan bigint,
    rows_insert bigint,
    rows_update bigint,
    rows_delete bigint,
    rows_total bigint
)
LANGUAGE sql AS
$$
-- Copied and pasted from the MIT Licensed ScoutApp Plugin for monitoring
-- PostgreSQL, see https://github.com/scoutapp/scout-plugins
-- then modified for better load with larger numbers of tables, as this approach
-- avoids resumming every aggregate twice for each table.  This is a marginal 
-- benefit since the PostgreSQL optimizer is very good at these things but the 
-- in a db under load with lots of tables, this seems like a good tradeoff
WITH raw_stats AS (
      SELECT sum(idx_tup_fetch) AS "rows_select_idx", 
              sum(seq_tup_read) AS "rows_select_scan", 
                 sum(n_tup_ins) AS "rows_insert", 
                 sum(n_tup_upd) AS "rows_update",
                 sum(n_tup_del) AS "rows_delete"
        FROM pg_stat_all_tables)
)
SELECT rows_select_idx, rows_select_scan, rows_insert, rows_update,
       rows_delete, 
       rows_select_idx + rows_select_scan + rows_insert + rows_update
       + rows_delete as rows_total
  FROM raw_stats;
$$;

CREATE OR REPLACE FUNCTION pg_monitoring_load_across_databases()
RETURNS TABLE (
   numbackends int,
   xact_commit bigint,
   xact_rollback bigint,
   xact_total bigint,
   blks_read  bigint,
   blks_hit   bigint
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
