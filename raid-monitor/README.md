# raid-monitor

Generic RAID status monitor for Xymon. Uses a **reference-file diff** approach: capture a known-good state once, then alert on any change. This makes it trivially easy to support new RAID controllers without writing per-card parsing logic. Reports a `raid` column to the Xymon server.

Version 0.9.8 by Thomas Eckert. See [project homepage](http://www.it-eckert.com/software/raid-monitor).

## Supported RAID systems

Modules are provided in `raid.d/` for:

| Module | Controller type | CLI tool |
|---|---|---|
| `3ware.raid` | 3ware/AMCC/LSI 7xxx–9xxx | `tw_cli` |
| `areca.raid` | Areca HW RAID cards | `areca-cli` |
| `aacraid.raid` | Adaptec SAS/SATA unified (5405, IBM ServeRAID) | `arcconf` |
| `linux_mdraid.raid` | Linux software RAID (MD driver) | `/proc/mdstat` |
| `megaraid.raid` | LSI MegaRAID, Dell PERC | `MegaCli` |
| `00sample.raid` | Example / template for new modules | — |

Multiple RAID types on the same host are supported.

## Requirements

- bash 3.x or 4.x with array support
- `diff`, `tail`, `sed`, `tee`
- The CLI tool for your RAID controller (see table above)
- `sudo` configured for the Xymon user to run the RAID CLI (most tools require root)

## Installation

```bash
cp -r raid-monitor/ $XYMONCLIENTHOME/ext/raid-monitor/
chmod +x $XYMONCLIENTHOME/ext/raid-monitor/raid-monitor
```

Copy `raid-monitor-clientlaunch.cfg` to `$XYMONCLIENTHOME/etc/clientlaunch.d/` (or append to `clientlaunch.cfg`). Edit `ENVFILE` path if needed — the original uses `$HOBBITCLIENTHOME` which should be changed to `$XYMONCLIENTHOME`:

```
[raid-monitor]
    ENVFILE $XYMONCLIENTHOME/etc/xymonclient.cfg
    CMD $XYMONCLIENTHOME/ext/raid-monitor/raid-monitor
    LOGFILE $XYMONCLIENTHOME/logs/raid-monitor.log
    INTERVAL 5m
```

## Configuration

Edit `raid-monitor.cfg` and set `MY_RAID` to the module(s) matching your hardware:

```bash
MY_RAID="megaraid"        # one controller type
MY_RAID="3ware areca"     # multiple on the same host
```

Then adjust the CLI path and options for your controller (see the comments in `raid-monitor.cfg` and in each `raid.d/*.raid` module).

## First run: generate reference file

After installing and configuring, generate the reference (known-good) file:

```bash
$XYMONCLIENTHOME/bin/bbcmd $XYMONCLIENTHOME/ext/raid-monitor/raid-monitor -r
```

Verify with debug mode (prints the diff command without sending to Xymon):

```bash
$XYMONCLIENTHOME/bin/bbcmd $XYMONCLIENTHOME/ext/raid-monitor/raid-monitor -d
```

## Command-line options

| Option | Description |
|---|---|
| `-r` | Generate new reference file from current RAID state |
| `-d` | Debug mode — print output to stdout, do not send to Xymon |
| `-s` | Silent mode — only log errors |
| `-c FILE` | Use a custom config file |
| `-m DIR` | Use a custom `raid.d/` directory |

## How it works

1. Runs all configured RAID CLI commands and captures their output to a temp file
2. `diff`s the temp file against the stored reference file
3. If no differences → **green** (RAID state matches known-good)
4. If differences → **red** (something changed from the known-good state)

The first line of the diff is included in the Xymon status summary. This approach catches any state change (degraded array, failed disk, firmware version change, etc.) without needing per-controller parsing logic.

## Adding support for a new controller

Copy `raid.d/00sample.raid` as a starting point. The module filename (without `.raid`) must match the function name prefixed with `_`. Use `__loop()` for repeated CLI invocations or `__single_cmd()` for one-offs. See existing modules for examples.

## Status column

The Xymon column name is `raid` (set by `BBCOLUMN` in `raid-monitor.cfg`).

## Origin

From [`spiderr/xymon-checks`](https://github.com/spiderr/xymon-checks). Original by Thomas Eckert, [http://www.it-eckert.com/](http://www.it-eckert.com/). Copyright 2006–2014 Thomas Eckert. Free to copy and modify with attribution.

## License

Copyright (C) 2006–2014 Thomas Eckert. Copying and distribution, with or without modification, permitted in any medium without royalty provided the copyright notice and this notice are preserved. See script header for full terms.
