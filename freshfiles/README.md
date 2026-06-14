# freshfiles

Verifies that every file matching a glob pattern has been updated within a specified time window. Useful for monitoring that nightly/weekly/monthly backup files are being written on schedule. Reports a `freshbackups` column to the Xymon server.

Unlike `dumpcheck`, which checks only the _most recent_ file in a directory, `freshfiles` checks **every file** matched by the pattern individually.

## Requirements

- Perl 5 with `File::Glob`, `File::stat`, `File::Basename`, `Scalar::Util`, `Data::Dumper`
- Standard Xymon client environment (`$XYMON`, `$XYMSRV`, `$MACHINE`)

## Installation

```bash
cp freshfiles.pl $XYMONCLIENTHOME/ext/
chmod +x $XYMONCLIENTHOME/ext/freshfiles.pl
cp freshfiles.cfg $XYMONCLIENTHOME/etc/clientlaunch.d/
```

## Usage

```
freshfiles.pl HOURS "GLOB_PATTERN[:GLOB_PATTERN...]"
```

- **HOURS** — maximum age in hours; files older than this trigger a red alert
- Patterns are separated by `:` (colon)
- Subdirectories matched by a pattern are skipped with a log message

### Common hour values

| Hours | Meaning |
|---|---|
| 26 | Daily (25 h + 1 h slack) |
| 168 | Weekly |
| 768 | Monthly (32 days) |

## Configuration (`freshfiles.cfg`)

```
[freshbackups]
    ENVFILE /etc/xymon/xymonclient.cfg
    CMD $XYMONCLIENTHOME/ext/freshfiles.pl 26 "/path/to/backups/*"
    LOGFILE $XYMONCLIENTHOME/logs/freshfiles.log
    INTERVAL 15m
```

## Status column

The Xymon column name is `freshbackups` (derived from the script filename via `File::Basename`). Status is **green** (all files fresh), or **red** (any file is older than the threshold or a directory cannot be read).

## Origin

From [`spiderr/xymon-checks`](https://github.com/spiderr/xymon-checks).

## License

Copyright (C) 2026 spiderr. GNU General Public License v2 or later — see <https://www.gnu.org/licenses/>.
