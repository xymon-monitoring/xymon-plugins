# xymon-plugins

Collection of optional plugins and extensions for [Xymon](https://xymon.sourceforge.io/) monitoring. Includes community-contributed checks, integrations, and add-ons that extend Xymon client functionality. Each plugin lives in its own directory with a README covering installation, configuration, and usage.

Provided on a best-effort basis. Tested on RHEL/CentOS/AlmaLinux 9.

## Plugins

| Directory | Language | Xymon column | What it monitors |
|---|---|---|---|
| [`arista/`](arista/) | Python 3 | `cpu` `memory` `hardware` `net` | Arista EOS switch health — server-side SSH poller |
| [`ciscoasa/`](ciscoasa/) | Python 3 | `cpu` `memory` `conn` `hardware` `net` `vpn` | Cisco ASA firewall health — server-side SSH poller |
| [`dumpcheck/`](dumpcheck/) | Perl | `dumpcheck` | Backup file age and size regression |
| [`freshfiles/`](freshfiles/) | Perl | `freshbackups` | File freshness — all files in a glob updated within time window |
| [`interface/`](interface/) | Python 2 | `interface` | Network interface speed, duplex, and link state via `ethtool` |
| [`logfetchupdate/`](logfetchupdate/) | sh | — | Downloads updated `logfetch` config from server (Terabithia) |
| [`omsa-raid/`](omsa-raid/) | sh | `hardware` | Dell PERC RAID via OpenManage `omreport` (OMSA) |
| [`openmanage/`](openmanage/) | bash | `hardware` | Dell chassis health (fans, temps, PSUs, memory) via `omreport chassis` |
| [`postfixq/`](postfixq/) | Perl | `postfixq` | Postfix mail queue depth (active + deferred) |
| [`remotehttp/`](remotehttp/) | Python 3 | `remotehttp` (or `http`) | HTTP/HTTPS URL checks from external vantage point — verify URLs are blocked from public internet |
| [`raid-monitor/`](raid-monitor/) | bash | `raid` | Generic RAID monitor — diff-based, supports 3ware/Areca/Adaptec/mdraid/MegaRAID |
| [`rhn/`](rhn/) | sh | `rhn` | Config drift from Red Hat Satellite 5.x / Spacewalk 2.x |

## Quick start

Each plugin directory contains:
- The plugin script(s)
- A `*.cfg` file for `clientlaunch.cfg` (or `clientlaunch.d/`)
- A `README.md` with full installation and configuration details

General steps for any plugin:

```bash
cp <plugin>/<script> $XYMONCLIENTHOME/ext/
chmod +x $XYMONCLIENTHOME/ext/<script>
cp <plugin>/<plugin>.cfg $XYMONCLIENTHOME/etc/clientlaunch.d/
# edit the CMD line in the .cfg to match your environment
systemctl reload xymon-client   # or kill -HUP the xymonlaunch process
```

## Xymon environment variables

All plugins expect the standard Xymon client environment sourced from `xymonclient.cfg`:

| Variable | Description |
|---|---|
| `$XYMON` | Full path to the `xymon` binary |
| `$XYMSRV` | Xymon server address |
| `$MACHINE` | This host's Xymon machine name (dots replaced with commas) |
| `$XYMONCLIENTHOME` | Xymon client install root |
| `$XYMONTMP` | Temp directory for Xymon client |

## Sources

Merged from:
- [`spiderr/xymon-checks`](https://github.com/spiderr/xymon-checks) — dumpcheck, freshfiles, rhn, interface, raid-monitor
- [`spiderr/xymon-ext`](https://github.com/spiderr/xymon-ext) — omsa-raid, openmanage
- Local production customizations — postfixq, logfetchupdate, dumpcheck v96h/4%, ciscoasa, arista, remotehttp

## Server configuration

[`graphs.cfg`](graphs.cfg) contains RRD graph definitions for plugins that send bandwidth data (`arista`, `ciscoasa`). Append it to `/etc/xymon/graphs.cfg` on the Xymon server.
