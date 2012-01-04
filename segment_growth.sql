--
-- Show total growth per segment for all segments in a given tablespace during the past n days
-- Assumes you are licenced for the tuning and diagnostics package, since we're using the AWR
-- tables...
--

  SELECT sso.owner,
         sso.object_name,
         sso.subobject_name,
         sso.object_type,
         SUM (SS.SPACE_ALLOCATED_DELTA) / (1024 * 1024) mb_growth
    FROM DBA_HIST_SEG_STAT ss, DBA_HIST_SEG_STAT_OBJ sso, dba_hist_snapshot sn
   WHERE     ss.dbid = sso.dbid
         AND SS.TS# = sso.ts#
         AND ss.obj# = sso.obj#
         AND ss.dataobj# = sso.dataobj#
         AND ss.dbid = sn.dbid
         AND SS.INSTANCE_NUMBER = sn.instance_number
         AND ss.snap_id = sn.snap_id
         AND sso.tablespace_name = '&tablespace_name'
         AND sn.begin_interval_time >= TRUNC (SYSDATE - &days)
  HAVING SUM (SS.SPACE_ALLOCATED_DELTA) > 0
GROUP BY sso.owner,
         sso.object_name,
         sso.subobject_name,
         sso.object_type
ORDER BY SUM (SS.SPACE_ALLOCATED_DELTA) DESC