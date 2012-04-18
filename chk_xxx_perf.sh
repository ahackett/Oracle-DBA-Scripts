#!/bin/ksh -p
#============================================================================
# File:         chk_xxxx_perf.sh
# Type:         UNIX korn-shell script
# Author:       Austin Hackett
# Date:         08Jan12
#
# Description:
#
#       Check the V$SQL_MONITOR view for certain queries running more
#       than n seconds. Customize the SELECT statement executed by this
#       script to fit your purposes. We maintain a record of the current 
#	time when the script runs in order to implement a moving time 
#	window that ensures we'll never miss an exection.
#
#	Much of this script is adapted and from Tim Gorman's UNIX shell
#	scripts library at http://www.evdbt.com/tools.htm
#
# Exit statuses:
#       0       normal succesful completion
#       1       ORACLE_SID or Elapsed Seconds not specified - user error
#       2       Elapsed seconds is not a number - user error
#       3       Instance ORACLE_SID is not up
#       4       ORACLE_SID is not valid in ORATAB - user error
#       5       Environment variable not set by ORATAB
#       6       "adhoc" directory not found
#       7       Last run date in "log" file isn't a valid date
#       8       Cannot connect to instance ORACLE_SID as SYSDBA
#       9       Failed to create SQL*Plus spool file
#       10      SQL statement did not run successfully
#       11      One or more long running queries found
#
# Modifications:
#============================================================================
Pgm=chk_xxx_perf
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
        cat << __EOF__ | mailx -s "$Pgm $OraSid" dba@mycompany.com
$ErrMsg

