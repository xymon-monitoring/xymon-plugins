#!/bin/sh 

#
# xy-omsa-raid.sh	External script for Big Brother
#
# Local RAID monitoring for Dell PowerEdge RAID Controllers (PERC) in 
# conjunction with Dell's OpenManage Server Administration (OMSA) tool 
# called 'omreport'.
#

#
# Known to work on the following Dell RAID controllers:
#
#	SCSI
#	----
#	Adaptec PERC2, PERC2/Si					     - ROMB
#	LSI Logic PERC2/SC, PERC2/DC, PERC2/QC			     - Add-in
#	Adaptec PERC3/Si, PERC3/Di				     - ROMB
#	LSI Logic PERC3/SC, PERC3/DC, PERC3/DCL, PERC3/QC 	     - Add-in
#	LSI Logic PERC4/Si, PERC4/Di, PERC4/IM			     - ROMB
#	LSI Logic PERC4/SC, PERC4/DC, PERC4/QC			     - Add-in
#	LSI Logic PERC4e/Si, PERC4e/Di				     - ROMB
#	LSI Logic PERC4e/DC					     - Add-in
#	LSI Logic PERC5/i, PERC5/iR				     - ROMB
#	LSI Logic PERC5/E					     - Add-in
#	LSI Logic PERC6/i, PERC6/iR				     - ROMB
#	LSI Logic PERC6/E					     - Add-in
# 	LSI Logic H700 						     - ROMB
#	(please submit other working controllers!)
#
#	ATA
#	---
#	LSI Logic CERC ATA 100/4ch				     - Add-in
#	Adaptec CERC SATA1.5/6ch, SATA1.5/2s			     - ROMB
#
# And on the following versions of OMSA:
#
#	3.3, 4.5, 5.0, 5.5, 6.0, 6.5

#
# Revision History:
# V1.0	2005-11-08 Original version by Ben Argyle
# 	bda20@cam.ac.uk -- Ben Argyle, University of Cambridge
# V1.1	2005-11-24 Minor bugfixes/updates suggested by Ricardo M. Stella
#		Fix to work with PCI slot cards properly
#		Fix to work with controllers without batteries
#		Some cosmetic changes
#		Verified compatiblity with certain CERCs
#	bda20@cam.ac.uk -- Ben Argyle, University of Cambridge
# V1.2	2005-12-01 Minor bugfixes to deal with capitalisation issues
#	bda20@cam.ac.uk -- Ben Argyle, University of Cambridge
# V1.3  2007-01-02 Functionality fix suggestions by Shane Presley
#		Fix to work with PERC5 cards, also
#		Superfluous report lines removed but verbosity increased
#		 (sorry if this isn't what you wanted)
#		Fixed typos and errors in some comments
#	bda20@cam.ac.uk -- Ben Argyle, University of Cambridge
# V1.4	2009-03-16 Functionality fix suggestion by Gabriel Petrescu
#		Fix to work with PERC6 cards while remaining backwards 
#		 compatible with older PERCs, also
#		Fix to work with OMSA 5.0.0 and greater
#		Minor clean up to code here and there
#	bda20@cam.ac.uk -- Ben Argyle, University of Cambridge
#
# V2.0  2011-07-20 Complete and utter major rewrite, from scratch, seriously
#		Thanks to Mike Brodbelt for configuration samples and testing
#		Everything has changed, but it should be a lot more
#		 resilient with regard to versions of OMSA, PERCs
#		 and all the other variations they throw up
#		Flags up a few new things like issues with firmware
#		 versions and should be a bit easier to add new tests 
#	ben@lspace.org -- Ben Argyle, University of Cambridge
# V2.1  2011-08-12 Bugfix for battery status and overall array status colo(u)r
#		Stupid thing wasn't giving the right colo(u)r back when charging
#       ben@lspace.org -- Ben Argyle, University of Cambridge
# V2.2  2012-04-03 Bugfix for multiple virtual disks, clean up of loop logic
#		NOTE: Non-Critical disks now marked as "green" as OMSA marks all
#		non-Dell branded disks as "Non-Critical"
#	ben@lspace.org -- Ben Argyle, University of Cambridge

