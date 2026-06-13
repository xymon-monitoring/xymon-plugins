#!/usr/bin/env python3
"""
ASA firewall health monitor — sends status and RRD data to Xymon.

Polls each ASA firewall defined in CONF_DIR/*.cfg via SSH, then sends
7 Xymon status columns and a 'net' RRD data message to the Xymon daemon.

Usage:
    python3 asa_monitor.py              # poll all configured firewalls
    python3 asa_monitor.py asa1         # poll one firewall by short name

Environment variables:
    ASA_MONITOR_CONF_DIR   Directory containing *-monitor.cfg files.
                           Default: /etc/xymon/conf.d
    ASA_MONITOR_DATA_DIR   Directory for per-firewall SQLite bandwidth DBs.
                           Default: /var/lib/xymon/asa-monitor

Xymon columns produced per firewall:
    cpu          CPU % with per-process breakdown (catches runaway DDNS etc.)
    memory       Memory used %
    conn         Active connections + NAT translation table count
    hardware     Physical health: PSU, fans, temperature
    net          Bandwidth (current rate + 95th-pct vs commitment) and
                 per-interface error/drop rates
    vpn          IKEv2 tunnel count and state (only sent if VPN is configured)

Bandwidth samples are stored in a SQLite DB under DATA_DIR. The 95th
percentile is calculated in pure Python over a configurable rolling window
(default 24 h = 288 × 5-min samples).

A Xymon 'data' message is sent each run (column: net) so Xymon's rrddata
channel stores bandwidth in net.rrd for native Xymon graphing.
"""
import configparser
import glob
import os
import re
import socket
import sqlite3
import subprocess
import sys
import time

import pexpect

CONF_DIR      = os.environ.get("ASA_MONITOR_CONF_DIR", "/etc/xymon/conf.d")
DATA_DIR      = os.environ.get("ASA_MONITOR_DATA_DIR", "/var/lib/xymon/asa-monitor")
XYMON_RRD_DIR = os.environ.get("XYMON_RRD_DIR",        "/var/lib/xymon/rrd")

SSH_OPTS = [
    "-o", "HostKeyAlgorithms=+ssh-rsa",  # ASA 9.14 only offers SHA-1 RSA host key
    "-o", "StrictHostKeyChecking=no",
    "-o", "ConnectTimeout=10",
]

GREEN  = "green"
YELLOW = "yellow"
RED    = "red"
PURPLE = "purple"

COLUMNS = ["cpu", "memory", "conn", "hardware", "net"]


# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

def find_configs(target=None):
    """Yield (short_name, fqdn, cfg_path, configparser) for each firewall config.

    Scans CONF_DIR for *.cfg files.  Each file may contain one or more
    [firewall-name] sections; a valid section must have at least HOST and
    XYMON_HOSTNAME keys (directly or via [DEFAULT]).
    """
    for cfg_path in sorted(glob.glob(os.path.join(CONF_DIR, "*.cfg"))):
        cfg = configparser.ConfigParser()
        try:
            cfg.read(cfg_path)
        except configparser.Error:
            continue
        for section in cfg.sections():
            if not cget(cfg, section, "HOST") or not cget(cfg, section, "XYMON_HOSTNAME"):
                continue
            dt = cget(cfg, section, "DEVICE_TYPE")
            if dt and dt.lower() != "asa":
                continue
            name = section
            if target and name != target:
                continue
            fqdn = cget(cfg, section, "XYMON_HOSTNAME")
            yield name, fqdn, cfg_path, cfg


def cget(cfg, section, key, fallback=None, cast=None):
    try:
        val = cfg.get(section, key)
        return cast(val) if cast else val
    except (configparser.NoSectionError, configparser.NoOptionError):
        return fallback


# ---------------------------------------------------------------------------
# SSH helpers
# ---------------------------------------------------------------------------

def ssh_connect(host, user, key, enable_pw):
    opts = SSH_OPTS + ["-i", key]
    cmd  = "ssh " + " ".join(opts) + f" {user}@{host}"
    child = pexpect.spawn(cmd, timeout=60, encoding="utf-8")
    child.setwinsize(50, 200)
    child.expect(">", timeout=15)
    child.sendline("enable")
    child.expect("[Pp]assword:", timeout=10)
    child.sendline(enable_pw)
    child.expect("#", timeout=10)
    child.sendline("terminal pager 0")
    child.expect("#", timeout=10)
    return child