Place some custom text here, if you wish...
$([ -f $SpoolFile ] && uuencode $SpoolFile xxx.txt)
__EOF__
} # ...end of shell function "notify_via_email"...
#
#----------------------------------------------------------------------------
# Verify that the ORACLE_SID has been specified on the UNIX command-line...
#----------------------------------------------------------------------------
if (( $# != 2 ))
then
        echo "Usage: $Pgm.sh ORACLE_SID Elapsed_Seconds; aborting..."
        exit 1
fi
OraSid=$1
Elapsed=$2
#
#----------------------------------------------------------------------------
# Check that value specified for Elapsed_Seconds is a number...
#----------------------------------------------------------------------------
expr $Elapsed + 0 > /dev/null 2>&1
if (( $? != 0 ))
then
        echo "Value specified for Elapsed_Seconds is not an integer; aborting..."
        exit 2
fi
#
#----------------------------------------------------------------------------
# Verify that the database instance specified is "up"...
#----------------------------------------------------------------------------
Up=`ps -eaf | grep ora_pmon_${OraSid} | grep -v grep | awk '{print $NF}'`
if [[ -z $Up  ]]
then
        exit 3
fi
#
#----------------------------------------------------------------------------
# Verify that the ORACLE_SID is registered in the ORATAB file...
#----------------------------------------------------------------------------
dbhome $OraSid > /dev/null 2>&1
if (( $? != 0 ))
then
        echo "$Pgm: \"$OraSid\" not local to this host; aborting..."
        exit 4
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
# Locate the script's log file directory...
#----------------------------------------------------------------------------
if [[ -z $ORACLE_BASE ]]
then
        echo "Env var \"ORACLE_BASE\" not set; aborting..."
        exit 5
fi
if [[ -z $ORACLE_SID ]]
then
        echo "Env var \"ORACLE_SID\" not set; aborting..."
        exit 5
fi
LogDir=$ORACLE_BASE/admin/$ORACLE_SID/adhoc
if [ ! -d $LogDir ]
then
        echo "Logging directory \"$LogDir\" not found; aborting..."
        exit 6
fi
#
#----------------------------------------------------------------------------
# Locate the script's "log" file; if it doesn't exit, then initialize it.
# If it already exits but has grown too large (i.e. over 100 lines), then
# trim it by re-initializing it...
#
# The last line of the "log" file contains "contextual" information for this
# script to use, namely the last time the script ran...
#----------------------------------------------------------------------------
Log=$LogDir/${Pgm}_state.log
if [ -r $Log ]
then
        NbrLines=$(wc -l $Log | awk '{print $1}')
        if (( $NbrLines >= 100 ))
        then
                Line=$(tail -1 $Log)
                echo "# file re-initialized on \"$(date)\"" > $Log
                echo "# PLEASE DO NOT edit this file" >> $Log
                echo $Line >> $Log
        fi
else
        echo "# file initialized on \"$(date)\"" > $Log
        echo "# PLEASE DO NOT edit this file" >> $Log
        echo "01/01/1970 00:00:00" >> $Log
        chmod 640 $Log
fi
#
#----------------------------------------------------------------------------
# Extract the last time the script ran from the last line of the "log"
# file...
#----------------------------------------------------------------------------
LastTime=$(tail -1 $Log)
#
#----------------------------------------------------------------------------
# Make sure the date is in the expected format - nobody manually edited the
# "log" file...
#----------------------------------------------------------------------------
echo $LastTime | grep "^[0-9][0-9]/[0-9][0-9]/[0-9][0-9][0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]$"
if (( $? != 0 ))
then
        echo "Last run date in \"log\" file (\"$LastTime\") not in expected format; aborting..."
        exit 7
fi
#
#----------------------------------------------------------------------------
# Get the current time. This is what will be appended to the "log" file at
# the end of this script and therefore becomes the last time the script
# ran. This will be picked up on the next execution. In this way we maintain
# a moving window of data that ensures no long running SQL is ever missed...
#----------------------------------------------------------------------------
CurrTime=$(date '+%d/%m/%Y %H:%M:%S')
#
#----------------------------------------------------------------------------
# Trim the "log" file to only the most recent 10 lines...
#----------------------------------------------------------------------------
TrimLogFile=$(tail -10 $Log)
echo "$TrimLogFile" > $Log
#
#----------------------------------------------------------------------------
# Check the field values are in the expected format...
#----------------------------------------------------------------------------
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
whenever oserror exit 8
whenever sqlerror exit 8
connect / as sysdba
whenever oserror exit 9
whenever sqlerror exit 10
set echo off feedb off timi off pau off pages 60 lines 32767 trimsp on head on long 2000000 longchunksize 2000000
spool $SpoolFile
col binds_xml word_wrapped
col etime for 999.99
var v_from_date varchar2(20)
var v_to_date   varchar2(20)
exec :v_from_date := '$LastTime'
exec :v_to_date   := '$CurrTime'
select program,
       sql_id,
       sql_plan_hash_value,
       sql_exec_id,
       to_char (sql_exec_start, 'dd/mm/yyyy hh24:mi:ss') sql_exec_start,
       elapsed_time / 1000000 etime,
       buffer_gets,
       disk_reads,
       case
         when binds_xml is not null then xmltype (binds_xml)
         else null
       end binds_xml
  FROM v\$sql_monitor
 WHERE sql_exec_start >= to_date (:v_from_date, 'dd/mm/yyyy hh24:mi:ss')
       and sql_exec_start < to_date (:v_to_date, 'dd/mm/yyyy hh24:mi:ss')
       and elapsed_time / 1000000 >= $Elapsed
       --- and further predicates are required
ORDER BY etime DESC
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
                7) ErrMsg="$Pgm: Cannot connect using \"CONNECT / AS SYSDBA\"";;
                8) ErrMsg="$Pgm: spool of report failed";;
                9) ErrMsg="$Pgm: query in report failed" ;;
        esac
        notify_via_email
        exit $Rtn
fi
#
#----------------------------------------------------------------------------
# Log new starting values to the "log" file for the next time this script is
# executed...
#----------------------------------------------------------------------------
echo "$CurrTime" >> $Log
#
#----------------------------------------------------------------------------
# If the report contains something, then notify the authorities!
#----------------------------------------------------------------------------
if [ -s $SpoolFile ]
then
        ErrMsg="$Pgm: long running xxx queries ($LastTime - $CurrTime)"
        notify_via_email
        rm -f $SpoolFile
        exit 11
else
        rm -f $SpoolFile
fi
#
#----------------------------------------------------------------------------
# Return the exit status from SQL*Plus...
#----------------------------------------------------------------------------
exit 0
