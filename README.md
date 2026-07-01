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

## Licensing & provenance

This repository is the **canonical maintenance source** for the plugins that
originate here — the GPL-2+ scripts authored by spiderr (marked *Original work*
below). For plugins authored by third parties, this repo redistributes and
patches a copy under the original license; the **authoritative source stays with
the original author**, and their license governs redistribution. The *Origin*
column records where a plugin's code first came from (historical source), not
who maintains it now.

| Plugin | Origin (historical) | Original author | License | Status |
|---|---|---|---|---|
| [`arista/`](arista/) | Original work (this repo) | spiderr (2026) | GPL-2+ | ✅ |
| [`ciscoasa/`](ciscoasa/) | Original work (this repo) | spiderr (2026) | GPL-2+ | ⚠️ empty `## Origin` |
| [`dumpcheck/`](dumpcheck/) | [`spiderr/xymon-ext`](https://github.com/spiderr/xymon-ext), [`xymon-checks`](https://github.com/spiderr/xymon-checks) | spiderr (2026) | GPL-2+ | ✅ |
| [`freshfiles/`](freshfiles/) | [`spiderr/xymon-checks`](https://github.com/spiderr/xymon-checks) | spiderr (2026) | GPL-2+ | ✅ |
| [`interface/`](interface/) | [`spiderr/xymon-checks`](https://github.com/spiderr/xymon-checks) (via [Dafert blog](https://blog.dafert.org/)) | netdar (2013) | ❌ none | ⚠️ no upstream license |
| [`logfetchupdate/`](logfetchupdate/) | Original work (this repo) | spiderr (2026) | GPL-2+ | ⚠️ empty `## Origin` |
| [`omsa-raid/`](omsa-raid/) | [`spiderr/xymon-ext`](https://github.com/spiderr/xymon-ext) | Ben Argyle, U. Cambridge | Public domain | ✅ |
| [`openmanage/`](openmanage/) | [`spiderr/xymon-ext`](https://github.com/spiderr/xymon-ext) | Brian Smith-Sweeney, UC (2002) | UC license (non-commercial) | ✅ |
| [`postfixq/`](postfixq/) | Original work (this repo) | spiderr (2026) | GPL-2+ | ⚠️ empty `## Origin` |
| [`raid-monitor/`](raid-monitor/) | [it-eckert.com](http://www.it-eckert.com/software/raid-monitor) | Thomas Eckert (2006–2014) | Custom "as-is" | ✅ |
| [`remotehttp/`](remotehttp/) | unknown | unstated | ❌ none | ❌ missing origin + license |
| [`rhn/`](rhn/) | [`spiderr/xymon-checks`](https://github.com/spiderr/xymon-checks) | spiderr (2026) | GPL-2+ | ✅ |

**Legend:** ✅ complete · ⚠️ minor gap · ❌ real gap

### Open items

1. **`remotehttp`** *(❌ priority)* — no origin and no license. Trace the source
   (likely a `spiderr/xymon-*` repo) or, if original, declare it "Original work
   (this repo)" + GPL-2+. Add both `## Origin` and `## License` to its README.
2. **`ciscoasa` / `logfetchupdate` / `postfixq`** *(⚠️ cosmetic)* — the `## Origin`
   section is empty; fill it with "Original work — this repository".
3. **`interface`** *(⚠️ decision)* — no license was ever granted by the original
   author (netdar, 2013); redistribution rights are unclear. Decide: keep with a
   disclaimer, contact the author, or remove.
4. **Maintenance status** — confirm with spiderr whether ongoing maintenance of
   the upstream-originated plugins is delegated to this repository.

### Licenses in this collection

GPL-2+ (most) · Public domain (`omsa-raid`) · UC academic, **non-commercial**
(`openmanage`) · Custom "as-is" (`raid-monitor`) · **no license** (`interface`,
`remotehttp`).

## Server configuration

[`graphs.cfg`](graphs.cfg) contains RRD graph definitions for plugins that send bandwidth data (`arista`, `ciscoasa`). Append it to `/etc/xymon/graphs.cfg` on the Xymon server.
