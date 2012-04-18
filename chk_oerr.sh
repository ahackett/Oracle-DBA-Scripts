#!/bin/ksh -p
#============================================================================
# File:         chk_oerr.sh
# Type:         UNIX korn-shell script
# Author:       Austin Hackett
# Date:         23Feb12
#
# Description:
#
#       Check each ADR Home for alerts, incidents, and problems. We maintain
#       a record of the current time when the script runs in order to
#       implement a moving window that ensures we'll never miss an issue.
#
#	Much of this script is adapted and from Tim Gorman's UNIX shell
#	scripts library at http://www.evdbt.com/tools.htm
#
#	The idea of using adrci for this task was from a blog post by
#	Coskan Gundogar:
#
#		http://coskan.wordpress.com/?s=adrci
#
# Exit statuses:
#       0       normal succesful completion
#       1       An error occurred
#       2       One or more alerts, incidents, or problems were found
#
# Modifications:
#============================================================================
Pgm=chk_oerr
SendEmail=0
ReturnCode=0
#
#----------------------------------------------------------------------------
# Set the correct PATH for the script...
#----------------------------------------------------------------------------
PATH=/usr/bin:/usr/local/bin; export PATH
#
#----------------------------------------------------------------------------
# Korn-shell function to send email notifications...
#----------------------------------------------------------------------------
notify_via_email() # ...use email to notify people...
{
        cat << __EOF__ | mailx -s "$Pgm $(uname -n)" dba@mycompany.com
$ErrMsg
__EOF__
} # ...end of shell function "notify_via_email"...
#
#----------------------------------------------------------------------------
# Korn-shell function to send email notifications...
#----------------------------------------------------------------------------
check_adr_home() # ...check ADR home for alerts, problems, and incidents
{
        #
        #--------------------------------------------------------------------
        # In the ADR, alert creation times etc. are stored as systimestamps.
        # This means that we need to know the timzone used for a given ADR
        # home. Since the last entry of the alert log will contain this info
        # we can use it to extract the timezone. However, if the ADR was
        # purged recently, then a tail of the alert log will raise an
        # ADR-48156 "Alert log purge has occurred" in which case we'll skip
        # this home because there is no alert log to check for issues...
        #--------------------------------------------------------------------
        Line=$(adrci exec="set home $AdrHome; show alert -tail 1" | head -1)
        echo $Line | grep "DIA-48156" > /dev/null
        (( $? == 0 )) && return
        TimeZone=$(echo $Line | awk '{print $3}')
        echo $TimeZone | grep "\+[0-9][0-9]:[0-9][0-9]" > /dev/null
        if (( $? == 0 ))
        then
                #------------------------------------------------------------
                # Obtain a list of alerts, incidents, and problems that
                # have occurred since the script last ran...
                #------------------------------------------------------------
                if [[ $HomeType = "tnslsnr" ]]
                then
                        adrci exec="set home $AdrHome; show alert -p \\\"message_text like '%TNS-%' and originating_timestamp >= '$LastTime.000000 $TimeZone' and originating_timestamp < '$CurrTime.000000 $TimeZone'\\\"" -term > $TempFile
                else
                        adrci exec="set home $AdrHome; show alert -p \\\"(message_text like '%ORA-%' or message_text like '%CORRUPT%') and originating_timestamp >= '$LastTime.000000 $TimeZone' and originating_timestamp < '$CurrTime.000000 $TimeZone'\\\"" -term > $TempFile
                fi
                LineCount=$(cat $TempFile | sed '/^$/d' | egrep -v "^ADR Home =|^\*" | wc -l)
                if (( $LineCount > 0 ))
                then
                        echo "" >> $ReportFile
                        echo "Alerts for ADR Home $AdrHome" >> $ReportFile
                        echo "*************************************************************************" >> $ReportFile
                        cat $TempFile >> $ReportFile
                        SendEmail=1
                fi
                adrci exec="set home $AdrHome; show incident -p \\\"create_time >= '$LastTime.000000 $TimeZone' and create_time < '$CurrTime.000000 $TimeZone'\\\"" > $TempFile
                LineCount=$(cat $TempFile | sed '/^$/d' | egrep -v "^ADR Home =|^\*|^0 rows fetched" | wc -l)
                if (( $LineCount > 0 ))
                then
                        echo "" >> $ReportFile
                        echo "Incidents for ADR Home $AdrHome" >> $ReportFile
                        echo "*************************************************************************" >> $ReportFile
                        cat $TempFile >> $ReportFile
                        SendEmail=1
                fi
                adrci exec="set home $AdrHome; show problem -p \\\"lastinc_time >= '$LastTime.000000 $TimeZone' and lastinc_time < '$CurrTime.000000 $TimeZone'\\\"" > $TempFile
                LineCount=$(cat $TempFile | sed '/^$/d' | egrep -v "^ADR Home =|^\*|^0 rows fetched" | wc -l)
                if (( $LineCount > 0 ))
                then
                        echo "" >> $ReportFile
                        echo "Problems for ADR Home $AdrHome" >> $ReportFile
                        echo "*************************************************************************" >> $ReportFile
                        cat $TempFile >> $ReportFile
                        SendEmail=1
                fi
        else
                ErrMsg="Unable to determine timezone for ADR HOME \"$AdrHome\" (Line=\"$Line\")"
                notify_via_email
        fi
} #...end of shell function "check_adr_home"...
#
#----------------------------------------------------------------------------
# Verify that an ORACLE_HOME has been specified on the UNIX command-line...
#----------------------------------------------------------------------------
if (( $# != 1 ))
then
        echo "Usage: $Pgm.sh ORACLE_HOME; aborting..."
        exit 1
fi
OraHome=$1
#
#----------------------------------------------------------------------------
# Verify that the specified ORACLE_HOME exists...
#----------------------------------------------------------------------------
if [ ! -d $OraHome ]
then
        echo "Directory \"$OraHome\" not found; aborting..."
        exit 1
fi
#
#----------------------------------------------------------------------------
# Set the Oracle environment variables for this Oracle home...
#----------------------------------------------------------------------------
export ORACLE_HOME=$OraHome
export PATH=$ORACLE_HOME/bin:$PATH
#
#----------------------------------------------------------------------------
# Check that adrci brinary is present...
#----------------------------------------------------------------------------
if [ ! -x $ORACLE_HOME/bin/adrci ]
then
        echo "adrci binary does not exist or is not executable; aborting.."
fi
#
#----------------------------------------------------------------------------
# Locate the script's log file directory; if it doesn't exist, then create
# it...
#----------------------------------------------------------------------------
LogDir=/var/tmp/$Pgm
if [ ! -d $LogDir ]
then
        mkdir -p $LogDir
        if (( $? != 0 ))
        then
                echo "Could not create Logging directory \"$LogDir\"; aborting..."
                exit 1
        fi
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
        echo "1970-01-01 00:00:00" >> $Log
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
echo $LastTime | grep "^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]$" > /dev/null
if (( $? != 0 ))
then
        echo "Last run date in \"log\" file (\"$LastTime\") not in expected format; aborting..."
        exit 1
fi
#
#----------------------------------------------------------------------------
# Get the current time. This is what will be appended to the "log" file at
# the end of this script and therefore becomes the last time the script
# ran. This will be picked up on the next execution. In this way we maintain
# a moving window of data that ensures no adr events are ever missed...
#----------------------------------------------------------------------------
CurrTime=$(date '+%Y-%m-%d %H:%M:%S')
#
#----------------------------------------------------------------------------
# Trim the "log" file to only the most recent 10 lines...
#----------------------------------------------------------------------------
TrimLogFile=$(tail -10 $Log)
echo "$TrimLogFile" > $Log
#
#----------------------------------------------------------------------------
# Locate the script's "report" file which forms the email body if any
# alerts, incidents, and problems are found. Also, the "temp" file
# which is used to capture a list of alerts, incidents, and problems for
# an ADR home. If any are found, these are appended to the report file...
#----------------------------------------------------------------------------
ReportFile=$LogDir/report.txt
TempFile=/tmp/${Pgm}$(echo $ORACLE_HOME | tr '/' '_').out
#
#----------------------------------------------------------------------------
# Add a report title to the "report" file...
#----------------------------------------------------------------------------
echo "Oracle Error Report For Period $LastTime - $CurrTime" > $ReportFile
echo "*************************************************************************" >> $ReportFile
#
#----------------------------------------------------------------------------
# Gather all database and ASM homes in the ADR for this ORACLE_HOME into an
# array...
#----------------------------------------------------------------------------
AdrHomes=$(adrci exec="show homes" | egrep "rdbms|asm")
HomeType=rdbms_or_asm
#
#----------------------------------------------------------------------------
# Check the ADR home for alerts, incidents, and problems...
#----------------------------------------------------------------------------
for AdrHome in ${AdrHomes[@]}
do
        check_adr_home
done
#
#----------------------------------------------------------------------------
# Gather all database and ASM homes in the ADR for this ORACLE_HOME into an
# array...
#----------------------------------------------------------------------------
AdrHomes=$(adrci exec="show homes" | grep tnslsnr)
HomeType=tnslsnr
#
#----------------------------------------------------------------------------
# Check the ADR home for alerts, incidents, and problems...
#----------------------------------------------------------------------------
for AdrHome in ${AdrHomes[@]}
do
        check_adr_home
done
#
#----------------------------------------------------------------------------
# Log new starting values to the "log" file for the next time this script is
# executed...
#----------------------------------------------------------------------------
echo "$CurrTime" >> $Log
#
#----------------------------------------------------------------------------
# Send an email notification as required...
#----------------------------------------------------------------------------
if (( $SendEmail == 1 ))
then
        ErrMsg="$(cat $ReportFile)"
        notify_via_email
        ReturnCode=2
fi
#
#----------------------------------------------------------------------------
# Remove the "temp" file and exit...
#----------------------------------------------------------------------------
rm -f $TempFile
exit $ReturnCode
