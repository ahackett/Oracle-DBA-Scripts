/*
 * File:	awr_delta_views.sql
 * Type:	SQL*Plus script
 * Author:	Austin Hackett
 * Date:	18Apr12
 *
 * Description:
 *
 *	SQL*Plus script containing DDL to create views that automatically
 *	calculate the "delta" or difference between adjacent samples of
 *	data gathered by AWR.
 *
 *	Each of these views is named the same as the corresponding views
 *	in the AWR, except that the prefix of "DBA_HIST" has been replaced
 * 	by a prefix of "DELTA$".
 *
 *	Views are present for the following AWR views:
 *
 *		AWR Name
 *		========
 *		DBA_HIST_IOSTAT_FUNCTION	DELTA$IOSTAT_FUNCTION
 *		DBA_HIST_PERSISTENT_QUEUES	DELTA$PERSISTENT_QUEUES
 *		DBA_HIST_SERVICE_STAT		DELTA$SERVICE_STAT
 *		DBA_HIST_SYSSTAT		DELTA$SYSSTAT
 *		DBA_HIST_SYSTEM_EVENT		DELTA$SYSTEM_EVENT
 *		DBA_HIST_SYS_TIME_MODEL		DELTA$SYS_TIME_MODEL
 *		DBA_HIST_TBSPC_SPACE_USAGE	DELTA$TABLESPACE_USAGE
 *
 *	These views are largely an adaptation of Tim Gorman's sp_delta_views.sql
 *	script found at http://www.evdbt.com/sp_delta_views.sql for the AWR. That
 *      said, not all of Tim's views have their equivalent here, as I'm creating
 *	them as I need them!
 *
 *	Note that TABLESPACE_USEDSIZE in DELTA$TABLESPACE_USAGE includes space
 *	occupied by recyclebin objects. This is a problem/feature of the AWR
 *	DBA_HIST_TBSPC_SPACE_USAGE view. Oracle Support have submitted a bug
 *	request for me.
 *
*/
SET DEFINE OFF ECHO ON FEEDBACK ON TIMING ON;
PROMPT View DELTA$IOSTAT_FUNCTION;

CREATE OR REPLACE FORCE VIEW DELTA$IOSTAT_FUNCTION
(
   SNAP_ID,
   DBID,
   INSTANCE_NUMBER,
   FUNCTION_NAME,
   LARGE_READ_MEGABYTES,
   LARGE_READ_REQS,
   SMALL_READ_MEGABYTES,
   SMALL_READ_REQS
)
AS
   SELECT snap_id,
          dbid,
          instance_number,
          function_name,
          NVL (
             DECODE (
                GREATEST (
                   large_read_reqs,
                   NVL (
                      LAG (
                         large_read_reqs)
                      OVER (PARTITION BY dbid, instance_number, function_name
                            ORDER BY snap_id),
                      0)),
                large_read_reqs,   large_read_reqs
                                 - LAG (
                                      large_read_reqs)
                                   OVER (
                                      PARTITION BY dbid,
                                                   instance_number,
                                                   function_name
                                      ORDER BY snap_id),
                large_read_reqs),
             0)
             VALUE,
          NVL (
             DECODE (
                GREATEST (
                   large_read_megabytes,
                   NVL (
                      LAG (
                         large_read_megabytes)
                      OVER (PARTITION BY dbid, instance_number, function_name
                            ORDER BY snap_id),
                      0)),
                large_read_megabytes,   large_read_megabytes
                                      - LAG (
                                           large_read_megabytes)
                                        OVER (
                                           PARTITION BY dbid,
                                                        instance_number,
                                                        function_name
                                           ORDER BY snap_id),
                large_read_megabytes),
             0)
             VALUE,
          NVL (
             DECODE (
                GREATEST (
                   small_read_megabytes,
                   NVL (
                      LAG (
                         small_read_megabytes)
                      OVER (PARTITION BY dbid, instance_number, function_name
                            ORDER BY snap_id),
                      0)),
                small_read_megabytes,   small_read_megabytes
                                      - LAG (
                                           small_read_megabytes)
                                        OVER (
                                           PARTITION BY dbid,
                                                        instance_number,
                                                        function_name
                                           ORDER BY snap_id),
                small_read_megabytes),
             0)
             VALUE,
          NVL (
             DECODE (
                GREATEST (
                   small_read_reqs,
                   NVL (
                      LAG (
                         small_read_reqs)
                      OVER (PARTITION BY dbid, instance_number, function_name
                            ORDER BY snap_id),
                      0)),
                small_read_reqs,   small_read_reqs
                                 - LAG (
                                      small_read_reqs)
                                   OVER (
                                      PARTITION BY dbid,
                                                   instance_number,
                                                   function_name
                                      ORDER BY snap_id),
                small_read_reqs),
             0)
             VALUE
     FROM dba_hist_iostat_function
