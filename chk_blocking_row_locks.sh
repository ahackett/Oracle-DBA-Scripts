#!/bin/ksh -p
#============================================================================
# File:         chk_blocking_row_locks.sh
# Type:         UNIX korn-shell script
# Author:       Austin Hackett
# Date:         13Jan12
#
# Description:
#
#       Check whether any sessions have been blocked on the TX and TS
#       enqueue for more than $Minutes minutes.
#
#	Much of this script is adapted and from Tim Gorman's UNIX shell
#	scripts library at http://www.evdbt.com/tools.htm
#
# Exit statuses:
#       0       normal succesful completion
#       1       ORACLE_SID not specified - user error
#       2       Cannot connect using "CONNECT / AS SYSDBA"
#       3       SQL*Plus failed to create "spool" file for report
#       4       SQL*Plus failed while running v$session count
#       5       SQL*Plus failed while creating block_tree GTT
#       6       SQL*Plus failed while inserting into block_tree GTT
#       7       SQL*Plus failed while commiting insert into block_tree GTT
#       8       SQL*Plus failed while querying block_tree GTT
#       9       Something is blocked - check report!!
#
# Modifications:
#
#       08-Mar-2012     Austin Hackett
#
#       A bug in 11.2.0.2 means that the original block tree query created
#       a new child cursor upon each execution. Obviously, this was not
#       acceptable, so query was rewritten not to use subquery factoring.
#       Since the new query uses a subquery, we populate a GTT with the
#       contents of v$session. This prevents the query from displaying
#       "rogue" records due to fact that v$ views don't provide read
#       consistency.
#
#============================================================================
Minutes=3
Pgm=chk_blocking_row_locks.sh
#
#----------------------------------------------------------------------------
# Set the correct PATH for the script...
#----------------------------------------------------------------------------
PATH=/usr/bin:/usr/local/bin; export PATH
#
#----------------------------------------------------------------------------
# Korn-shell function to be called multiple times in the script...
#----------------------------------------------------------------------------
notify_via_email() # ...use email to notify people...
{
        echo "$ErrMsg" | mailx -s "$Pgm $OraSid" dba@mycompany.com
} # ...end of shell function "notify_via_email"...
#
#----------------------------------------------------------------------------
# Verify that the ORACLE_SID has been specified on the UNIX command-line...
#----------------------------------------------------------------------------
if (( $# != 1 ))
then
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
# Connect via SQL*Plus and product the report...
#----------------------------------------------------------------------------
sqlplus -s /nolog << __EOF__ > /dev/null 2>&1
whenever oserror exit 2
whenever sqlerror exit 2
connect / as sysdba
whenever oserror exit 3
whenever sqlerror exit 4
set echo off feedb off timi off pau off pages 60 lines 500 trimsp on head off
spool /tmp/chk_blocking_row_locks_${ORACLE_SID}.lst
col sid for a14
col serial# for 9999999
col secs for 9999
col object_name for a20 trunc
col sql_text for a40
col program for a19 trunc
col event for a30
col osuser for a10 trunc
col line for a100
SELECT 'There are ' || TO_CHAR (cnt)
       || ' sessions that have been waiting on a row lock for more than $Minutes minutes continuously'
          line
  FROM (SELECT COUNT (*) cnt
          FROM v\$session
         WHERE event IN
                  ('enq: TX - row lock contention',
                   'enq: TM - contention')
               AND state = 'WAITING'
               AND wait_time_micro > $Minutes * 60 * 1000000)
/
whenever sqlerror exit 5
set head on
prompt
prompt Here is the blocking session tree...
prompt
DECLARE
   e_already_exists   EXCEPTION;
   PRAGMA EXCEPTION_INIT (e_already_exists, -955);
BEGIN
   EXECUTE IMMEDIATE
      'create global temporary table dba_tools.block_tree (sid number,
                   serial# number,
                   osuser varchar2(30) ,
                   program varchar2(48),
                   event varchar2(64),
                   state varchar2(19),
                   wait_time_micro number,
                   blocking_session number ,
                   row_wait_obj# number,
                   sql_id varchar2(13)) on commit preserve rows';
EXCEPTION
   WHEN e_already_exists
   THEN
      NULL;
END;
/
whenever sqlerror exit 6
INSERT INTO DBA_TOOLS.BLOCK_TREE (SID,
                                  SERIAL#,
                                  OSUSER,
                                  PROGRAM,
                                  EVENT,
                                  STATE,
                                  WAIT_TIME_MICRO,
                                  BLOCKING_SESSION,
                                  ROW_WAIT_OBJ#,
                                  SQL_ID)
   SELECT SID,
          SERIAL#,
          OSUSER,
          PROGRAM,
          EVENT,
          STATE,
          WAIT_TIME_MICRO,
          BLOCKING_SESSION,
          ROW_WAIT_OBJ#,
          SQL_ID
     FROM v\$session
/
whenever sqlerror exit 7
COMMIT;
whenever sqlerror exit 8
    SELECT LPAD (' ', LEVEL) || sid sid,
           serial#,
           osuser,
           program,
           event,
           ROUND (wait_time_micro / 1000000) secs,
           object_name,
           SUBSTR (sql_text, 1, 40) sql_text
      FROM (SELECT t.sid,
                   t.serial#,
                   t.osuser,
                   t.program,
                   t.event,
                   t.state,
                   t.wait_time_micro,
                   t.blocking_session,
                   o.object_name,
                   s.sql_text
              FROM dba_tools.block_tree t, dba_objects o, v\$sql s
             WHERE     (   sid IN
                              (SELECT blocking_session FROM dba_tools.block_tree)
                        OR blocking_session IS NOT NULL)
                   AND t.row_wait_obj# = o.object_id(+)
                   AND t.sql_id = s.sql_id(+))
CONNECT BY PRIOR sid = blocking_session
START WITH blocking_session IS NULL
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
                3) ErrMsg="$Pgm: spool of blocking-row-lock-report failed";;
                4) ErrMsg="$Pgm: query of v\$session failed" ;;
                5) ErrMsg="$Pgm: Cannot create dba_tools.block_tree" ;;
                6) ErrMsg="$Pgm: insert into dba_tools.block_tree failed" ;;
                7) ErrMsg="$Pgm: commiting insert into dba_tools.block_tree failed" ;;
                8) ErrMsg="$Pgm: query of ba_tools.block_tree failed" ;;
        esac
        notify_via_email
        exit $Rtn
fi
#
#----------------------------------------------------------------------------
# If the report contains waiting sessions, then notify the authorities!
#----------------------------------------------------------------------------
grep "There are 0 sessions that have been waiting" /tmp/chk_blocking_row_locks_${ORACLE_SID}.lst > /dev/null 2>&1
Blocking=$?
if (( $Blocking == 1 ))
then
        ErrMsg="$Pgm:\n`cat /tmp/chk_blocking_row_locks_${ORACLE_SID}.lst`"
        notify_via_email
        rm -f /tmp/chk_blocking_row_locks_${ORACLE_SID}.lst
        exit 9
else
        rm -f /tmp/chk_blocking_row_locks_${ORACLE_SID}.lst
fi
#
#----------------------------------------------------------------------------
# Return the exit status from SQL*Plus...
#----------------------------------------------------------------------------
exit 0