def ssh_run(child, command, timeout=30):
    """Send a command and return output up to the next # prompt."""
    child.sendline(command)
    child.expect("#", timeout=timeout)
    lines = child.before.splitlines()
    # Drop echoed command line (first non-empty line containing the command)
    if lines and lines[0].strip().startswith(command.split()[0]):
        lines = lines[1:]
    return "\n".join(lines).strip()


# ---------------------------------------------------------------------------
# Parsers — each returns structured data or None on parse failure
# ---------------------------------------------------------------------------

def parse_cpu(text):
    """Returns (pct_5sec, pct_1min, pct_5min) ints or None."""
    m = re.search(
        r"5 seconds[^=]+=\s*(\d+)%.*?1 minute:\s*(\d+)%.*?5 minutes:\s*(\d+)%",
        text, re.DOTALL | re.IGNORECASE
    )
    return (int(m.group(1)), int(m.group(2)), int(m.group(3))) if m else None


def parse_processes(text):
    """Returns list of (name, pct_5min) sorted descending, top 10 non-zero."""
    procs = []
    for line in text.splitlines():
        # Format: PC  Thread  5Sec  1Min  5Min  Process
        m = re.match(
            r"\S+\s+\S+\s+[\d.]+%\s+[\d.]+%\s+([\d.]+)%\s+(.+)",
            line.strip()
        )
        if m:
            pct  = float(m.group(1))
            name = m.group(2).strip()
            if pct > 0:
                procs.append((name, pct))
    procs.sort(key=lambda x: -x[1])
    return procs[:10]


def parse_memory(text):
    """Returns (used_pct, used_bytes, free_bytes) or None."""
    mu = re.search(r"Used memory:\s+([\d,]+)\s+bytes\s+\((\d+)%\)", text)
    mf = re.search(r"Free memory:\s+([\d,]+)\s+bytes",               text)
    if not mu:
        return None
    return (
        int(mu.group(2)),
        int(mu.group(1).replace(",", "")),
        int(mf.group(1).replace(",", "")) if mf else 0,
    )


def parse_iface_rate(text):
    """Returns (in_bps, out_bps) bytes/sec from the longest-period rate shown, or None."""
    # ASA may show '1 minute' or '5 minute' rates; take the last pair (longest avg)
    in_matches  = re.findall(r"\d+ minute input rate\s+\d+ pkts/sec,\s+(\d+) bytes/sec",  text)
    out_matches = re.findall(r"\d+ minute output rate\s+\d+ pkts/sec,\s+(\d+) bytes/sec", text)
    if in_matches and out_matches:
        return int(in_matches[-1]), int(out_matches[-1])
    return None


def parse_iface_errors(text):
    """Returns dict of cumulative error counters from show interface output."""
    def _int(pattern):
        m = re.search(pattern, text, re.IGNORECASE)
        return int(m.group(1)) if m else 0

    return {
        "input_errors":  _int(r"Input errors:\s+(\d+)"),
        "output_errors": _int(r"Output errors:\s+(\d+)"),
        "crc":           _int(r"CRC:\s+(\d+)"),
        "input_drops":   _int(r"Input queue:.*?/\d+/(\d+)/"),
        "output_drops":  _int(r"Output queue:.*?/(\d+)\s"),
        "resets":        _int(r"interface resets\s+(\d+)"),
    }


def parse_conn(text):
    m = re.search(r"(\d+)\s+in use", text)
    return int(m.group(1)) if m else None


