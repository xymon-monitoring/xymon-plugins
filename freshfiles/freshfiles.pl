#!/usr/bin/perl
use File::Glob ':globally';
use File::stat;
use File::Basename;
use Sys::Hostname;
use Scalar::Util;
use Data::Dumper;

%CONFIG = ();

$script = fileparse( $0, qr/\.[^.]*/ );

$CONFIG{'CHECKNAME'} = $script;
$CONFIG{'status_duration'} = "+1d";
$CONFIG{'stale_backup_threshold'} = $ARGV[0]; # number of hours
$CONFIG{'backup_tolerance_percent'} = 2; # percentage Tolerance for day to day backup file sizes

$usage = 'Usage: '.$0.' [HOURS] "/dir/to/check/foo_*:/path/to/check/bar*"';

$GREEN = 0;
$YELLOW = 1;
$RED = 2;

# open file with handle DIR

$status = $GREEN;
$statusMessage = "";
@backupDirs = split( /:/, $ARGV[1] );

if( $CONFIG{'stale_backup_threshold'} !~ /^[\d\.]+?$/  ) {
	$status |= $RED;
	$statusMessage .= "The first argument should be an integer for the number of hours to check for file age";
} if( $backupDirs[0]  ) {
	foreach $backupDir (@backupDirs) {
		# use glob to get directory contents
		@dirContents = glob( $backupDir );

		if( $dirContents[0] ) {
			$statusMessage .= "Checking $backupDir\n";
			# sort alphabetically, descending to we can easily check elements 0 and 1
			@sortedDir = sort {$b cmp $a} @dirContents;

			foreach $file (@sortedDir) {
				my $sb = stat( $file ); 
				if( -d $file ) {
					$statusMessage .= "Skipping directory $file\n";
				} else {
					$statusMessage .= "Checking $file ... ";
					if( $sb ) {
						if( time() - $sb->mtime > ($CONFIG{'stale_backup_threshold'} * 3600) ) {
							$status |= $RED;
							$statusMessage .= "\nMost recent backup is more than ".$CONFIG{'stale_backup_threshold'}." hours old ( ".localtime( $sb->mtime )." ) $mostRecentFile\n";
						} else {
							$statusMessage .= "OK\n";
						}
					} else {
						$status |= $RED;
						$statusMessage .= "Error reading most recent backup file $mostRecentFile: $! \n";
					}
				}
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
