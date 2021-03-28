-- setup
-- Set fsync on since we need to test the fsync code logic.
!\retcode gpconfig -c fsync -v on --skipvalidation;
!\retcode gpstop -u;
-- skip FTS probes to avoid segment being marked down on restart
SELECT gp_inject_fault_infinite('fts_probe', 'skip', dbid)
    FROM gp_segment_configuration WHERE role='p' AND content=-1;
SELECT gp_request_fts_probe_scan();
SELECT gp_wait_until_triggered_fault('fts_probe', 1, dbid)
    FROM gp_segment_configuration WHERE role='p' AND content=-1;

-- test scenario

-- The test is to validate crash recovery can be completed, for WAL
-- records generated by same transaction create and truncate followed
-- by abort transaction. Context is table created in same transaction
-- on truncate command performs unsafe truncate operation where it
-- emits WAL record for file truncate and truncates the file. During
-- crash recovery, file truncate WAL record replay will queue fsync
-- request. Replay of abort record will unlink the file. There used to
-- bug where abort record replay didn't emit forget fsync request
-- before unlink the file. This cased the crash recovery to PANIC as
-- couldn't complete the stale fsync request registered by file
-- truncate WAL record.
1: CHECKPOINT;
1: BEGIN;
1: CREATE TABLE ao_same_trans_truncate(a int, b int) WITH (appendonly=true, orientation=column);
1: TRUNCATE TABLE ao_same_trans_truncate;
1: ABORT;
-- restart (immediate) to invoke crash recovery
1: SELECT pg_ctl(datadir, 'restart') FROM gp_segment_configuration WHERE role = 'p' AND content <> -1;
-- validate the segments recovered fine and able to serve queries
2: SELECT oid from gp_dist_random('pg_class') WHERE relname='ao_same_trans_truncate';

-- cleanup
SELECT gp_inject_fault('fts_probe', 'reset', dbid)
FROM gp_segment_configuration WHERE role='p' AND content=-1;
!\retcode gpconfig -r fsync --skipvalidation;
!\retcode gpstop -u;