/


PROMPT View DELTA$PERSISTENT_QUEUES;

CREATE OR REPLACE FORCE VIEW DELTA$PERSISTENT_QUEUES
(
   SNAP_ID,
   DBID,
   INSTANCE_NUMBER,
   QUEUE_SCHEMA,
   QUEUE_NAME,
   ENQUEUED_MSGS,
   DEQUEUED_MSGS
)
AS
     SELECT snap_id,
            dbid,
            instance_number,
            queue_schema,
            queue_name,
            NVL (
               DECODE (
                  GREATEST (
                     enqueued_msgs,
                     NVL (
                        LAG (
                           enqueued_msgs)
                        OVER (
                           PARTITION BY dbid,
                                        instance_number,
                                        queue_schema,
                                        queue_name
                           ORDER BY snap_id),
                        0)),
                  enqueued_msgs,   enqueued_msgs
                                 - LAG (
                                      enqueued_msgs)
                                   OVER (
                                      PARTITION BY dbid,
                                                   instance_number,
                                                   queue_schema,
                                                   queue_name
                                      ORDER BY snap_id),
                  enqueued_msgs),
               0)
               enqueued_msgs,
            NVL (
               DECODE (
                  GREATEST (
                     dequeued_msgs,
                     NVL (
                        LAG (
                           dequeued_msgs)
                        OVER (
                           PARTITION BY dbid,
                                        instance_number,
                                        queue_schema,
                                        queue_name
                           ORDER BY snap_id),
                        0)),
                  dequeued_msgs,   dequeued_msgs
                                 - LAG (
                                      dequeued_msgs)
                                   OVER (
                                      PARTITION BY dbid,
                                                   instance_number,
                                                   queue_schema,
                                                   queue_name
                                      ORDER BY snap_id),
                  dequeued_msgs),
               0)
               dequeued_msgs
       FROM dba_hist_persistent_queues
   ORDER BY snap_id DESC
/


PROMPT View DELTA$SERVICE_STAT;

CREATE OR REPLACE FORCE VIEW DELTA$SERVICE_STAT
(
   SNAP_ID,
   DBID,
   INSTANCE_NUMBER,
   SERVICE_NAME,
   STAT_NAME,
   VALUE
)
AS
   SELECT snap_id,
          dbid,
          instance_number,
          SERVICE_NAME,
          stat_name,
          NVL (
             DECODE (
                GREATEST (
                   VALUE,
                   NVL (
                      LAG (
                         VALUE)
                      OVER (
                         PARTITION BY dbid,
                                      instance_number,
                                      stat_name,
                                      SERVICE_NAME
                         ORDER BY snap_id),
                      0)),
                VALUE,   VALUE
                       - LAG (
                            VALUE)
                         OVER (
                            PARTITION BY dbid,
                                         instance_number,
                                         stat_name,
                                         SERVICE_NAME
                            ORDER BY snap_id),
                VALUE),
             0)
             VALUE
     FROM dba_hist_SERVICE_STAT
