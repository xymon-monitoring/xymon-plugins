#!/bin/bash

# openmanage.sh: Use Dell OpenManage to monitor hardware
#
# version 0.56
#
# Dell OpenManage XYMON script to monitor various pieces of hardware using the
# cli (omreport)
#
# Written by: Brian Smith-Sweeney
# Last Updated: December 6th, 2002
#
# This is my first attempt at a BigBrother script.  I've only tested this 
# script thus far on a RedHat 7.3 box with the ServerAdministrator-1.0-0,
# dellomsa-drivers-4.70-3613, and dellomsa-4.70-3613 rpms from Dell (although
# the version of ServerAdministrator is actually 1.2.3, not as the RPM implies
# 1.0)  I have tested chassis intrusion, power supply failure, and fan failure in 
# "real" situations", and the other options by passing it faked data.
#
# If you find the script useful or have questions/suggestions/flames 
# please drop me a line at bsweeney@physics.ucsb.edu.   Please note, as of yet
# this script has not been tested extensively; if you have good luck with it
# let me know.  I'll (hopefully) be updating this script fairly frequently 
# over the next few months, so check back on deadcat.net for updates.
#
# Copyright 2002 Regents of the University of California. 
# All Rights Reserved.
#
# Permission to use, copy, modify, and distribute this software and its 
# documentation for educational, research and non-profit purposes, without fee,
# and without a written agreement is hereby granted, provided that the above
# copyright notice, this paragraph and the following three paragraphs appear 
# in all copies.
#
# Permission to incorporate this software into commercial products may be 
# obtained by contacting the University of California at 
# randall.stoskopfe@purc.ucsb.edu
#
# This software program and documentation are copyrighted by The Regents of the
# University of California. The software program and documentation are supplied
# "as is", without any accompanying services from The Regents. The Regents 
# does not warrant that the operation of the program will be uninterrupted or 
# error-free. The end-user understands that the program was developed for 
# research purposes and is advised not to rely exclusively on the program for 
# any reason.
#
# IN NO EVENT SHALL THE UNIVERSITY OF CALIFORNIA BE LIABLE TO ANY PARTY FOR 
# DIRECT, INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES, INCLUDING 
# LOST PROFITS, ARISING OUT OF THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION,
# EVEN IF THE UNIVERSITY OF CALIFORNIA HAS BEEN ADVISED OF THE POSSIBILITY OF 
# SUCH DAMAGE. THE UNIVERSITY OF CALIFORNIA SPECIFICALLY DISCLAIMS ANY 
# WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF 
# MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE SOFTWARE PROVIDED 
# HEREUNDER IS ON AN "AS IS" BASIS, AND THE UNIVERSITY OF CALIFORNIA HAS NO 
# OBLIGATIONS TO PROVIDE MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR 
# MODIFICATIONS. 
#
# Author's copyright request: if you do modify/redistribute this script, please
# leave my name in it.
#
# USAGE
# Standard XYMON external test.  Put this file in $XYMONHOME/ext on the Dell server
# running OpenManage and add a line to the $XYMONHOME/etc/bb-bbexttab like 
# the following:
#
#  : : openmanage.sh;60
#
# where the number after the semicolon represents how frequently (in seconds)
# you'd like the openmanage script to run.
#
#
# KNOWN BUGS:
# None, but there is a minor gotcha.  The output from some of the level-3
# omreport commands are somewhat extensive, and XYMON has a limit on how large
# a message you can send, so if multiple components have errors you may
# get a DATA TRUNCATED line in your XYMON openmanage status page.
#
#
# TODO:
# * Fix the above truncation problem by further parsing the output of the
#   level-3 commands to list only the sensors reporting problems
# * Add more support for the level-2 command "omreport system" and subsequent
#   level-3 commands
# * Add support for ignoring some components
# * Find the "unknown" bugs 
# * Maybe rewrite in perl when I get to parsing the logs
# * Add omdiag command?
# * Possibly divide up report pages
#
#
# HISTORY
# 0.1 - First version
# * Just parses the basics from omreport chassis
# 0.2 
# * Added "Command level 3" stuff for omreport chassis when level-2 command
#   reports issues
# 0.3 
# * Commented existing code
# 0.4
# * Fixed multi-word level-2 command output
# * Added an echo line to the fallback case alerting user in XYMONOUT file 
#   that we don't support that particular component yet.
# 0.5 - First version made public
# * General cleanup
# * Made it user-friendly to users who aren't me ;-) 
# * Added more notes
# 0.51
# * Added quick usage line
# 0.52
# * Fixed a nasty bug where Non-critical errors made reports green, even with
#   other critical errors present
# 0.53
# * Added Non-critical erros, made omreport chassis report parsing more robust
# 0.54
# * Fixed HTML tag in warning to include quotes
# 0.55
# * Added support for the Hardware Log chassis component via "omreport system esmlog"
# 0.56
# * Increased grep -A context from 9 to 30 so components beyond the 9th (e.g. Batteries) are captured
# * Added Batteries case to drill-down loop
# * Silenced grep output in color-detection if/elif