#
# This script is public-domain software and may be modified
# as you wish.  If you do, please include the revision history.
#

#
# This program is (loosely) based on the sample monitoring
# script distributed with Big Brother, and released under 
# the same restrictions as Big Brother.
#

#
# XYMONPROG should just contain the name of this file
# Useful when you get environment dumps to locate
# the offending script
#
XYMONPROG=xy-omsa-raid.sh; export XYMONPROG

#
# TEST will become a column on the display
# It should be as short as possible to save space...
# Note you can also create a help file for your test
# which should be put in www/help/$TEST.html.  It will
# be linked into the display automatically.
#
TEST="hardware"

#########################################################
#
# For testing purposes only
# Uncomment if you're not running this within Big Brother
# and you want output to screen rather than just the file
# and not send the data to the Big Brother server
#
#export XYMONHOME=/usr/share/xymon-client/
#export XYMONTMP=/tmp
#########################################################

if test ! "$XYMONHOME"
then
 echo "${XYMONPROG}: XYMONHOME is not set"
 exit 1
fi

if test ! -d "$XYMONHOME"
then
 echo "${XYMONPROG}: XYMONHOME is invalid"
 exit 1
fi

#
# Set up global variables/files/function
#
OMREPORT="/opt/dell/srvadmin/bin/omreport"
RAW_OMSA=`$OMREPORT about -fmt ssv | grep Version | cut -d";" -f2`
OMSA_VERSION=`echo $RAW_OMSA | tr -d "."`
CONTROLLER_FULL=$XYMONTMP/xy-omsa-raid_controller-full.tmp
CONTROLLER_ONLY=$XYMONTMP/xy-omsa-raid_controller-only.tmp
VDISKS_ONLY=$XYMONTMP/xy-omsa-raid_vdisks-only.tmp
ADISKS_ONLY=$XYMONTMP/xy-omsa-raid_adisks-only.tmp
BATTERY_ONLY=$XYMONTMP/xy-omsa-raid_battery-only.tmp
CONTROLLER_XYMON_OUT=$XYMONTMP/xy-omsa-raid_controller-xy-out.tmp
VDISKS_XYMON_OUT=$XYMONTMP/xy-omsa-raid_vdisks-xy-out.tmp
BATTERY_XYMON_OUT=$XYMONTMP/xy-omsa-raid_battery-xy-out.tmp
CUMULATIVE_XYMON_OUT=$XYMONTMP/xy-omsa-raid_cumulative-xy-out.tmp