def parse_environment(text):
    """Returns (issues_list, max_ambient_c_or_None).

    Trusts the ASA's own OK/FAIL indicators rather than applying external
    thresholds — the ASA firmware knows its own hardware limits.  Only
    flags lines the ASA itself marks as non-OK, plus hardware error counters.
    """
    issues = []

    skip_patterns = re.compile(
        r"^[-=\s]*$"                          # separator lines / blank
        r"|Statistics|Last 5 Errors"          # error stats section headers
        r"|ALARM CONTACT \d+$"                # alarm contact label lines
        r"|Description:|Severity:|Trigger:"   # alarm contact detail lines
        r"|Driver Information|Status\s*:\s*RUNNING",
        re.IGNORECASE,
    )

    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or skip_patterns.search(stripped):
            continue
        # ASA marks faults with these keywords
        if re.search(r"\b(?:FAIL(?:ED)?|NOT PRESENT|ABSENT|FAULT)\b",
                     stripped, re.IGNORECASE):
            issues.append(stripped[:100])
        # Alarm contact asserted = external alarm wired in
        if re.search(r"Status\s*:\s*asserted", stripped, re.IGNORECASE):
            issues.append(f"Alarm asserted: {stripped[:80]}")

    # Hardware I2C / GPIO / PECI error counters — non-zero = board fault
    for label, pat in [
        ("I2C errors",  r"I2C I/O Errors\s*:\s*([1-9]\d*)"),
        ("GPIO errors", r"GPIO Errors\s*:\s*([1-9]\d*)"),
        ("PECI errors", r"PECI Errors\s*:\s*([1-9]\d*)"),
    ]:
        m = re.search(pat, text)
        if m:
            issues.append(f"{label}: {m.group(1)}")

    # Extract highest ambient/chassis temperature for informational display.
    # Does NOT threshold — trust ASA's own OK indicator on each temp line.
    temp_c = None
    for m in re.finditer(
        r"(?:Ambient|Chassis[^:]*|Inlet)\s+\d*\s*:?\s*([\d.]+)\s*C\s*-\s*OK",
        text, re.IGNORECASE
    ):
        val = float(m.group(1))
        if temp_c is None or val > temp_c:
            temp_c = val

    return issues, temp_c


def parse_vpn(text):
    """Returns (tunnel_count, detail_text, no_vpn_configured)."""
    lower = text.lower()
    if "no ikev2 sa" in lower or "there are no" in lower or not text.strip():
        return 0, text, True
    # Count lines with status indicators
    up_lines = [l for l in text.splitlines()
                if re.search(r"UP-\w+|READY|ESTABLISHED", l, re.IGNORECASE)]
    return len(up_lines), text, False


def parse_uptime(text):
    m = re.search(r"up\s+([\d\w ,]+?)(?:\n|$)", text, re.IGNORECASE)
    return m.group(1).strip().rstrip(",") if m else "unknown"


# ---------------------------------------------------------------------------
# 95th percentile — SQLite
# ---------------------------------------------------------------------------

def bw_store(db_path, ts, in_bps, out_bps):
    con = sqlite3.connect(db_path)
    con.execute(
        "CREATE TABLE IF NOT EXISTS bw_samples "
        "(ts INTEGER NOT NULL, in_bps REAL NOT NULL, out_bps REAL NOT NULL)"
    )
    con.execute("INSERT INTO bw_samples VALUES (?,?,?)", (ts, in_bps, out_bps))
    con.execute("DELETE FROM bw_samples WHERE ts < ?", (ts - 86400 * 30,))
    con.commit()
    con.close()


def bw_percentile(db_path, window_hours):
    """Returns (in_95_mbps, out_95_mbps, n_samples).  Values are None if < 2 samples."""
    if not os.path.exists(db_path):
        return None, None, 0
    con     = sqlite3.connect(db_path)
    cutoff  = int(time.time()) - window_hours * 3600
    rows    = con.execute(
        "SELECT in_bps, out_bps FROM bw_samples WHERE ts >= ? ORDER BY ts", (cutoff,)
    ).fetchall()
    con.close()
    n = len(rows)
    if n < 2:
        return None, None, n
    in_s  = sorted(r[0] for r in rows)
    out_s = sorted(r[1] for r in rows)
    idx   = min(int(0.95 * n), n - 1)
    return in_s[idx] * 8 / 1_000_000, out_s[idx] * 8 / 1_000_000, n


# ---------------------------------------------------------------------------
# Threshold helpers
# ---------------------------------------------------------------------------

def threshold_color(value, warn, crit):
    if value >= crit:  return RED
    if value >= warn:  return YELLOW
    return GREEN


def worst_color(*colors):
    for c in (RED, YELLOW, GREEN, PURPLE):
        if c in colors:
            return c
    return GREEN


# ---------------------------------------------------------------------------
# Xymon send
# ---------------------------------------------------------------------------

