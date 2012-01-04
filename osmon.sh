#!/bin/ksh -p
#============================================================================
# File:         osmon.sh
# Type:         UNIX korn-shell script
# Author:       Austin Hackett
# Date:         11Oct11
#
# Description:
#
#       This script provides a quick and dirty way of getting some basic
#       operating system metric alerting in place. It has been tested on
#       Solaris 10 and Oracle Enterprise Linux 5. We use the sar command
#       to report system activity and send an alert when it breaches a
#       user specified threshold. Further email alerts will only be sent
#       if the threshold is cleared and then breached once again. This is
#       to prevent the DBA team being spammed with repeating alerts. To
#       this end, a "highwater" file is used to "remember" if we've sent
#       an alert already for a given metric. This logic is adapted from
#       an old HP-UX diskspace monitoring script by Bill Hassell that was
#       named diskspace.sh.
#
#       Using one of the many Open Source or commerical System Management
#       tools for OS monitoring is preferable, but in the absence of such 
#       a tool, this script might be useful.
#
#       Currently the following are implemented:
#
#       Memory Percent Used
#       CPU Percent Used
#       Swap Percent Used
#       Paging Activity
#
#       The reason for using sar instead of the multitude of other OS
#       monitoring tools available (iostat, vmstat, mpstat etc.) is
#       that it provides an Average value out of the box. The reason
#       this is imporant is that we want to avoid false alarms because
#       there happens to be a momentary spike when the script runs.
#       By taking n intervals every second and checking the average we
#       should only send an alert when utilization is continually high.
#
# Exit statuses:
#       0       normal succesful completion
#       1       failure
#
# Modifications:
#============================================================================
#============================================================================
########################## DEFINE CONSTANTS HERE ############################
#============================================================================
TRUE=1
FALSE=0
PROGRAM=${0##*/}
TEMPDIR=/var/tmp/${PROGRAM%.*}
HIWATER=$TEMPDIR/highwater
TEMPREADME=$TEMPDIR/README.txt
HIWATERTEMP=$TEMPDIR/highwater.tmp
MEMTEMP=$TEMPDIR/mem.txt
SWAPTEMP=$TEMPDIR/swap.txt
PAGETEMP=$TEMPDIR/page.txt
CPUTEMP=$TEMPDIR/cpu.txt
MAILTO=dba@mycompany.com
#============================================================================
########################## DEFINE FUNCTIONS HERE ############################
#============================================================================
#
#----------------------------------------------------------------------------
# Display a usage message for the script...
#----------------------------------------------------------------------------
function usage {
        cat  <<EOF
$PROGRAM - Monitor operating system metrics averaged across count 1 second
           intervals and send an alert when they exceed a given limit.
Usage: $PROGRAM [-c limit] [-p limit] [-m limit] [-s limit] [count]
  -c   check CPU percent used
  -p   check paging
  -m   check memory percent used
  -s   check swap used
EOF
}
#
#----------------------------------------------------------------------------
# Send an email notification. Whichever parameters are passed will suffix
# the email subject line. For example, passing the parameters CPU USAGE
# will result on an email subject line of "CPU USAGE warning from <host>"...
#----------------------------------------------------------------------------
function notify_via_email {
        print "On system $node: script $PROGRAM reports: $mailmsg" | \
            mailx -s "$@ warning from $node" $MAILTO
}
#
#----------------------------------------------------------------------------
# Print the passed string to standard error and exit with a return code of
# 1...
#----------------------------------------------------------------------------
function die {
        print "$*" 1>&2
        exit 1
}
#
#----------------------------------------------------------------------------
# This function is used to determine whether a metric alert should be
# raised. The function will return TRUE when the value of the metric
# (arg 1) exceeds the specified limit (arg2), and the threshold for the
# metric (arg 3) hasn't already breached...
#----------------------------------------------------------------------------
function evaluate_metric {
        typeset -i rcode=$FALSE value=$1 threshold=$2
        typeset metric="$3"
        #
        #--------------------------------------------------------------------
        # Over the limit?
        #--------------------------------------------------------------------
        if (( $value >= $threshold )) ; then
                #
                #------------------------------------------------------------
                # Check if the metric has already breached. If not, return
                # TRUE...
                #------------------------------------------------------------
                typeset beenthere=$(fgrep "$metric" $HIWATER)
                if [[ -z $beenthere ]]; then
                        print "$metric" >> $HIWATER
                        rcode=$TRUE

                fi
        else
                #
                #------------------------------------------------------------
                # If the current metric value falls below the limit value,
                # remove the 'remembered' metric from the HIWATER file.
                # Always test whether HIWATER has any entries at all...
                #------------------------------------------------------------
                if [[ -s $HIWATER ]]; then
                        fgrep -v "$metric" $HIWATER > $HIWATERTEMP
                        cat $HIWATERTEMP > $HIWATER
                fi
        fi
        return $rcode
}
#
#----------------------------------------------------------------------------
# Check whether used memory as a percentage of total memory exceeds the
# specified threshold. Send an email notifcation if it does...
#----------------------------------------------------------------------------
function memory_check {
        typeset -i mem_pct_used=0 usedmem=0
        #
        #--------------------------------------------------------------------
        # Determine current memory percent used...
        #--------------------------------------------------------------------
        case "$os" in
                SunOS)
                    #
                    #--------------------------------------------------------
                    # On Solaris, the prtconf command tells us the total
                    # physical memory on the machine...
                    #--------------------------------------------------------
                    typeset -i totmem=0
                    totmem=$(prtconf | grep "Memory size:" | awk '{print $3}')
                    #
                    #--------------------------------------------------------
                    # The sar command reports free memory in pages. The page
                    # size may vary from machine to machine, but we can use
                    # the pagesize command to determine what the page size is
                    # in bytes.
                    # freemem_mb = (freemem_pages * pagesize) / (1024 * 1024)
                    #--------------------------------------------------------
                    typeset freemempg=$(grep Average $MEMTEMP | \
                        awk '{print $2}')
                    typeset freemem=$(print "($freemempg * $(pagesize)) / \
                        (1024 * 1024)" | bc -l | awk '{printf "%d\n", $1}')
                    #
                    #--------------------------------------------------------
                    # Since sar tells us free memory and not used memory, we
                    # have determine used memory by substracting free memory
                    # from total memory...
                    #--------------------------------------------------------
                    usedmem=$(print "$totmem - $freemem" | bc -l | \
                        awk '{printf "%d\n", $1}')
                    #
                    #--------------------------------------------------------
                    # Now we have used memory and free memory, we can work
                    # out the percent used!
                    #--------------------------------------------------------
                    mem_pct_used=$(print "$usedmem / $totmem * 100" | bc -l \
                        | awk '{printf "%d\n", $1}')
                    #
                    #--------------------------------------------------------
                    # Determine whether or not we should send an email
                    # notification...
                    #--------------------------------------------------------
                    evaluate_metric $mem_pct_used $memory_limit mem_pct_used
                    if (( $? != 0 )) ; then
                        mailmsg="Memory is ${mem_pct_used}% used ($freemem"
                        mailmsg="$mailmsg Mbytes left), limit = "
                        mailmsg="$mailmsg ${memory_limit}%"
                        notify_via_email Memory
                    fi
                    ;;
                Linux)
                    #
                    #-------------------------------------------------------
                    # On Linux, buffers and cache aren't cleared unless more
                    # free RAM is needed. This is a performance optimization.
                    # So, to monitor how much memory is actually free we
                    # can't use memory % used as per sar, vmstat, top etc.
                    # These tools will always report a high percent used
                    # simply because Linux will use whatever free RAM is
                    # available for buffers and cache. We need to substract
                    # the memory used for buffers and cache from the total
                    # memory used and then divide this by total memory used.
                    #
                    # (kbmemused-kbbuffers-kbcached)/(kbmemfree+kbmemused)
                    #
                    # Note that ksh88 doesn't support floating point shell
                    # arithmetic, so we use awk to ensure memory percent
                    # used is a decimal integer.
                    #-------------------------------------------------------
                    usedmem=$(grep Average $MEMTEMP | awk '{print $3}')
                    typeset -i buffers=$(grep Average $MEMTEMP | \
                        awk '{print $5}')
                    typeset -i cached=$(grep Average $MEMTEMP | \
                        awk '{print $6}')
                    freemem=$(grep Average $MEMTEMP | awk '{print $2}')
                    mem_pct_used=$(print "(($usedmem - $buffers - $cached) \
                        / ($freemem + $usedmem)) * 100" | bc -l | \
                        awk '{printf "%d\n", $1}')
                    typeset -i actual_free=0
                    actual_free=$(print "$usedmem - $buffers - $cached" | \
                        bc -l | awk '{printf "%d\n", $1}')
                    #
                    #--------------------------------------------------------
                    # Determine whether or not we should send an email
                    # notification...
                    #--------------------------------------------------------
                    evaluate_metric $mem_pct_used $memory_limit mem_pct_used
                    if (( $? != 0 )) ; then
                        mailmsg="Memory is ${mem_pct_used}% used ("
                        mailmsg="$mailmsg $actual_free Kbytes left),"
                        mailmsg="$mailmsg limit = ${memory_limit}%"
                        notify_via_email Memory
                    fi
                    ;;
        esac
}
#
#----------------------------------------------------------------------------
# Check whether CPU utilization exceeds the specified threshold. Send an
# email notifcation if it does...
#----------------------------------------------------------------------------
function cpu_check {
        typeset -i cpu_pct_used=0
        case "$os" in
                SunOS)
                    #
                    #--------------------------------------------------------
                    # Sar does not report CPU percent used, but it does
                    # report percent idle, so we can determine precent used
                    # by subtracting it from 100..
                    #--------------------------------------------------------
                    cpu_pct_used=$(grep Average $CPUTEMP | \
                        awk '{printf "%d\n", 100 - $5}')
                    ;;
                Linux)
                    #
                    #--------------------------------------------------------
                    # Sar does not report CPU percent used, but it does
                    # report percent idle, so we can determine precent used
                    # by subtracting it from 100..
                    #--------------------------------------------------------
                    cpu_pct_used=$(grep Average $CPUTEMP | \
                        awk '{printf "%d\n", 100 - $8}')
                    ;;
        esac
        #
        #--------------------------------------------------------------------
        # Determine whether or not we should send an email notification...
        #--------------------------------------------------------------------
        evaluate_metric $cpu_pct_used $cpu_limit cpu_pct_used
        if (( $? != 0 )) ; then
                mailmsg="CPU is ${cpu_pct_used}% used, limit = ${cpu_limit}%"
                notify_via_email CPU
        fi
}
#
#----------------------------------------------------------------------------
# Check whether paging activity exceeds the specified threshold. Send an
# email notifcation if it does...
#----------------------------------------------------------------------------
function paging_check {
        typeset -i paging_activity=0
        case "$os" in
                SunOS)
                    #
                    #--------------------------------------------------------
                    # On Solaris we are interested in the pgscan/s column.
                    # Basically, the memory page scan rate.
                    #--------------------------------------------------------
                    paging_activity=$(grep Average $PAGETEMP | \
                        awk '{printf "%d\n", $5}')
                    ;;
                Linux)
                    #
                    #--------------------------------------------------------
                    # On Linux we are interested in the pswapout/s column.
                    # Basically, the number of pages swapped out per
                    # second
                    #--------------------------------------------------------
                    paging_activity=$(grep Average $PAGETEMP | \
                        awk '{printf "%d\n", $3}')
                    ;;
        esac
        #
        #--------------------------------------------------------------------
        # Determine whether or not we should send an email notification...
        #--------------------------------------------------------------------
        evaluate_metric $paging_activity $paging_limit paging_activity
        if (( $? != 0 )) ; then
                case "$os" in
                    SunOS)
                        mailmsg="The memory page scan rate is"
                        mailmsg="$mailmsg ${paging_activity},"
                        mailmsg="$mailmsg limit = ${paging_limit}"
                        notify_via_email Paging
                        ;;
                    Linux)
                        ;;
                esac
        fi
}