function rpad {
 word="$1"
 while [ ${#word} -lt $2 ]; do
  word="$word$3";
 done;
 echo "$word";
}

#
# Set the default overall COLOR (result) for the test.
#
COLOR="green"

#
# Stick in the header
#
echo > $CUMULATIVE_XYMON_OUT
echo "Dell PowerEdge RAID Controller Status (OMSA v$RAW_OMSA)" >> $CUMULATIVE_XYMON_OUT
echo "===================================================" >> $CUMULATIVE_XYMON_OUT
echo  >> $CUMULATIVE_XYMON_OUT

controller_count=`$OMREPORT storage controller -fmt ssv | egrep '^[0-9]' | wc -l`
for (( controller_id=0; controller_id<$controller_count; controller_id++ ))
do
 $OMREPORT storage controller controller=$controller_id > $CONTROLLER_FULL

 #
 # Controller section
 #
 sed '0,/Controllers/d' $CONTROLLER_FULL > $CONTROLLER_ONLY
 grep "Channels" $CONTROLLER_FULL > /dev/null
 if [ $? -eq 0 ]; then
  connector_delimiter="Channels" # Older PERCs/OMSA versions
 else
  connector_delimiter="Connectors" # More recent PERCs/OMSA versions
 fi
 sed -i "/$connector_delimiter/,\$d" $CONTROLLER_ONLY

 #
 # Battery section
 #
 $OMREPORT storage battery controller=$controller_id -fmt ssv | grep -i found > /dev/null
 if [ $? -eq 1 ]; then
  sed '0,/Battery/d' $CONTROLLER_FULL > $BATTERY_ONLY
  sed -i '/Enclosure(s)/,$d' $BATTERY_ONLY
 else
  echo "\# \&clear Controller has no battery." > $BATTERY_ONLY
 fi

 #
 # Vdisks section
 #
 $OMREPORT storage vdisk controller=$controller_id > $VDISKS_ONLY
 sed -i '0,/Controller/d' $VDISKS_ONLY
 #
 # Separate each vdisk out into its own file
 #
 vdisk_count=0
 while read line
 do
  echo $line | egrep '^ID' > /dev/null
  if [ $? -eq 0 ]; then
   vdisk_id=`echo $line | awk '{print $3}'`
   vdisk_count=`expr $vdisk_count + 1`
   individual_vdisk=$VDISKS_ONLY.$vdisk_id
  fi
  echo $line | egrep '^$' > /dev/null
  if [ $? -eq 0 ]; then
   individual_vdisk=/dev/null
  fi
  echo $line >> ${individual_vdisk}
 done < $VDISKS_ONLY
 
 #
 # Array/Physical disks section
 #
 for (( vdisk_id=0; vdisk_id<$vdisk_count; vdisk_id++ ))
 do
  $OMREPORT storage adisk vdisk=$vdisk_id controller=$controller_id > $ADISKS_ONLY.$vdisk_id
  sed -i "0,/Controller/d" $ADISKS_ONLY.$vdisk_id
 done
 
 #
 # Now get the lines we want from each file and XYMONify them where necessary
 #
 # Controller
 #
 echo "Controller $controller_id" > $CONTROLLER_XYMON_OUT
 echo "------------" >> $CONTROLLER_XYMON_OUT
 egrep '^ID|Status|Name|^State|Slot|Version' $CONTROLLER_ONLY | while read line
 do 
  line_id=`echo $line | cut -d':' -f1`
  line_state=`echo $line | cut -d':' -f2`
  echo $line | egrep '^State|Status' > /dev/null
  if [ $? -eq 0 ]; then
   if [ $line_state = "Ok" -o $line_state = "Ready" ]; then
    line=`echo \&green $(rpad \$line_id 42 '.') " :"$line_state`
   else
    if [ $line_state = "Non-Critical" -o $line_state = "Degraded" ]; then 
     line=`echo \&yellow $(rpad \$line_id 42 '.')" :"$line_state`
    else
     line=`echo \&red $(rpad \$line_id 42 '.')" :"$line_state`
    fi
   fi
  else
   echo $line | egrep '^ID|Name|Slot' > /dev/null
   if [ $? -eq 1 ]; then
    echo $line | egrep 'Required.*Applicable' > /dev/null
    if [ $? -eq 0 ]; then
     line=`echo \&green $(rpad "$line_id" 42 '.')" :"$line_state`
    else
     echo $line | egrep 'Minimum.*Version.*[0-9]' > /dev/null
     if [ $? -eq 0 ]; then
      line=`echo \&yellow $(rpad "$line_id" 42 '.')" :"$line_state`
     else
      line=`echo \&clear $(rpad "$line_id" 42 '.')" :"$line_state`
     fi
    fi
   else
    line=`echo \&clear $(rpad "$line_id" 42 '.')" :"$line_state`
   fi
  fi
  echo $line >> $CONTROLLER_XYMON_OUT
 done

 #
 # Battery
 #
 echo > $BATTERY_XYMON_OUT
 echo "Controller $controller_id : Battery" >> $BATTERY_XYMON_OUT
 echo "----------------------" >> $BATTERY_XYMON_OUT
 grep "has no" $BATTERY_ONLY > /dev/null
 if [ $? -eq 1 ]; then
  egrep 'ID|^Status|Name|State' $BATTERY_ONLY | while read line
  do
   line_id=`echo $line | cut -d':' -f1`
   line_state=`echo $line | cut -d':' -f2`
   echo $line | egrep 'Status|^State' > /dev/null
   if [ $? -eq 0 ]; then
    if [ $line_state = "Ok" -o $line_state = "Ready" ]; then
     line=`echo \# \&green $(rpad "$line_id" 13 '.')" :"$line_state`
    else
     if [ $line_state = "Reconditioning" -o $line_state = "Charging" -o $line_state = "Non-Critical" ]; then
      line=`echo \# \&yellow $(rpad "$line_id" 13 '.')" :"$line_state`
     else
      line=`echo \# \&red $(rpad "$line_id" 13 '.')" :"$line_state`
     fi
    fi
   else
    line=`echo \# \&clear $(rpad "$line_id" 13 '.')" :"$line_state`
   fi
   echo $line >> $BATTERY_XYMON_OUT
  done
 else
  echo $line >> $BATTERY_XYMON_OUT
 fi

 #
 # Vdisks
 #
 echo > $VDISKS_XYMON_OUT
 for (( vdisk_id=0; vdisk_id<$vdisk_count; vdisk_id++ ))
 do
  echo "-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-" >> $VDISKS_XYMON_OUT
  echo "Controller $controller_id : Virtual Disk $vdisk_id" >> $VDISKS_XYMON_OUT
  echo "-----------------------------" >> $VDISKS_XYMON_OUT
  egrep '^ID|Status|^Name|State|Progress|Layout' $VDISKS_ONLY.$vdisk_id | while read line
  do
   line_id=`echo $line | cut -d':' -f1`
   line_state=`echo $line | cut -d':' -f2 | sed 's/^ //g'`
   echo $line | egrep 'Status|^State' > /dev/null
   if [ $? -eq 0 ]; then
    if [ "$line_state" = "Ok" -o "$line_state" = "Ready" ]; then
     line=`echo \&green $(rpad "$line_id" 42 '.')" : "$line_state`
    elif [ "$line_state" = "No" ]; then
     line=`echo \&green $(rpad "$line_id" 42 '.')" : "$line_state`
    else
     if [ "$line_state" = "Non-Critical" -o "$line_state" = "Degraded" ]; then
      line=`echo \&yellow $(rpad "$line_id" 42 '.')" : "$line_state`
     else
      line=`echo \&red $(rpad "$line_id" 42 '.')" : "$line_state`
     fi
    fi
   else
    echo $line | egrep '^ID|Name|Layout' > /dev/null
    if [ $? -eq 1 ]; then
     echo $line | egrep '(Progress.*Applicable|Applicable.*Progress)' > /dev/null
     if [ $? -eq 0 ]; then
      line=`echo \&green $(rpad "$line_id" 42 '.')" : "$line_state`
    elif [ "$line_state" = "Not Applicable" ]; then
     line=`echo \&green $(rpad "$line_id" 42 '.')" : "$line_state`
     else
      line=`echo \&yellow $(rpad "$line_id" 42 '.')" : "$line_state`
     fi
    else
     line=`echo \&clear $(rpad "$line_id" 42 '.')" : "$line_state`
    fi
   fi
   echo $line >> $VDISKS_XYMON_OUT
  done

  #
  # Adisks for the vdisk
  #
  echo >> $VDISKS_XYMON_OUT
  echo "Controller $controller_id : Virtual Disk $vdisk_id : Array Disks" >> $VDISKS_XYMON_OUT
  echo "-------------------------------------------" >> $VDISKS_XYMON_OUT
  egrep '^ID|^Status|State|Name|Failure|Progress|^$' $ADISKS_ONLY.$vdisk_id | while read line
  do
   line_id=`echo $line | cut -d':' -f1`
   line_state=`echo $line | cut -d':' -f2-5`
   echo $line | egrep 'Status|^State' > /dev/null
   if [ $? -eq 0 ]; then
    if [ $line_state = "Ok" -o $line_state = "Online" -o $line_state = "Spun Up" -o $line_state = "Ready" -o $line_state = "Non-Critical" ]; then
     line=`echo \# \&green $(rpad "$line_id" 40 '.')" :"$line_state`
    else
     if [ $line_state = "Degraded" -o $line_state = "Recovering" -o $line_state = "Resynching" -o $line_state = "Rebuilding" -o $line_state = "Formatting" -o $line_state = "Initializing" ]; then
      line=`echo \# \&yellow $(rpad "$line_id" 40 '.')" :"$line_state`
     else
      line=`echo \# \&red $(rpad "$line_id" 40 '.')" :"$line_state`
     fi
    fi
   else
    echo $line | egrep '^ID|Name|^$' > /dev/null
    if [ $? -eq 1 ]; then
     echo $line | egrep 'Failure Predicted' > /dev/null
     if [ $? -eq 0 ]; then
      if [ $line_state = "No" ]; then
       line=`echo \# \&green $(rpad "$line_id" 40 '.')" :"$line_state`
      else
       line=`echo \# \&red $(rpad "$line_id" 40 '.')" :"$line_state`
      fi
     fi
     echo $line | egrep '(Progress.*Applicable|Applicable.*Progress)' > /dev/null
     if [ $? -eq 0 ]; then
      line=`echo \# \&green $(rpad "$line_id" 40 '.')" :"$line_state`
     else
      echo $line | egrep 'Progress.*[0-9]' > /dev/null
      if [ $? -eq 0 ]; then
       line=`echo \# \&yellow $(rpad "$line_id" 40 '.')" :"$line_state`
      fi
     fi
    else
     echo $line | egrep '^$' > /dev/null
     if [ $? -eq 0 ]; then
      line=" "
     else
      line=`echo \# \&clear $(rpad "$line_id" 40 '.')" :"$line_state`
     fi
    fi
   fi
   echo $line >> $VDISKS_XYMON_OUT
  done 
 done 
 echo "=========================================================================" >> $VDISKS_XYMON_OUT
 cat $CONTROLLER_XYMON_OUT $BATTERY_XYMON_OUT $VDISKS_XYMON_OUT >> $CUMULATIVE_XYMON_OUT
done
 
#
# Create the line we'll send to Big Brother
#
grep '&yellow' $CUMULATIVE_XYMON_OUT > /dev/null
if [ $? = 0 ]; then
 COLOR="yellow"
fi

grep '&red' $CUMULATIVE_XYMON_OUT > /dev/null
if [ $? = 0 ]; then
 COLOR="red"
fi

LINE="status $MACHINE.$TEST $COLOR `date` RAID Status: `cat $CUMULATIVE_XYMON_OUT`"

#########################################################
#
# For testing purposes only
# Uncomment if you're not running this within Big Brother
# and you want output to screen rather than just the file
# and not send the data to the Big Brother server
# Additionally, comment out the line beginning $XYMON below
#
#echo $XYMONDISP "$LINE"
#########################################################

#
# Otherwise send the line
#
$XYMON $XYMONDISP "$LINE"

#
# Clean up our temporary files
#
for (( vdisk_id=0; vdisk_id<=$vdisk_count; vdisk_id++ ))
do
 rm -rf $VDISKS_ONLY.$vdisk_id $ADISKS_ONLY.$vdisk_id
done
rm -rf $CONTROLLER_FULL $CONTROLLER_ONLY $BATTERY_ONLY $VDISKS_ONLY $CONTROLLER_XYMON_OUT $VDISKS_XYMON_OUT $BATTERY_XYMON_OUT $CUMULATIVE_XYMON_OUT