def xymon_send_status(xymon_host, xymon_port, fqdn, column, color, body, headline=""):
    ts  = time.strftime("%a %b %d %H:%M:%S %Z %Y")
    sfx = (" " + headline) if headline else ""
    msg = f"status+600 {fqdn}.{column} {color} {ts}{sfx}\n\n{body}\n"
    _xymon_tcp(xymon_host, xymon_port, msg)
    print(f"  [{color.upper():6}] {fqdn}.{column}")


def xymon_send_data(xymon_host, xymon_port, fqdn, column, ds_dict, rrd_file=None):
    """Send a 'data' message so Xymon's rrddata channel stores data in RRD.

    column   — Xymon status column name (used in the 'data <fqdn>.<column>' header)
    rrd_file — RRD filename stem (default: same as column).  Use when the target
               RRD file must differ from the column name, e.g. column='cpu',
               rrd_file='la' to feed Xymon's built-in la.rrd/[la] graph.
    """
    if rrd_file is None:
        rrd_file = column
    lines = [f"data {fqdn}.{column}", f"[{rrd_file}.rrd]"]
    for ds, val in ds_dict.items():
        lines.append(f"DS:{ds}:GAUGE:600:0:U {int(val)}")
    _xymon_tcp(xymon_host, xymon_port, "\n".join(lines) + "\n")


def port_to_rrd(name):
    """Map a port/interface name to an ifstat.*.rrd stem for the [ifstat] graph stanza."""
    return "ifstat." + re.sub(r'[/\s]+', '-', name)


# ---------------------------------------------------------------------------
# Direct rrdtool writes (bypass xymond_rrd write cache / missing handlers)
# ---------------------------------------------------------------------------

_STD_RRAS = [
    "RRA:AVERAGE:0.5:1:576",
    "RRA:AVERAGE:0.5:6:576",
    "RRA:AVERAGE:0.5:24:576",
    "RRA:AVERAGE:0.5:288:576",
]
_NET_RRD_SPEC    = ["--step", "300", "DS:in:GAUGE:600:0:U", "DS:out:GAUGE:600:0:U"] + _STD_RRAS
_LA_RRD_SPEC     = ["--step", "300", "DS:la:GAUGE:600:U:U"] + _STD_RRAS
_IFSTAT_RRD_SPEC = ["--step", "300",
                    "DS:bytesReceived:GAUGE:600:0:U",
                    "DS:bytesSent:GAUGE:600:0:U"] + _STD_RRAS


