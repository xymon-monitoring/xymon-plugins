#!/usr/bin/env python3
"""
remotehttp — checks HTTP/HTTPS URLs from an external vantage point and
reports results to Xymon. URL syntax follows Xymon hosts.cfg HTTP check
notation so check lines can be copied directly from hosts.cfg.

Runs on an outside server with a tunnel to the inside Xymon daemon (port 1984).
Redirects are NOT followed — the reported status is the raw first response,
which is what matters for access-control checks.

Usage:
    python3 remotehttp.py              # check all configured hosts
    python3 remotehttp.py web1         # check one host by section name

Environment:
    REMOTEHTTP_CONF_DIR   Directory containing *.cfg files.
                          Default: /etc/xymon/conf.d

URL line syntax (one per line in URLS =):
    [modifier;]...[modifier;]URL[;STATUS]

    Modifiers (semicolon-separated prefix tokens, before the URL):
        nossl          skip TLS certificate verification
        cont=STRING    response body must contain STRING
        nocont=STRING  response body must NOT contain STRING

    STATUS  expected HTTP status code (default: 200)

Examples:
    https://example.com/;200                        site is up publicly
    https://example.com/admin/;403                  admin blocked outside
    https://example.com/api/internal;401            API requires auth
    nossl;https://example.com/staging/;403          skip cert check
    cont=Forbidden;https://example.com/admin/;403   verify body text too

Column color:
    green   all URLs returned expected status (and content checks passed)
    red     one or more URLs returned an unexpected status
    purple  one or more URLs were unreachable (connection error / timeout / DNS)
"""
import configparser
import glob
import os
import socket
import ssl
import sys
import time
import urllib.error
import urllib.request

CONF_DIR = os.environ.get("REMOTEHTTP_CONF_DIR", "/etc/xymon/conf.d")

GREEN  = "green"
YELLOW = "yellow"
RED    = "red"
PURPLE = "purple"


# ---------------------------------------------------------------------------
# URL line parser
# ---------------------------------------------------------------------------

def parse_check_line(line):
    """Parse a hosts.cfg-style URL check line.

    Returns (url, expected_status, nossl, cont, nocont) or (None, ...) if
    the line contains no recognisable URL.
    """
    parts = line.strip().split(";")
    url      = None
    expected = 200
    nossl    = False
    cont     = None
    nocont   = None

    i = 0
    while i < len(parts):
        tok = parts[i]
        if tok == "nossl":
            nossl = True
        elif tok.startswith("cont="):
            cont = tok[5:]
        elif tok.startswith("nocont="):
            nocont = tok[7:]
        elif tok.startswith("http://") or tok.startswith("https://"):
            url = tok
            i += 1
            break
        i += 1

    # Any remaining token that is a bare integer is the expected status code
    while i < len(parts):
        tok = parts[i].strip()
        if tok.isdigit():
            expected = int(tok)
        i += 1

    return url, expected, nossl, cont, nocont


# ---------------------------------------------------------------------------
# HTTP check
# ---------------------------------------------------------------------------

def check_url(url, expected_status, nossl, cont, nocont, timeout):
    """Fetch url and compare against expected_status and optional content checks.

    Returns (actual_status_or_None, color, reason).
        green   status matched and content checks passed
        red     status did not match, or content check failed
        purple  connection error / timeout / DNS failure (no data received)
    """
    ctx = ssl.create_default_context()
    if nossl:
        ctx.check_hostname = False
        ctx.verify_mode    = ssl.CERT_NONE

    class _NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            raise urllib.error.HTTPError(req.full_url, code, msg, headers, fp)

    opener = urllib.request.build_opener(
        urllib.request.HTTPSHandler(context=ctx),
        _NoRedirect,
    )
    opener.addheaders = [("User-Agent", "xymon-remotehttp/1.0")]

    body = ""
    try:
        try:
            resp   = opener.open(url, timeout=timeout)
            status = resp.status
            if cont or nocont:
                body = resp.read(8192).decode("utf-8", errors="replace")
        except urllib.error.HTTPError as e:
            status = e.code
            if cont or nocont:
                try:
                    body = e.read(8192).decode("utf-8", errors="replace")
                except Exception:
                    pass

        if status != expected_status:
            return status, RED, f"expected {expected_status}, got {status}"
        if cont and cont not in body:
            return status, RED, f"body missing '{cont}'"
        if nocont and nocont in body:
            return status, RED, f"body contains '{nocont}'"
        return status, GREEN, ""

    except urllib.error.URLError as e:
        return None, PURPLE, f"unreachable: {e.reason}"
    except Exception as e:
        return None, PURPLE, f"error: {e}"