function swap_check {
        typeset -i swap_pct_used=0 freeswap=0
        case "$os" in
                SunOS)
                    #
                    #--------------------------------------------------------
                    # On Solaris, "swap -s" will tell us the amount of swap
                    # available and used in Kbytes. By adding these together
                    # we have the total amount of swap configured on the
                    # system. We need this to work out what percent of swap
                    # is used...
                    #--------------------------------------------------------
                    typeset -i totswap=$(swap -s | awk '{print $9,$11}' | \
                        sed -e 's/k//g' | awk  '{print $1 + $2}')
                    #
                    #--------------------------------------------------------
                    # Sar reports free swap is 512 Byte disk blocks.
                    # Dividing free swap by 2 will give us free swap in KB...
                    #--------------------------------------------------------
                    freeswap=$(grep Average $SWAPTEMP | \
                        awk '{printf "%d\n", $3 / 2}')
                    #
                    #--------------------------------------------------------
                    # Since sar tells us free swap and not used swap, we
                    # have determine used swap by substracting free swap
                    # from total swap...
                    #--------------------------------------------------------
                    typeset -i usedswap=0
                        ((usedswap = totswap - freeswap))
                    #
                    #--------------------------------------------------------
                    # Now we have used swap and free swap, we can work
                    # out the percent used!
                    #--------------------------------------------------------
                    swap_pct_used=$(print "$usedswap $totswap" | \
                        awk '{printf "%d\n", $1 / $2 * 100}')
                    ;;
                Linux)
                    #
                    #--------------------------------------------------------
                    # On Linux we are interested in the %swpused column...
                    #--------------------------------------------------------
                    swap_pct_used=$(grep Average $SWAPTEMP \
                        | awk '{printf "%d\n", $9}')
                    #
                    #--------------------------------------------------------
                    # We also need swap free for the email notification...
                    #--------------------------------------------------------
                    freeswap=$(grep Average $SWAPTEMP \
                        | awk '{printf "%d\n", $7}')
                    ;;
        esac
        #
        #--------------------------------------------------------------------
        # Determine whether or not we should send an email notification...
        #--------------------------------------------------------------------
        evaluate_metric $swap_pct_used $swap_limit swap_pct_used
        if (( $? != 0 )) ; then
                mailmsg="Swap is ${swap_pct_used}% used ($freeswap Kbytes"
                mailmsg="$mailmsg left), limit = ${swap_limit}%"
                notify_via_email Swap
        fi
}
#============================================================================
############################ BEGINNING OF MAIN ##############################
#============================================================================
typeset -i cpu_flag=$FALSE
typeset -i paging_flag=$FALSE
typeset -i memory_flag=$FALSE
typeset -i swap_flag=$FALSE
typeset -i count=10
typeset -i cpu_limit=0
typeset -i paging_limit=0
typeset -i memory_limit=0
typeset -i swap_limit=0
typeset -i metric_specified=$FALSE
#
#----------------------------------------------------------------------------
# Process the command line options...
#----------------------------------------------------------------------------
while getopts "c:hp:m:s:" arg
do
        case $arg in
            c)
                cpu_flag=$TRUE
                cpu_limit="$OPTARG"
                metric_specified=$TRUE
                ;;
            h)
                usage
                exit 0
                ;;
            p)
                paging_flag=$TRUE
                paging_limit="$OPTARG"
                metric_specified=$TRUE
                ;;
            m)
                memory_flag=$TRUE
                memory_limit="$OPTARG"
                metric_specified=$TRUE
                ;;
            s)
                swap_flag=$TRUE
                swap_limit="$OPTARG"
                metric_specified=$TRUE
                ;;
            *)
                usage
                exit 1
                ;;
        esac
