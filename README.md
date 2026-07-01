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
| [`interface/`](interface/) | Python 3 | `interface` | Network interface speed, duplex, and link state via `ethtool` |
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

## Licensing & provenance

No third-party upstream currently maintains a public repository for any of
these plugins (the original sites are dead or were only mailing-list / blog
posts). This repository is therefore the **source of record for all of them**.
Original authors and licenses are preserved and credited per row; for
third-party code the original license still governs redistribution.

- *Side* — `client` (runs on the monitored host, `client/ext/`) or `server`
  (runs on the Xymon server, `server/ext/`).
- *Official source* — where to get the maintained copy: **this repo** for every
  plugin, since no third-party upstream repo is maintained.
- *Origin* — where the code first came from, with a URL where one still
  resolves; dead links are marked **down**.

| Plugin | Side | Official source | Origin (historical) | Original author | License | Status |
|---|---|---|---|---|---|---|
| [`arista/`](arista/) | server | **this repo** | Original work | spiderr (2026) | GPL-2+ | ✅ |
| [`ciscoasa/`](ciscoasa/) | server | **this repo** | Original work | spiderr (2026) | GPL-2+ | ⚠️ empty `## Origin` |
| [`dumpcheck/`](dumpcheck/) | client | **this repo** | [`spiderr/xymon-ext`](https://github.com/spiderr/xymon-ext), [`xymon-checks`](https://github.com/spiderr/xymon-checks) | spiderr (2026) | GPL-2+ | ✅ |
| [`freshfiles/`](freshfiles/) | client | **this repo** | [`spiderr/xymon-checks`](https://github.com/spiderr/xymon-checks) | spiderr (2026) | GPL-2+ | ✅ |
| [`interface/`](interface/) | client | **this repo** | reimplemented clean-room; design orig. netdar (2013), [blog archived](http://web.archive.org/web/20180328134523/http://blog.dafert.org/xymon-bigbrother-script-to-monitor-network-interfaces-duplex-settings-and-bonding/) | xymon-monitoring (2026) | GPL-2+ | ✅ |
| [`logfetchupdate/`](logfetchupdate/) | client | **this repo** | Original work | spiderr (2026) | GPL-2+ | ⚠️ empty `## Origin` |
| [`omsa-raid/`](omsa-raid/) | client | **this repo** | [`spiderr/xymon-ext`](https://github.com/spiderr/xymon-ext); Xymon list [2009](https://lists.xymon.com/xymon/2009-March/023783.html), [2011](https://lists.xymon.com/xymon/2011-September/032429.html) | Ben Argyle, U. Cambridge | Public domain | ✅ |
| [`openmanage/`](openmanage/) | client | **this repo** | [`spiderr/xymon-ext`](https://github.com/spiderr/xymon-ext); [hobbit list (2008)](https://lists.xymon.com/archive/2008-November/022358.html) | Brian Smith-Sweeney, UC (2002) | UC license (non-commercial) | ✅ |
| [`postfixq/`](postfixq/) | client | **this repo** | Original work | spiderr (2026) | GPL-2+ | ⚠️ empty `## Origin` |
| [`raid-monitor/`](raid-monitor/) | client | **this repo** | it-eckert.com **down** (NXDOMAIN); [Wayback (2017)](http://web.archive.org/web/20170515074814/http://www.it-eckert.com:80/software/raid-monitor/) | Thomas Eckert (2006–2014) | Custom "as-is" | ✅ |
| [`remotehttp/`](remotehttp/) | server | **this repo** | unknown (no repo found) | unstated | ❌ none | ❌ license TBD |
| [`rhn/`](rhn/) | client | **this repo** | [`spiderr/xymon-checks`](https://github.com/spiderr/xymon-checks) | spiderr (2026) | GPL-2+ | ✅ |

**Legend:** ✅ complete · ⚠️ minor gap · ❌ real gap · **this repo** =
[`xymon-monitoring/xymon-plugins`](https://github.com/xymon-monitoring/xymon-plugins)

### Open items

1. **`remotehttp`** *(❌ priority)* — no origin and no license. Trace the source
   (likely a `spiderr/xymon-*` repo) or, if original, declare it "Original work
   (this repo)" + GPL-2+. Add both `## Origin` and `## License` to its README.
2. **`ciscoasa` / `logfetchupdate` / `postfixq`** *(⚠️ cosmetic)* — the `## Origin`
   section is empty; fill it with "Original work — this repository".
3. **`interface`** — ✅ **resolved by rewrite.** The original (netdar, 2013,
   republished on Andreas Dafert's now-offline blog) carried **no license**, and a
   public blog is not public domain — copyright stays with the author, and any
   implied license would cover *use*, not redistribution/relicensing. Rather than
   ship unlicensed third-party code, the check was **reimplemented clean-room** in
   Python 3 under GPL-2+ (same `interface` column and `--debug`/`--speed`
   behaviour, no shared code). netdar is credited as design inspiration only. Full
   provenance and rationale: [`interface/README.md`](interface/README.md#origin).
4. **Maintenance status** — confirm with spiderr whether ongoing maintenance of
   the upstream-originated plugins is delegated to this repository.

### Licenses in this collection

GPL-2+ (most) · Public domain (`omsa-raid`) · UC academic, **non-commercial**
(`openmanage`) · Custom "as-is" (`raid-monitor`) · **no license** (`remotehttp`).

## Server configuration

[`graphs.cfg`](graphs.cfg) contains RRD graph definitions for plugins that send bandwidth data (`arista`, `ciscoasa`). Append it to `/etc/xymon/graphs.cfg` on the Xymon server.