/


PROMPT View DELTA$SYSSTAT;

CREATE OR REPLACE FORCE VIEW DELTA$SYSSTAT
(
   SNAP_ID,
   DBID,
   INSTANCE_NUMBER,
   STAT_NAME,
   VALUE
)
AS
   SELECT snap_id,
          dbid,
          instance_number,
          stat_name,
          NVL (
             DECODE (
                GREATEST (
                   VALUE,
                   NVL (
                      LAG (
                         VALUE)
                      OVER (PARTITION BY dbid, instance_number, stat_name
                            ORDER BY snap_id),
                      0)),
                VALUE,   VALUE
                       - LAG (
                            VALUE)
                         OVER (PARTITION BY dbid, instance_number, stat_name
                               ORDER BY snap_id),
                VALUE),
             0)
             VALUE
     FROM dba_hist_sysstat
/


PROMPT View DELTA$SYSTEM_EVENT;

CREATE OR REPLACE FORCE VIEW DELTA$SYSTEM_EVENT
(
   SNAP_ID,
   DBID,
   INSTANCE_NUMBER,
   EVENT_NAME,
   WAIT_CLASS,
   TOTAL_WAITS,
   TOTAL_TIMEOUTS,
   TIME_WAITED_MICRO,
   TOTAL_WAITS_FG,
   TOTAL_TIMEOUTS_FG,
   TIME_WAITED_MICRO_FG
)
AS
   SELECT SNAP_ID,
          DBID,
          INSTANCE_NUMBER,
          EVENT_name,
          wait_class,
          NVL (
             DECODE (
                GREATEST (
                   TOTAL_WAITS,
                   NVL (
                      LAG (
                         TOTAL_WAITS)
                      OVER (PARTITION BY dbid, instance_number, event_name
                            ORDER BY snap_id),
                      0)),
                TOTAL_WAITS,   TOTAL_WAITS
                             - LAG (
                                  TOTAL_WAITS)
                               OVER (
                                  PARTITION BY dbid,
                                               instance_number,
                                               event_name
                                  ORDER BY snap_id),
                TOTAL_WAITS),
             0)
             TOTAL_WAITS,
          NVL (
             DECODE (
                GREATEST (
                   TOTAL_TIMEOUTS,
                   NVL (
                      LAG (
                         TOTAL_TIMEOUTS)
                      OVER (PARTITION BY dbid, instance_number, event_name
                            ORDER BY snap_id),
                      0)),
                TOTAL_TIMEOUTS,   TOTAL_TIMEOUTS
                                - LAG (
                                     TOTAL_TIMEOUTS)
                                  OVER (
                                     PARTITION BY dbid,
                                                  instance_number,
                                                  event_name
                                     ORDER BY snap_id),
                TOTAL_TIMEOUTS),
             0)
             TOTAL_TIMEOUTS,
          NVL (
             DECODE (
                GREATEST (
                   TIME_WAITED_MICRO,
                   NVL (
                      LAG (
                         TIME_WAITED_MICRO)
                      OVER (PARTITION BY dbid, instance_number, event_name
                            ORDER BY snap_id),
                      0)),
                TIME_WAITED_MICRO,   TIME_WAITED_MICRO
                                   - LAG (
                                        TIME_WAITED_MICRO)
                                     OVER (
                                        PARTITION BY dbid,
                                                     instance_number,
                                                     event_name
                                        ORDER BY snap_id),
                TIME_WAITED_MICRO),
             0)
             TIME_WAITED_MICRO,
          NVL (
             DECODE (
                GREATEST (
                   TOTAL_WAITS_FG,
                   NVL (
                      LAG (
                         TOTAL_WAITS_FG)
                      OVER (PARTITION BY dbid, instance_number, event_name
                            ORDER BY snap_id),
                      0)),
                TOTAL_WAITS_FG,   TOTAL_WAITS_FG
                                - LAG (
                                     TOTAL_WAITS_FG)
                                  OVER (
                                     PARTITION BY dbid,
                                                  instance_number,
                                                  event_name
                                     ORDER BY snap_id),
                TOTAL_WAITS_FG),
             0)
             TOTAL_WAITS_FG,
          NVL (
             DECODE (
                GREATEST (
                   TOTAL_TIMEOUTS_FG,
                   NVL (
                      LAG (
                         TOTAL_TIMEOUTS_FG)
                      OVER (PARTITION BY dbid, instance_number, event_name
                            ORDER BY snap_id),
                      0)),
                TOTAL_TIMEOUTS_FG,   TOTAL_TIMEOUTS_FG
                                   - LAG (
                                        TOTAL_TIMEOUTS_FG)
                                     OVER (
                                        PARTITION BY dbid,
                                                     instance_number,
                                                     event_name
                                        ORDER BY snap_id),
                TOTAL_TIMEOUTS_FG),
             0)
             TOTAL_TIMEOUTS_FG,
          NVL (
             DECODE (
                GREATEST (
                   TIME_WAITED_MICRO_FG,
                   NVL (
                      LAG (
                         TIME_WAITED_MICRO_FG)
                      OVER (PARTITION BY dbid, instance_number, event_name
                            ORDER BY snap_id),
                      0)),
                TIME_WAITED_MICRO_FG,   TIME_WAITED_MICRO_FG
                                      - LAG (
                                           TIME_WAITED_MICRO_FG)
                                        OVER (
                                           PARTITION BY dbid,
                                                        instance_number,
                                                        event_name
                                           ORDER BY snap_id),
                TIME_WAITED_MICRO_FG),
             0)
             TIME_WAITED_MICRO_FG
     FROM dba_hist_system_event
