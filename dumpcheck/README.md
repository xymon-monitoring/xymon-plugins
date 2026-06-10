# dumpcheck

Monitors directories of backup files (typically database dumps) for staleness and unexpected size changes. Reports a `dumpcheck` column to the Xymon server.

## What it checks

- **Staleness** — alerts red if the most recent file in a glob pattern is older than the threshold (default: 96 hours)
- **Size regression** — alerts yellow if the newest file is more than the tolerance percentage smaller than the previous file (default: 4%), skipping files less than 15 minutes old to avoid false positives on in-progress backups

## Requirements

- Perl 5 with `File::Glob`, `File::stat`
- Standard Xymon client environment (`$XYMON`, `$XYMSRV`, `$MACHINE`)

## Installation

```bash
cp dumpcheck.pl $XYMONCLIENTHOME/ext/
chmod +x $XYMONCLIENTHOME/ext/dumpcheck.pl
cp dumpcheck.cfg $XYMONCLIENTHOME/etc/clientlaunch.d/
```

## Usage

```
dumpcheck.pl "GLOB_PATTERN[;GLOB_PATTERN...]"
```

Patterns are separated by `;` (semicolon). Each pattern is expanded via `glob()` and the resulting file list is sorted descending alphabetically to find the most recent file.

## Configuration (`dumpcheck.cfg`)

Edit the `CMD` line glob patterns to match your backup directories:

```
[dumpcheck]
    ENVFILE /etc/xymon/xymonclient.cfg
    CMD $XYMONCLIENTHOME/ext/dumpcheck.pl "/bak/db/*/pg_dump-*;/bak/db/*/mysql-*"
    LOGFILE $XYMONCLIENTHOME/logs/dumpcheck.log
    INTERVAL 15m
```

## Defaults

| Parameter | Default | Description |
|---|---|---|
| `stale_backup_threshold` | 96 hours | Age threshold for red alert |
| `backup_tolerance_percent` | 4% | Size shrinkage threshold for yellow alert |
| `status_duration` | +1d | How long Xymon holds the status |

To change thresholds, edit the `%CONFIG` block near the top of `dumpcheck.pl`.

## Status column

The Xymon column name is `dumpcheck`. Status is **green** (all files fresh and size-stable), **yellow** (size regression warning), or **red** (stale file or read error).

## Origin

Derived from [`spiderr/xymon-ext`](https://github.com/spiderr/xymon-ext) and [`spiderr/xymon-checks`](https://github.com/spiderr/xymon-checks), with local production customizations (96 h threshold, 4% tolerance, `;` pattern separator).