#
# Test name
#
TEST="hardware"

# 
# Name of our script for debugging purposes
#
XYMONPROG=openmanage.sh; export XYMONPROG

#
# Set these for testing if you need to
#
#XYMONHOME=/home/bb/bb; export XYMONHOME    

if test "$XYMONHOME" = ""
then
    echo "XYMONHOME is not set...exiting"
    exit 1
fi

if test ! "$XYMONTMP"                      
then
        . $XYMONHOME/etc/bbdef.sh          
fi

#
# Collect data regarding the system from the omreport cli
#
PATH=/opt/dell/srvadmin/bin/:$PATH
DATAFILE=$XYMONTMP/openmanage.tmp
BAD_CHECKS=$XYMONTMP/openmanage_bad.tmp
OMREPORTS_FILE=$XYMONTMP/openmanage_reports.tmp
touch ${OMREPORTS_FILE} # So the cat from the message line won't choke

# I use this for debugging
#XYMON=echo; export XYMON

#
# Any errors?
#
omreport chassis | grep -A30 "SEVERITY" | grep " : " | grep -v \
"SEVERITY" > ${DATAFILE}

#
# Figure out color based on severity
#  Ok=green
#  Non-Critical=yellow
#  Critical=red
#
COLOR="green"
if grep -v Ok ${DATAFILE} > ${BAD_CHECKS}; then
    if grep -q ^Critical ${BAD_CHECKS}; then
        COLOR="red"
        MSGLINE="WARNING: Chassis is reporting a critical error!"
    elif grep -q Non-Critical ${BAD_CHECKS}; then
        COLOR="yellow"
        MSGLINE="WARNING: Chassis is reporting a non-critical error."
    else
        COLOR="purple"
        MSGLINE="ERROR: A Chassis component is reporting a state I don't understand; ie, something other than Ok, Critical, or Non-Critical"
    fi;
fi;

# 
# Figure out which if any of the results are generating an error.
#
# Each of the initial components reported from 2nd-level "omreport chassis"
# command corresponds to a level-3 omreport command, but we have to use a case 
# statement to get the right one as they don't
# translate exactly (You can get more info about the "Fans" component by
# using the level-3 command "omreport chasis fans", but for the
# "Power Supplies" component, you need to use the level-3 command
# "omreport chassis pwrsupplies"
# 
BAD_ITEMS=`awk -F': ' '{printf $2" "}' ${BAD_CHECKS}`
for item in ${BAD_ITEMS}; do
    case "${item}" in
    Fans)
        omreport chassis fans >> ${OMREPORTS_FILE}
        echo " " >> ${OMREPORTS_FILE}
        ;;
    Intrusion)
        omreport chassis intrusion >> ${OMREPORTS_FILE}
        echo " " >> ${OMREPORTS_FILE}
        ;;
    Memory)
        omreport chassis memory >> ${OMREPORTS_FILE}
        echo " " >> ${OMREPORTS_FILE}
        ;;
    Power)
        omreport chassis pwrsupplies >> ${OMREPORTS_FILE}
        echo " " >> ${OMREPORTS_FILE}
        ;;
    Temperatures)
        omreport chassis temps >> ${OMREPORTS_FILE}
        echo " " >> ${OMREPORTS_FILE}
        ;;
    Voltages)
        omreport chassis volts >> ${OMREPORTS_FILE}
        echo " " >> ${OMREPORTS_FILE}
        ;;
    Supplies)
        ;;
    Hardware)
        omreport system esmlog >> ${OMREPORTS_FILE}
        echo " " >> ${OMREPORTS_FILE}
        ;;
    Log)
        ;;
    Batteries)
        omreport chassis batteries >> ${OMREPORTS_FILE}
        echo " " >> ${OMREPORTS_FILE}
        ;;
    *)
        echo "ERROR: Unrecognized chassis component ${item}. We probably\
just don't support this component yet."
        ;;
    esac
done

#
# Compose the message to send to XYMON display
#
LINE="status $MACHINE.$TEST $COLOR `date` ${MSGLINE}
The result from omreport chassis is as follows:

`omreport chassis | grep -v "For further help"`

<A HREF=\"https://$HOSTNAME:1311/\">OpenManage Web Interface for $HOSTNAME</A>

`cat ${OMREPORTS_FILE}`"

rm -f ${DATAFILE}
rm -f ${BAD_CHECKS}
rm -f ${OMREPORTS_FILE}

$XYMON $XYMSRV "$LINE"          # Send message to XYMON display

