#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# clientage-client.sh [YELLOW [RED]] -- the clientage column, clientage(8):
# run every 5 minutes by xymonlaunch as the task clientage-client, under
# the client's environment (ENVFILE xymonclient.cfg). It reads the clock
# the Xymon client wrote in its last message, $XYMONTMP/msg.MACHINEDOTS.txt
# -- the [clock] section's epoch, which xymonclient.sh writes with logfetch
# --clock at each run -- and compares it with logfetch --clock now: no stat,
# no date +%s, which not every system has. It sends this host's status
# clientage: green up to YELLOW minutes (15), yellow up to RED (30), red
# beyond; yellow when there is no message yet, as just after the client
# starts. With XYMSRV 0.0.0.0, the xymon utility sends to every server
# XYMSERVERS names. What it did goes to its log, one line a run.

log() { printf '%s clientage: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

for v in XYMON XYMSRV XYMONHOME XYMONTMP MACHINEDOTS; do
	eval "val=\${$v:-}"
	if [ -z "$val" ]; then log "$v is not set: run as the task, with ENVFILE xymonclient.cfg"; exit 1; fi
done
yellow=${1:-15} red=${2:-30}
case $yellow$red in ''|*[!0-9]*) log "the thresholds are minutes, two numbers: $yellow $red"; exit 1 ;; esac

lf=$XYMONHOME/bin/logfetch
now=$("$lf" --clock 2>/dev/null | sed -n 's/^epoch: \([0-9]\{1,\}\).*/\1/p')
msg=$XYMONTMP/msg.$MACHINEDOTS.txt
# The first epoch line after [clock], the client's own.
then_=$(sed -n '/^\[clock\]/{n;s/^epoch: \([0-9]\{1,\}\).*/\1/p;}' "$msg" 2>/dev/null | sed -n 1p)
if [ -z "$now" ]; then
	color=yellow line="the clock cannot be read: $lf --clock gave no epoch"
elif [ -z "$then_" ]; then
	color=yellow line="no message of the client yet in $msg"
else
	age=$(( (now - then_) / 60 ))
	if [ "$age" -lt "$yellow" ]; then color=green
	elif [ "$age" -lt "$red" ]; then color=yellow
	else color=red; fi
	line="the client's last message is $age minutes old (yellow from $yellow, red from $red)"
fi
host=$(printf '%s' "$MACHINEDOTS" | tr . ,)
if ! "$XYMON" "$XYMSRV" "status $host.clientage $color $(date) $line"; then
	log "$color, not sent to $XYMSRV: $line"
	exit 1
fi
log "$color sent: $line"