def _rrd_write(host_dir, fname, spec, value_str):
    path = os.path.join(host_dir, fname)
    if not os.path.exists(path):
        r = subprocess.run(["rrdtool", "create", path] + spec,
                           capture_output=True, text=True)
        if r.returncode != 0:
            print(f"  rrdtool create {fname}: {r.stderr.strip()}", file=sys.stderr)
            return
    r = subprocess.run(["rrdtool", "update", path, f"N:{value_str}"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        print(f"  rrdtool update {fname}: {r.stderr.strip()}", file=sys.stderr)


def _rrd_update_net(fqdn, in_bps, out_bps):
    host_dir = os.path.join(XYMON_RRD_DIR, fqdn)
    os.makedirs(host_dir, exist_ok=True)
    _rrd_write(host_dir, "net.rrd", _NET_RRD_SPEC, f"{int(in_bps)}:{int(out_bps)}")
    print(f"  [RRD   ] net.rrd → {in_bps/1_000_000:.1f}/{out_bps/1_000_000:.1f} Mbps")


def _rrd_update_cpu_la(fqdn, cpu_pct):
    host_dir = os.path.join(XYMON_RRD_DIR, fqdn)
    os.makedirs(host_dir, exist_ok=True)
    _rrd_write(host_dir, "la.rrd", _LA_RRD_SPEC, str(int(cpu_pct * 100)))
    print(f"  [RRD   ] la.rrd → {cpu_pct:.1f}%")


def _rrd_update_ifstat(fqdn, port, in_bytes_sec, out_bytes_sec):
    host_dir = os.path.join(XYMON_RRD_DIR, fqdn)
    os.makedirs(host_dir, exist_ok=True)
    fname = f"{port_to_rrd(port)}.rrd"
    _rrd_write(host_dir, fname, _IFSTAT_RRD_SPEC,
               f"{int(in_bytes_sec)}:{int(out_bytes_sec)}")


def _xymon_tcp(host, port, msg):
    try:
        with socket.create_connection((host, int(port)), timeout=10) as s:
            s.sendall(msg.encode())
    except Exception as exc:
        print(f"  Xymon TCP send failed: {exc}", file=sys.stderr)


def purple_all(xymon_host, xymon_port, fqdn, reason):
    for col in COLUMNS:
        xymon_send_status(xymon_host, xymon_port, fqdn, col, PURPLE,
                          f"No data: {reason}")


# ---------------------------------------------------------------------------
# Column body builders
# ---------------------------------------------------------------------------

def col_cpu(cpu_tuple, procs, uptime_str, cfg, section):
    if not cpu_tuple:
        return RED, "Could not parse 'show cpu usage' output."
    s5, m1, m5 = cpu_tuple
    color = threshold_color(m5,
                            cget(cfg, section, "CPU_WARN", 70, int),
                            cget(cfg, section, "CPU_CRIT", 85, int))
    body = f"CPU  5-sec: {s5}%   1-min: {m1}%   5-min: {m5}%\nUptime: {uptime_str}\n"
    if procs:
        body += "\nTop processes (5-min CPU):\n"
        for name, pct in procs:
            marker = "  <-- !" if pct >= 20 else ""
            body  += f"  {pct:5.1f}%  {name}{marker}\n"
    return color, body


def col_memory(mem_tuple, cfg, section):
    if not mem_tuple:
        return RED, "Could not parse 'show memory' output."
    used_pct, used_bytes, free_bytes = mem_tuple
    color = threshold_color(used_pct,
                            cget(cfg, section, "MEM_WARN", 80, int),
                            cget(cfg, section, "MEM_CRIT", 90, int))
    body = (f"Memory used: {used_pct}%\n"
            f"  Used: {used_bytes / 1048576:.0f} MB\n"
            f"  Free: {free_bytes / 1048576:.0f} MB\n")
    return color, body


def col_conn(conn, xlate, cfg, section):
    c_warn  = cget(cfg, section, "CONN_WARN",  50000, int)
    c_crit  = cget(cfg, section, "CONN_CRIT",  80000, int)
    x_warn  = cget(cfg, section, "XLATE_WARN", 50000, int)
    x_crit  = cget(cfg, section, "XLATE_CRIT", 80000, int)
    c1      = threshold_color(conn  or 0, c_warn, c_crit)
    c2      = threshold_color(xlate or 0, x_warn, x_crit)
    color   = worst_color(c1, c2)
    body    = (f"Connections (active): {conn  if conn  is not None else 'N/A'}\n"
               f"NAT translations:     {xlate if xlate is not None else 'N/A'}\n")
    return color, body


def col_bandwidth(in_bps, out_bps, in_95, out_95, n_samples, cfg, section):
    commit  = cget(cfg, section, "COMMITMENT_MBPS", 100, float)
    window  = cget(cfg, section, "BW_WINDOW_HOURS",  24, int)
    in_m    = (in_bps  or 0) * 8 / 1_000_000
    out_m   = (out_bps or 0) * 8 / 1_000_000

    body  = f"Current rate (5-min avg):\n  In:  {in_m:.2f} Mbps\n  Out: {out_m:.2f} Mbps\n\n"

    if in_95 is None:
        color  = GREEN
        needed = max(0, int(cget(cfg, section, "BW_WINDOW_HOURS", 24, int) * 12) - n_samples)
        body  += (f"95th percentile: accumulating data "
                  f"({n_samples} of {window * 12} samples, ~{needed * 5} min to go)\n"
                  f"Commitment: {commit:.0f} Mbps\n")
    else:
        peak         = max(in_95, out_95)
        pct_commit   = peak / commit * 100 if commit > 0 else 0
        color        = threshold_color(peak, commit * 0.85, commit)
        body        += (f"95th percentile (last {window}h, {n_samples} samples):\n"
                        f"  In:  {in_95:.2f} Mbps\n"
                        f"  Out: {out_95:.2f} Mbps\n"
                        f"  Peak 95th: {peak:.2f} Mbps  =  {pct_commit:.0f}% of "
                        f"{commit:.0f} Mbps commitment\n")
    return color, body


def col_interfaces(iface_data, cfg, section):
    e_warn = cget(cfg, section, "IFACE_ERR_WARN", 10,  int)
    e_crit = cget(cfg, section, "IFACE_ERR_CRIT", 100, int)
    colors = []
    lines  = ["Interface          In Mbps  Out Mbps  Errors  CRC  Drops  Resets"]
    for iface, d in iface_data.items():
        e   = d["errors"]
        in_m  = d["in_bps"]  * 8 / 1_000_000
        out_m = d["out_bps"] * 8 / 1_000_000
        tot   = e["input_errors"] + e["output_errors"]
        crc   = e["crc"]
        drops = e["input_drops"] + e["output_drops"]
        rst   = e["resets"]
        c = threshold_color(tot + crc, e_warn, e_crit)
        colors.append(c)
        flag = f"  [{c}]" if c != GREEN else ""
        lines.append(
            f"{iface:<18} {in_m:>7.2f}  {out_m:>8.2f}"
            f"  {tot:>6}  {crc:>3}  {drops:>5}  {rst:>6}{flag}"
        )
    return worst_color(*colors) if colors else GREEN, "\n".join(lines)


def col_environment(issues, temp_c, cfg, section):
    """Color based solely on ASA-reported faults and hardware error counters.

    Temperature is displayed informational only — the ASA firmware knows its
    own thermal limits and flags them; we trust that rather than guessing
    thresholds for CPU vs PSU vs ambient sensors.
    """
    lines = []

    if issues:
        color = RED
        for i in issues:
            lines.append(f"FAULT: {i}")
    else:
        color = GREEN
        lines.append("Power supplies: Normal")
        lines.append("Fans: Normal")
        lines.append("Hardware error counters: 0")

    if temp_c is not None:
        lines.append(f"Max ambient/chassis temp: {temp_c:.0f} C  (ASA OK)")
    else:
        lines.append("Temperature: not parsed from output")

    return color, "\n".join(lines)


def col_vpn(count, detail, no_vpn):
    if no_vpn:
        return GREEN, "IKEv2 VPN: not configured"
    if count > 0:
        return GREEN, f"IKEv2 tunnels: {count} UP\n\n{detail}"
    return RED, f"IKEv2 tunnels: 0 UP\n\n{detail}"


def col_net_combined(in_bps, out_bps, in_95, out_95, n_samp, iface_data,
                     cfg, section):
    """Combine bandwidth and interface error data into a single net column."""
    c_bw,    b_bw    = col_bandwidth(in_bps, out_bps, in_95, out_95, n_samp, cfg, section)
    c_iface, b_iface = col_interfaces(iface_data, cfg, section)

    color = worst_color(c_bw, c_iface)
    body  = f"=== Bandwidth ===\n{b_bw}\n=== Interfaces ===\n{b_iface}\n"
    return color, body


# ---------------------------------------------------------------------------
# Poll one firewall
# ---------------------------------------------------------------------------

def poll(name, fqdn, cfg_path, cfg):
    section = name

    xymon_host = cget(cfg, section, "XYMON_HOST", "xymon.example.com")
    xymon_port = cget(cfg, section, "XYMON_PORT", "1984")
    fw_host    = cget(cfg, section, "HOST")
    ssh_user   = cget(cfg, section, "SSH_USER",   "admin")
    ssh_key    = cget(cfg, section, "SSH_KEY")
    enable_pw  = cget(cfg, section, "ENABLE_PASSWORD", "")
    outside    = cget(cfg, section, "OUTSIDE_IFACE",   "outside")
    ifaces     = cget(cfg, section, "MONITOR_IFACES",  "outside inside").split()
    bw_win     = cget(cfg, section, "BW_WINDOW_HOURS", 24, int)
    os.makedirs(DATA_DIR, exist_ok=True)
    bw_db      = os.path.join(DATA_DIR, f"{name}-bw.db")

    print(f"\n{'='*60}")
    print(f"{fqdn}  ({fw_host})")
    print(f"{'='*60}")

    # --- SSH connect ---
    try:
        child = ssh_connect(fw_host, ssh_user, ssh_key, enable_pw)
    except Exception as exc:
        print(f"  SSH failed: {exc}")
        purple_all(xymon_host, xymon_port, fqdn, f"SSH failed: {exc}")
        return

    # --- Collect all data in one session ---
    raw = {}
    try:
        for cmd, key in [
            ("show cpu usage",                         "cpu"),
            ("show process cpu-usage non-zero sorted", "procs"),
            ("show memory",                            "mem"),
            ("show conn count",                        "conn"),
            ("show xlate count",                       "xlate"),
            ("show environment",                       "env"),
            ("show crypto ikev2 sa",                   "vpn"),
            ("show version | include up",              "uptime"),
        ]:
            raw[key] = ssh_run(child, cmd)

        iface_raw = {}
        for iface in ifaces:
            iface_raw[iface] = ssh_run(child, f"show interface {iface}")

        child.sendline("exit")
        child.close()

    except Exception as exc:
        print(f"  Collection error: {exc}")
        try:
            child.close()
        except Exception:
            pass
        purple_all(xymon_host, xymon_port, fqdn, f"Data collection error: {exc}")
        return

    # --- Parse ---
    cpu_t   = parse_cpu(raw["cpu"])
    procs   = parse_processes(raw["procs"])
    mem_t   = parse_memory(raw["mem"])
    conn    = parse_conn(raw["conn"])
    xlate   = parse_conn(raw["xlate"])   # same structure
    env_iss, temp_c = parse_environment(raw["env"])
    vpn_n, vpn_det, no_vpn = parse_vpn(raw["vpn"])
    uptime  = parse_uptime(raw["uptime"])

    iface_data = {}
    in_bps = out_bps = None
    for iface, text in iface_raw.items():
        rate = parse_iface_rate(text)
        iface_data[iface] = {
            "in_bps":  rate[0] if rate else 0,
            "out_bps": rate[1] if rate else 0,
            "errors":  parse_iface_errors(text),
        }
        if iface == outside and rate:
            in_bps, out_bps = rate

    # --- Bandwidth 95th pct ---
    now = int(time.time())
    if in_bps is not None:
        bw_store(bw_db, now, in_bps, out_bps)
    in_95, out_95, n_samp = bw_percentile(bw_db, bw_win)

    # --- Send columns ---
    c, b = col_cpu(cpu_t, procs, uptime, cfg, section)
    xymon_send_status(xymon_host, xymon_port, fqdn, "cpu", c, b)

    c, b = col_memory(mem_t, cfg, section)
    xymon_send_status(xymon_host, xymon_port, fqdn, "memory", c, b)

    c, b = col_conn(conn, xlate, cfg, section)
    xymon_send_status(xymon_host, xymon_port, fqdn, "conn", c, b)

    c, b = col_environment(env_iss, temp_c, cfg, section)
    xymon_send_status(xymon_host, xymon_port, fqdn, "hardware", c, b)

    c, b = col_net_combined(in_bps, out_bps, in_95, out_95, n_samp,
                            iface_data, cfg, section)
    xymon_send_status(xymon_host, xymon_port, fqdn, "net", c, b)

    # --- Direct RRD updates (bypass xymond_rrd write cache / missing handlers) ---
    if cpu_t:
        # cpu_t is (s5, m1, m5); use m5 for the CPU% graph
        _rrd_update_cpu_la(fqdn, cpu_t[2])
    if in_bps is not None:
        # ASA in_bps is bytes/sec; net.rrd uses bits/sec
        _rrd_update_net(fqdn, in_bps * 8, out_bps * 8)

    graphed = cget(cfg, section, "GRAPHED_PORTS", "").split()
    for iface_name in graphed:
        d = iface_data.get(iface_name)
        if d:
            # ASA in_bps is bytes/sec; ifstat.rrd uses bytes/sec — use directly
            _rrd_update_ifstat(fqdn, iface_name, d["in_bps"], d["out_bps"])

    if not no_vpn:
        c, b = col_vpn(vpn_n, vpn_det, no_vpn)
        xymon_send_status(xymon_host, xymon_port, fqdn, "vpn", c, b)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    target  = sys.argv[1] if len(sys.argv) > 1 else None
    configs = list(find_configs(target))

    if not configs:
        msg = f"No monitor.cfg found for firewall '{target}'" if target \
              else "No monitor.cfg files found under hosts/"
        print(msg, file=sys.stderr)
        sys.exit(1)

    for args in configs:
        poll(*args)

    print("\nDone.")


if __name__ == "__main__":
    main()
