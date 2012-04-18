#!/bin/ksh -p
#============================================================================
# File:         tablespace_growth_rpt.sh
# Type:         UNIX korn-shell script
# Author:       Austin Hackett
# Date:         16Mar2012
#
# Description:
#
#       Adaptation of Graham Halsey's tablespace growth report to use the
#       AWR views and include last week's growth high water mark and the
#       utilization high water mark for yesterday.
#
#       General shell script style adapated from Tim Gorman's "UNIX shell
#       scripts for Oracle DBAs" at http://www.evdbt.com/tools.htm.
#
#       For the specified database, report:
#
#       1. Current tablespace utilization
#       2. Growth yesterday
#       3. Growth for the previous seven days before that
#       4. Number of days left at the current growth rate
#
#	IMPORTANT NOTE: This script uses the DBA_HIST_TBSPC_SPACE_USAGE
#	AWR view. It seems that the view includes space occupied by the
#	recycle bin in it's calculation of used space. This being the
#	case, the report can be misleading if the recycle bin isn't empty.
#	Oracle Support have opened a bug request on my behalf.
#
#       Detailed description of each column in the report:
#
#       Tablespace Name
#
#       The name of the tablespace
#
#       Current Total (GB)
#
#       This is the size of the tablespace in gigbytes when
#       the report was run (e.g. it is calculated using DBA_DATA_FILES)
#
#       Current Used (GB)
#
#       This is the amount of used space in gigabytes when the report
#       was run (e.g. it is calculated by subtracting free space to the
#       total size of the tablespace)
#
#       Current Free (GB)
#
#       This is the amount of free space in gigabytes when the report was
#       run (e.g. it is calculated using DBA_FREE_SPACE)
#
#       Current % Used
#
#       This is the amount of free space when the report was run, expressed
#       as a percentage
#
#       Previous 7 Days Inc
#
#       This is total growth in megabytes for the 7 days previous to
#       yesterday. If yesterday.s growth is similar to, or exceeds the
#       growth for the previous 7 days then it.s worth investigating
#
#       Previous 7 Days Max Inc (MB)
#
#       This is the highest daily rate of growth for the 7 days previous to yesterday.
#       By comparing this to yesterday's growth, we can determine whether current growth
#       is unusual for this tablespace
#
#       Yesterday Inc (MB)
#
#       This is yesterdays growth in megabytes
#
#       Yesterday Max Used (GB)
#
#       This is high water mark for space usage during the previous day
#
#       Days Left
#
#       Assuming yesterday.s growth rate, the number of days before space
#       will be exhausted. Whenever this is less than 21 days, the tablespace
#       is flagged with a "<<" symbol. This should be investigated, but it's
#       important to check "Previous 7 Days Max Inc (MB)" and see if similar
#       growth has occurred in the past. If it has and "Previous 7 Days Inc"
#       is low, then the segments are probably subject to regular purges, and it
#       should be safe to check growth again in 24 hours (unless "Days Left" is
#       very low)
#
# Exit statuses:
#       0       normal succesful completion
#       1       ORACLE_SID not specified - user error
#       2       Cannot connect using "CONNECT / AS SYSDBA"
#       3       SQL*Plus failed to create "spool" file for report
#       4       SQL*Plus failed while generating report
#
# Modifications:
#
#       16Mar2012       Austin Hackett
#
#       ps and grep are in /bin on Linux platforms, rather than /usr/bin
#       as per Solaris. Added /bin to PATH
#============================================================================
Pgm=tablespace_growth_rpt
#
#----------------------------------------------------------------------------
# Set the correct PATH for the script...
#----------------------------------------------------------------------------
PATH=/bin:/usr/bin:/usr/local/bin; export PATH
#
#----------------------------------------------------------------------------
# Korn-shell function to be called multiple times in the script...
#----------------------------------------------------------------------------
notify_via_email() # ...use email to notify people...
{
        cat << __EOF__ | mailx -s "$Pgm $Level $OraSid" dba@mycompany.com
$ErrMsg

$([ -f $SpoolFile ] && cat $SpoolFile)
__EOF__
} # ...end of shell function "notify_via_email"...
#
#----------------------------------------------------------------------------
# Verify that the ORACLE_SID has been specified on the UNIX command-line...
#----------------------------------------------------------------------------
if (( $# != 1 ))
then
        echo "Usage: $Pgm.sh ORACLE_SID;  aborting..."
        exit 1
fi
OraSid=$1
#
#----------------------------------------------------------------------------
# Verify that the database instance specified is "up"...
#----------------------------------------------------------------------------
Up=`ps -eaf | grep ora_pmon_${OraSid} | grep -v grep | awk '{print $NF}'`
if [[ -z $Up  ]]
then
        exit 0
fi
#
#----------------------------------------------------------------------------
# Verify that the ORACLE_SID is registered in the ORATAB file...
#----------------------------------------------------------------------------
dbhome $OraSid > /dev/null 2>&1
if (( $? != 0 ))
then
        echo "$Pgm: \"$OraSid\" not local to this host; aborting..."
        exit 1
fi
#
#----------------------------------------------------------------------------
# Set the Oracle environment variables for this database instance...
#----------------------------------------------------------------------------
export ORACLE_SID=$OraSid
export ORAENV_ASK=NO
. oraenv > /dev/null 2>&1
unset ORAENV_ASK
#
#----------------------------------------------------------------------------
# Locate the "spool" file for the SQL*Plus report...
#----------------------------------------------------------------------------
SpoolFile=/tmp/${Pgm}_$ORACLE_SID.lst
#
#----------------------------------------------------------------------------
# Connect via SQL*Plus and produce the report...
#----------------------------------------------------------------------------
sqlplus -s /nolog << __EOF__ > /dev/null 2>&1
whenever oserror exit 2
whenever sqlerror exit 2
connect / as sysdba
whenever oserror exit 3
whenever sqlerror exit 4
set pages 1000 lines 200 trims on feed off veri off
break on report
compute sum of alloc_gb on report;
compute sum of used_gb on report;
compute sum of free_gb on report;
compute sum of last_week_mb on report;
compute sum of yesterday_mb on report;
col tsname for a30 head "Tablespace|Name"
col alloc_gb for 9,999,990.00 head "Current|Total (GB)"
col used_gb for 9,999,990.00 head "Current|Used (GB)"
col free_gb for 9,999,990.00 head "Current|Free (GB)"
col pct_used for 990.00 head "Current|% Used"
col last_week_mb for 999,990.00 head "Previous|7 Days Inc"
col last_week_max_mb for 999,990.00 head "Previous 7 Days|Max Inc (MB)"
col yesterday_mb for 999,990.00 head "Yesterday|Inc (MB)"
col yesterday_max_gb for 9,999,990.00 head "Yesterday|Max Used (GB)"
col days_left for 9,990 head "Days|Left"
col flag head ""
spool $SpoolFile
  SELECT tsname,
         alloc_gb,
         used_gb,
         free_gb,
         pct_used,
         last_week_mb,
         last_week_max_mb,
         yesterday_mb,
         yesterday_max_gb,
         LEAST (days_left, 999) days_left,
         CASE WHEN days_left <= 20 THEN '<<' ELSE NULL END flag
    FROM (SELECT curr.tsname,
                 curr.alloc / (1024 * 1024 * 1024) alloc_gb,
                 curr.used / (1024 * 1024 * 1024) used_gb,
                 curr.free / (1024 * 1024 * 1024) free_gb,
                 curr.pct_used,
                 last_week.growth / (1024 * 1024) last_week_mb,
                 last_week_max.growth / (1024 * 1024) last_week_max_mb,
                 yesterday.growth / (1024 * 1024) yesterday_mb,
                 yesterday_max.used / (1024 * 1024 * 1024) yesterday_max_gb,
                 CASE
                    WHEN yesterday.growth > 0 THEN curr.free / yesterday.growth
                    ELSE 999
                 END
                    days_left
            FROM (SELECT df.tablespace_name tsname,
                         df.alloc,
                         df.alloc - NVL (fs.free, 0) used,
                         NVL (fs.free, 0) free,
                         ( (df.alloc - NVL (fs.free, 0)) / df.alloc) * 100
                            pct_used
                    FROM (  SELECT tablespace_name, SUM (bytes) free
                              FROM dba_free_space
                          GROUP BY tablespace_name) fs,
                         (  SELECT tablespace_name, SUM (bytes) alloc
                              FROM dba_data_files
                          GROUP BY tablespace_name) df
                   WHERE fs.tablespace_name = df.tablespace_name) curr,
                 (  SELECT tsname, SUM (growth) growth
                      FROM (SELECT s.snap_id,
                                   s.instance_number,
                                   s.dbid,
                                   ti.tsname,
                                   NVL (
                                        NVL (
                                           su.tablespace_usedsize * ti.block_size,
                                           0)
                                      - LAG (
                                           NVL (
                                                su.tablespace_usedsize
                                              * ti.block_size,
                                              0),
                                           1)
                                        OVER (PARTITION BY ti.tsname, su.dbid
                                              ORDER BY su.snap_id),
                                      0)
                                      growth
                              FROM dba_hist_snapshot s,
                                   dba_hist_tbspc_space_usage su,
                                   (  SELECT dbid,
                                             ts#,
                                             tsname,
                                             MAX (block_size) block_size
                                        FROM dba_hist_datafile
                                    GROUP BY dbid, ts#, tsname) ti
                             WHERE     s.dbid = su.dbid
                                   AND s.snap_id = su.snap_id
                                   AND su.dbid = ti.dbid
                                   AND su.tablespace_id = ti.ts#
                                   AND s.begin_interval_time >=
                                          TRUNC (SYSDATE - 8)
                                   AND s.begin_interval_time <
                                          TRUNC (SYSDATE - 1)
                                   AND su.dbid = (SELECT dbid FROM v\$database)
                                   AND s.instance_number =
                                          (SELECT instance_number FROM v\$instance))
                  GROUP BY tsname) last_week,
                 (  SELECT tsname, MAX (growth) growth
                      FROM (  SELECT TRUNC (begin_interval_time, 'DD')
                                        begin_interval_time,
                                     tsname,
                                     SUM (growth) growth
                                FROM (SELECT s.snap_id,
                                             s.instance_number,
                                             s.dbid,
                                             s.begin_interval_time,
                                             ti.tsname,
                                             NVL (
                                                  NVL (
                                                       su.tablespace_usedsize
                                                     * ti.block_size,
                                                     0)
                                                - LAG (
                                                     NVL (
                                                          su.tablespace_usedsize
                                                        * ti.block_size,
                                                        0),
                                                     1)
                                                  OVER (
                                                     PARTITION BY ti.tsname,
                                                                  su.dbid
                                                     ORDER BY su.snap_id),
                                                0)
                                                growth
                                        FROM dba_hist_snapshot s,
                                             dba_hist_tbspc_space_usage su,
                                             (  SELECT dbid,
                                                       ts#,
                                                       tsname,
                                                       MAX (block_size) block_size
                                                  FROM dba_hist_datafile
                                              GROUP BY dbid, ts#, tsname) ti
                                       WHERE     s.dbid = su.dbid
                                             AND s.snap_id = su.snap_id
                                             AND su.dbid = ti.dbid
                                             AND su.tablespace_id = ti.ts#
                                             AND s.begin_interval_time >=
                                                    TRUNC (SYSDATE - 8)
                                             AND s.begin_interval_time <
                                                    TRUNC (SYSDATE - 1)
                                             AND su.dbid =
                                                    (SELECT dbid FROM v\$database)
                                             AND s.instance_number =
                                                    (SELECT instance_number
                                                       FROM v\$instance))
                            GROUP BY TRUNC (begin_interval_time, 'DD'), tsname)
                  GROUP BY tsname) last_week_max,
                 (  SELECT tsname, SUM (growth) growth
                      FROM (SELECT s.snap_id,
                                   s.instance_number,
                                   s.dbid,
                                   ti.tsname,
                                   NVL (
                                        NVL (
                                           su.tablespace_usedsize * ti.block_size,
                                           0)
                                      - LAG (
                                           NVL (
                                                su.tablespace_usedsize
                                              * ti.block_size,
                                              0),
                                           1)
                                        OVER (PARTITION BY ti.tsname, su.dbid
                                              ORDER BY su.snap_id),
                                      0)
                                      growth
                              FROM dba_hist_snapshot s,
                                   dba_hist_tbspc_space_usage su,
                                   (  SELECT dbid,
                                             ts#,
                                             tsname,
                                             MAX (block_size) block_size
                                        FROM dba_hist_datafile
                                    GROUP BY dbid, ts#, tsname) ti
                             WHERE     s.dbid = su.dbid
                                   AND s.snap_id = su.snap_id
                                   AND su.dbid = ti.dbid
                                   AND su.tablespace_id = ti.ts#
                                   AND s.begin_interval_time >=
                                          TRUNC (SYSDATE - 1)
                                   AND s.begin_interval_time < TRUNC (SYSDATE)
                                   AND su.dbid = (SELECT dbid FROM v\$database)
                                   AND s.instance_number =
                                          (SELECT instance_number FROM v\$instance))
                  GROUP BY tsname) yesterday,
                 (  SELECT TRUNC (s.begin_interval_time, 'DD')
                              begin_interval_time,
                           ti.tsname,
                           MAX (su.tablespace_usedsize * ti.block_size) used
                      FROM dba_hist_snapshot s,
                           (  SELECT dbid,
                                     ts#,
                                     tsname,
                                     MAX (block_size) block_size
                                FROM dba_hist_datafile
                            GROUP BY dbid, ts#, tsname) ti,
                           dba_hist_tbspc_space_usage su
                     WHERE     s.dbid = su.dbid
                           AND s.snap_id = su.snap_id
                           AND su.dbid = ti.dbid
                           AND su.tablespace_id = ti.ts#
                           AND s.begin_interval_time >= TRUNC (SYSDATE - 1)
                           AND s.begin_interval_time < TRUNC (SYSDATE)
                           AND su.dbid = (SELECT dbid FROM v\$database)
                           AND s.instance_number =
                                  (SELECT instance_number FROM v\$instance)
                  GROUP BY TRUNC (s.begin_interval_time, 'DD'), ti.tsname) yesterday_max
           WHERE     curr.tsname = last_week.tsname
                 AND curr.tsname = yesterday.tsname
                 AND curr.tsname = last_week_max.tsname
                 AND curr.tsname = yesterday_max.tsname
                 AND curr.tsname NOT LIKE 'UNDO%')
ORDER BY days_left ASC
/
exit success
__EOF__
#
#----------------------------------------------------------------------------
# If SQL*Plus exited with a failure status, then exit the script also...
#----------------------------------------------------------------------------
Rtn=$?
if (( $Rtn != 0 ))
then
        case "$Rtn" in
                2) ErrMsg="$Pgm: Cannot connect using \"CONNECT / AS SYSDBA\"";;
                3) ErrMsg="$Pgm: spool of report failed";;
                4) ErrMsg="$Pgm: query in report failed" ;;
        esac
        notify_via_email
        exit $Rtn
fi
#
#----------------------------------------------------------------------------
# Send the report via email...
#----------------------------------------------------------------------------
ErrMsg="Tablespace Growth Report: $(date)"
grep "<<" $SpoolFile > /dev/null
if (( $? == 0 ))
then
        Level=WARNING
else
        Level=INFO
fi
notify_via_email
rm -f $SpoolFile > /dev/null 1>&2
#
#----------------------------------------------------------------------------
# Return the exit status from SQL*Plus...
#----------------------------------------------------------------------------
exit 0
