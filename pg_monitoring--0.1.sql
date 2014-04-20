CREATE OR REPLACE FUNCTION pg_monitorring_lag_info()
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
LANGUAGE SQL SECURITY DEFINER AS
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

CREATE OR REPLACE FUNCTION scout_how_far_are_we_behind()
RETURNS int SECURITY DEFINER LANGUAGE SQL AS
$$ SELECT extract(epoch from now() - pg_last_xact_replay_timestamp()); $$;

COMMENT ON function scout_replication_lag_info() IS
$$This is a simple function to grab lag info in bytes.  This must be a 
function since it requires superuser privileges to run and we do not want to
run the monitoring as superuser.$$;

COMMENT ON FUNCTION pg_monitoring_how_far_ar_we_behind()
IS $$ Simple function to grab time from last write on slave.  $$; 