/


PROMPT View DELTA$SYS_TIME_MODEL;

CREATE OR REPLACE FORCE VIEW DELTA$SYS_TIME_MODEL
(
   SNAP_ID,
   DBID,
   INSTANCE_NUMBER,
   STAT_NAME,
   VALUE
)
AS
   SELECT snap_id,
          dbid,
          instance_number,
          stat_name,
          NVL (
             DECODE (
                GREATEST (
                   VALUE,
                   NVL (
                      LAG (
                         VALUE)
                      OVER (PARTITION BY dbid, instance_number, stat_name
                            ORDER BY snap_id),
                      0)),
                VALUE,   VALUE
                       - LAG (
                            VALUE)
                         OVER (PARTITION BY dbid, instance_number, stat_name
                               ORDER BY snap_id),
                VALUE),
             0)
             VALUE
     FROM dba_hist_sys_time_model
/


PROMPT View DELTA$TABLESPACE_USAGE;

CREATE OR REPLACE FORCE VIEW DELTA$TABLESPACE_USAGE
(
   SNAP_ID,
   DBID,
   TABLESPACE_ID,
   TSNAME,
   GROWTH,
   TABLESPACE_USEDSIZE
)
AS
   WITH ts_info
        AS (  SELECT dbid,
                     ts#,
                     tsname,
                     MAX (block_size) block_size
                FROM dba_hist_datafile
            GROUP BY dbid, ts#, tsname)
   -- Calculate the delta growth of each tablespace by snapshot
   SELECT tsu.snap_id,
          tsu.dbid,
          tsu.tablespace_id,
          ti.tsname,
          NVL (  tsu.tablespace_usedsize * ti.block_size
               - LAG (tsu.tablespace_usedsize * ti.block_size, 1)
                    OVER (ORDER BY
                             tsu.dbid,
                             tsu.tablespace_id,
                             ti.tsname,
                             tsu.snap_id),
               0)
             growth,
          tsu.tablespace_usedsize * ti.block_size tablespace_usedsize
     FROM dba_hist_tbspc_space_usage tsu, ts_info ti
    WHERE tsu.dbid = ti.dbid AND tsu.tablespace_id = ti.ts#
/