# ---------------------------------------------------------------------------
# Xymon send
# ---------------------------------------------------------------------------

def xymon_send(host, port, msg):
    try:
        with socket.create_connection((host, int(port)), timeout=10) as s:
            s.sendall(msg.encode())
    except Exception as exc:
        print(f"  Xymon TCP error: {exc}", file=sys.stderr)


# ---------------------------------------------------------------------------
# Config discovery
# ---------------------------------------------------------------------------

def find_configs(target=None):
    for path in sorted(glob.glob(os.path.join(CONF_DIR, "*.cfg"))):
        cfg = configparser.ConfigParser()
        try:
            cfg.read(path)
        except configparser.Error:
            continue
        for section in cfg.sections():
            if not cfg.get(section, "XYMON_HOSTNAME", fallback=None):
                continue
            if target and section != target:
                continue
            yield section, cfg


# ---------------------------------------------------------------------------
# Poll one host
# ---------------------------------------------------------------------------

def _worst(a, b):
    order = {RED: 0, PURPLE: 1, YELLOW: 2, GREEN: 3}
    return a if order[a] <= order[b] else b


def poll(section, cfg):
    xymon_host = cfg.get(section, "XYMON_HOST",     fallback="xymon.example.com")
    xymon_port = cfg.get(section, "XYMON_PORT",     fallback="1984")
    fqdn       = cfg.get(section, "XYMON_HOSTNAME")
    column     = cfg.get(section, "COLUMN",         fallback="remotehttp")
    timeout    = cfg.getint(section, "TIMEOUT",     fallback=10)

    raw   = cfg.get(section, "URLS", fallback="")
    lines = [l.strip() for l in raw.splitlines() if l.strip()]

    if not lines:
        print(f"  {section}: no URLs configured, skipping")
        return

    print(f"\n{'='*60}")
    print(f"{fqdn}  ({section})")
    print(f"{'='*60}")

    results = []
    overall = GREEN

    for line in lines:
        url, expected, nossl, cont, nocont = parse_check_line(line)
        if not url:
            print(f"  SKIP (no URL found): {line}")
            continue

        status, color, reason = check_url(url, expected, nossl, cont, nocont, timeout)
        overall = _worst(overall, color)

        status_str = str(status) if status is not None else "no response"
        detail     = f"{status_str} (expected {expected})"
        if reason:
            detail += f" — {reason}"
        results.append((color, url, detail))
        print(f"  [{color.upper():6}] {url}")
        print(f"           {detail}")

    ts         = time.strftime("%a %b %d %H:%M:%S %Z %Y")
    source     = socket.getfqdn()
    body_lines = [f"Remote HTTP checks — {fqdn}", f"Checked from: {source}", ""]

    for color, url, detail in results:
        dot = {"green": "&green", "yellow": "&yellow", "red": "&red", "purple": "&purple"}.get(color, "&clear")
        body_lines.append(f"{dot} {url}")
        body_lines.append(f"    {detail}")
        body_lines.append("")

    msg = (f"status+600 {fqdn}.{column} {overall} {ts}\n\n"
           + "\n".join(body_lines) + "\n")
    xymon_send(xymon_host, xymon_port, msg)
    print(f"\n  [{overall.upper()}] → {fqdn}.{column}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    target  = sys.argv[1] if len(sys.argv) > 1 else None
    configs = list(find_configs(target))

    if not configs:
        msg = f"No config found for '{target}'" if target else "No *.cfg files found"
        print(msg, file=sys.stderr)
        sys.exit(1)

    for args in configs:
        poll(*args)

    print("\nDone.")


if __name__ == "__main__":
    main()
