# remotehttp

Checks HTTP/HTTPS URLs from an **external vantage point** and reports results to Xymon. Designed to run on an outside server with a tunnel back to the inside Xymon daemon (port 1984), so internal Xymon sees what the public internet actually gets.

Primary use case: verify that URLs which should be access-controlled (admin panels, `.htaccess`-protected paths, internal APIs) are actually blocked from outside — not just blocked from inside where `.htaccess` rules apply.

URL line syntax follows Xymon `hosts.cfg` HTTP check notation, so check lines can be copied directly from `hosts.cfg`.

## Requirements

- Python 3 (stdlib only — no external packages)
- Network access from the monitoring host to the target URLs
- TCP tunnel from the monitoring host to the inside Xymon daemon on port 1984

## Installation

```bash
cp remotehttp.py /usr/lib/xymon/server/ext/remotehttp.py
chmod +x /usr/lib/xymon/server/ext/remotehttp.py

mkdir -p /etc/xymon/conf.d
cp remotehttp.cfg /etc/xymon/conf.d/remotehttp.cfg
```

## URL line syntax

Each line in a `URLS =` block uses Xymon `hosts.cfg` HTTP check notation:

```
[modifier;]...[modifier;]URL[;STATUS]
```

**Modifiers** (prefix tokens, separated by `;`, before the URL):

| Modifier | Effect |
|---|---|
| `nossl` | Skip TLS certificate verification |
| `cont=STRING` | Response body must contain `STRING` |
| `nocont=STRING` | Response body must NOT contain `STRING` |

**STATUS**: expected HTTP status code. Default is `200` if omitted.

**Redirects are not followed.** The status reported is the raw first response from the server — important for access-control checks where a 302 or 403 is the expected blocked response.

### Examples

```
https://example.com/;200                          public home page is up
https://example.com/admin/;403                    admin blocked from outside
https://example.com/server-status;403             Apache status blocked
https://example.com/.htaccess;403                 dotfile blocked
https://example.com/api/internal/;401             API requires authentication
nossl;https://staging.example.com/admin/;403      skip cert, expect 403
cont=Forbidden;https://example.com/admin/;403     403 with "Forbidden" in body
https://example.com/login;302                     login redirects (acceptable)
```

## Configuration (`remotehttp.cfg`)

```ini
[DEFAULT]
XYMON_HOST    = xymon.example.com
XYMON_PORT    = 1984
COLUMN        = http
TIMEOUT       = 10

[web1]
XYMON_HOSTNAME = web1.example.com
URLS =
    https://web1.example.com/;200
    https://web1.example.com/admin/;403
    https://web1.example.com/.htaccess;403
    https://web1.example.com/api/internal/;401
```

Add one `[section]` per Xymon hostname. `XYMON_HOSTNAME` must match the hostname as registered in Xymon's `hosts.cfg`.

### COLUMN setting

The default column name is `remotehttp`. Set `COLUMN = http` to merge results into the standard `http` column alongside Xymon's built-in HTTP checks — this avoids adding an extra column to the Xymon grid.

## Scheduling via cron

```cron
*/5 * * * * root /usr/bin/python3 /usr/lib/xymon/server/ext/remotehttp.py >> /var/log/xymon/remotehttp.log 2>&1
```

Or via `tasks.cfg`:

```
[remotehttp]
    INTERVAL 5m
    CMD /usr/bin/python3 /usr/lib/xymon/server/ext/remotehttp.py
    LOGFILE /var/log/xymon/remotehttp.log
```

## Status column color

| Color | Meaning |
|---|---|
| green | All URLs returned their expected status and content checks passed |
| red | One or more URLs returned an unexpected status — something is accessible that should not be |
| purple | One or more URLs were unreachable (connection refused / timeout / DNS failure) — no data received |

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `REMOTEHTTP_CONF_DIR` | `/etc/xymon/conf.d` | Directory scanned for `*.cfg` files |

## Origin

Custom plugin. Server-side script; runs on the external monitoring host, not on the monitored web server.

## License

Copyright (C) 2026 spiderr. GNU General Public License v2 or later — see <https://www.gnu.org/licenses/>.
