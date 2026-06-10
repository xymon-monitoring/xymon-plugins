#!/usr/bin/perl
use File::Glob ':globally';
use File::stat;
use Sys::Hostname;

%CONFIG = ();

$CONFIG{'CHECKNAME'} = "dumpcheck";
$CONFIG{'status_duration'} = "+1d";
$CONFIG{'stale_backup_threshold'} = 96; # number of hours
$CONFIG{'backup_tolerance_percent'} = 4; # percentage Tolerance for day to day backup file sizes

$usage = 'Usage: '.$0.' "/dir/to/check/foo_*:/path/to/check/bar*"';

$GREEN = 0;
$YELLOW = 1;
$RED = 2;

# open file with handle DIR

$status = $GREEN;
$statusMessage = "Check files older than ".$CONFIG{'stale_backup_threshold'}." Hours\n";
@backupDirs = split( /;/, $ARGV[0] );

if( $backupDirs[0]  ) {
	foreach $backupDir (@backupDirs) {
		# use glob to get directory contents
		@dirContents = glob( $backupDir );

		if( $dirContents[0] ) {
			$statusMessage .= "Checking $backupDir\n";
			# sort alphabetically, descending to we can easily check elements 0 and 1
			@sortedDir = sort {$b cmp $a} @dirContents;

			$mostRecentFile = $sortedDir[0];
			$secondMostRecentFile = $sortedDir[1];
			my $sb = stat( $mostRecentFile ); 
			if( $sb ) {
				# prevent checking in progress backup, only compare file sizes if backup is at least 15 minutes old
				if( time() - $sb->mtime > 15*60 ) {
						$secondMostRecentSize = -s $secondMostRecentFile;
						if( $secondMostRecentSize && ($sb->size / $secondMostRecentSize)*100 < (100-$CONFIG{'backup_tolerance_percent'}) ) {
							$status |= $YELLOW;
							$statusMessage .= "Newest backup is more than ".$CONFIG{'backup_tolerance_percent'}."% smaller than previous backup: $mostRecentFile ( ".$sb->size." ) < $secondMostRecentFile ( $secondMostRecentSize ) \n";
						}
				}

				if( time() - $sb->mtime > ($CONFIG{'stale_backup_threshold'} * 3600) ) {
					$status |= $RED;
					$statusMessage .= "Most recent backup is more than ".$CONFIG{'stale_backup_threshold'}." hours old ( ".localtime( $sb->mtime )." ) $mostRecentFile\n";
				}
			} else {
				$status |= $RED;
				$statusMessage .= "Error reading most recent backup file $mostRecentFile: $! \n";
			}
		} else {
			# an error occurred reading backupdir
			$status |= $RED;
			$statusMessage .= "Could not open backup directory '$backupDir': $!\n$usage\n";
		}
	}
} else {
	$status |= $RED;
	$statusMessage .= "Directories to scan for backup where not specified.\n$usage\n";
}

$commandDate = `/bin/date`;
$statusColor = ($status > $YELLOW ? "RED" : ($status > $GREEN ? "YELLOW" : "GREEN"));
$command=qq{$ENV{XYMON} $ENV{XYMSRV} "status$CONFIG{status_duration} $ENV{MACHINE}.$CONFIG{CHECKNAME} $statusColor $commandDate $statusMessage"};
if( -s "$ENV{XYMON}" ) {
	`$command`;
	if( $status ) {
		print "$statusColor $commandDate $statusMessage\n";
	}
} else {
	print "Xymon command not found: $ENV{XYMON}\n";
	print "$command\n";
}

exit 0;
