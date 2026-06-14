#!/usr/bin/perl
# Copyright (C) 2026 spiderr
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, see <https://www.gnu.org/licenses/>.
use File::Glob ':globally';
use File::stat;
use Sys::Hostname;

%CONFIG = ();

$CONFIG{'CHECKNAME'} = "postfixq";
$CONFIG{'queue_directory'} = `/usr/sbin/postconf -h queue_directory`;
chop( $CONFIG{'queue_directory'} );
$usage = 'Usage: '.$0.' [yellow_threshold_num] [red_threshold_num]';

$CONFIG{'yellow_threshold'} = $ARGV[0];
$CONFIG{'red_threshold'} = $ARGV[1];


$GREEN = 0;
$YELLOW = 1;
$RED = 2;

$status = $GREEN;
$statusMessage = "";

if( $CONFIG{'red_threshold'} && $CONFIG{'yellow_threshold'} ) {
	@testDirs = qw( incoming active maildrop deferred );
#	foreach $dir (@testDirs ) {
#		open TEST, "$CONFIG{'queue_directory'}/$dir" or $permDenied .= "Permission denied: $CONFIG{'queue_directory'}/$dir\n";
#		close TEST;
#	}
	$active_num = `sudo /bin/find $CONFIG{'queue_directory'}/incoming $CONFIG{'queue_directory'}/active $CONFIG{'queue_directory'}/maildrop -type f -print | wc -l | awk '{print $1}'`;
	chop( $active_num );
	$deferred_num = `sudo /bin/find $CONFIG{'queue_directory'}/deferred -type f -print | wc -l | awk '{print $1}'`;
	chop( $deferred_num );

	$statusMessage .= "activemessages: $active_num\n";
	$statusMessage .= "deferredmessages: $deferred_num\n\n";
	$statusMessage .= "Active queue has $active_num messages \n";
	$statusMessage .= "Defered queue has $deferred_num messages \n";

	if( $permDenied ) {
		$statusMessage .= $permDenied;
		$status |= $RED;
	}

	if( $deferred_num >= $CONFIG{'red_threshold'}/10 ) {
		$statusMessage .= "Deferred ".$deferred_num." >= 10% of ".$CONFIG{'yellow_threshold'}."\n";
		$status |= $RED;
	} elsif( $deferred_num >= $CONFIG{'yellow_threshold'}/10 ) {
		$statusMessage .= "Deferred messages ".$deferred_num."\n";
		$status |= $YELLOW;
	}

	if( $active_num >= $CONFIG{'red_threshold'} ) {
		$statusMessage .= "Active ".$active_num." >= ".$CONFIG{'red_threshold'}."\n";
		$status |= $RED;
	} elsif( $active_num >= $CONFIG{'yellow_threshold'} ) {
		$status |= $YELLOW;
	}

} else {
	$status |= $RED;
	$statusMessage .= "postfix queue warning and error thresholds were not specified in hobbit configuration.\n$usage\n";
}

$commandDate = `/bin/date`;
$statusColor = ($status > $YELLOW ? "RED" : ($status > $GREEN ? "YELLOW" : "GREEN"));
$command=qq{$ENV{XYMON} $ENV{XYMSRV} "status$CONFIG{status_duration} $ENV{MACHINE}.$CONFIG{CHECKNAME} $statusColor $commandDate$statusMessage"};
if( -s "$ENV{XYMONHOME}/bin/xymon" ) {
	`$command`;
	if( $status ) {
		print "$statusColor $commandDate $statusMessage\n";
	}
} else {
	print "Hobbit command not found: $ENV{XYMONHOME}/bin/bb\n";
	print "$command\n";
}

exit 0;