done

shift $(($OPTIND - 1))
#
#----------------------------------------------------------------------------
# Process command-line parameters
#----------------------------------------------------------------------------
(( $# > 0 )) && count=$1
(( $count <= 1 )) && die You must specifiy a count that is greater than 1
#
#----------------------------------------------------------------------------
# Verify that at least one metric option was specified...
#----------------------------------------------------------------------------
(( $metric_specified == $FALSE )) && \
    die "You must specify at least one metric to monitor!"
#
#----------------------------------------------------------------------------
# The location of the uname binary is platform dependent, so use the correct
# location for this machine
#----------------------------------------------------------------------------
if [[ -e /usr/bin/uname ]]; then
        os=$(/usr/bin/uname -s)
elif [[ -e /bin/uname ]]; then
        os=$(/bin/uname -s)
else
        die "Unable to find uname in /usr/bin or /bin!"
fi
#
#----------------------------------------------------------------------------
# Make sure the TEMPDIR directory exists. If not, create it and add a README
# file...
#----------------------------------------------------------------------------
if [[ ! -d $TEMPDIR ]]; then
        umask 022
        mkdir $TEMPDIR
        if (( $? != 0 )) ; then
                die Unable to create directory $TEMPDIR
        fi
        cat > $TEMPREADME <<EOF
This directory is used by the $PROGRAM script which is typically run
from cron to monitor diskspace. To prevent endless repeating messages
about high operating system metric utilization, this directory
remembers previous warnings and will not repeat a warning unless the
threshold breach is first cleared.

If this directory is deleted, it will be recreated automatically when
$PROGRAM runs again.
EOF
fi
#
#----------------------------------------------------------------------------
# To simplify coding later, make sure there is always a HIWATER file even
# though it is zero length...
#----------------------------------------------------------------------------
touch $HIWATER || die "Unable to touch file \"$HIWATER\""
#
#----------------------------------------------------------------------------
# Run sar command with the flags need to gather the system metrics of
# interest and capture the output in a file for use later. Each execution
# of sar is run as a background task. We run the sar commands in parallel
# to reduce script runtime and to ensure that all metrics are looking at
# the same period of time and so can be correlated by the DBA...
#----------------------------------------------------------------------------
case "$os" in
        SunOS)
            PATH=/bin:/usr/sbin; export PATH
            node=$(uname -n)
            (( $memory_flag == $TRUE )) && sar -r 1 $count > $MEMTEMP &
            (( $paging_flag == $TRUE )) && sar -g 1 $count > $PAGETEMP &
            (( $cpu_flag == $TRUE )) && sar -u 1 $count > $CPUTEMP &
            (( $swap_flag == $TRUE )) && sar -r 1 $count > $SWAPTEMP &
            ;;
        Linux)
            PATH=/bin:/usr/bin; export PATH
            node=$(uname -n)
            (( $memory_flag == $TRUE )) && sar -r 1 $count > $MEMTEMP &
            (( $paging_flag == $TRUE )) && sar -W 1 $count > $PAGETEMP &
            (( $cpu_flag == $TRUE )) && sar -u 1 $count > $CPUTEMP &
            (( $swap_flag == $TRUE )) && sar -r 1 $count > $SWAPTEMP &
            ;;
        *)
            die "\"$os\" Operating System not currently supported!"
            ;;
esac
#
#----------------------------------------------------------------------------
# Wait for the sar commands to complete...
#----------------------------------------------------------------------------
wait
#
#----------------------------------------------------------------------------
# Call the relevent metric check procedures for the command-line options that
# were specified.
#----------------------------------------------------------------------------
(( $memory_flag == $TRUE )) && memory_check
(( $paging_flag == $TRUE )) && paging_check
(( $cpu_flag == $TRUE )) && cpu_check
(( $swap_flag == $TRUE )) && swap_check
# End of Script
