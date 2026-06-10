#!/usr/bin/env python3
"""
Arista EOS switch health monitor — sends status and RRD data to Xymon.

Polls each Arista switch defined in CONF_DIR/*.cfg via SSH (user EXEC mode,
no enable required), then sends 6 Xymon status columns per switch.

Usage:
    python3 arista_monitor.py              # poll all configured switches
    python3 arista_monitor.py arista1      # poll one switch by short name

Environment variables:
    ARISTA_MONITOR_CONF_DIR   Directory containing *.cfg files.
                              Default: /etc/xymon/conf.d
    ARISTA_MONITOR_DATA_DIR   Directory for per-switch SQLite DBs.
                              Default: /var/lib/xymon/arista-monitor

Xymon columns produced per switch:
    cpu          Load average and top EOS process CPU usage
    memory       Physical memory used %
    interfaces   Per-port status, new flaps since last poll, error/CRC counts
    hardware     PSU status, fan status, temperature (show environment all)
    net          Bandwidth on configured uplink ports: current rate and
                 95th-percentile vs commitment
    stp          Spanning-tree health: port states, BPDU guard, err-disabled

Port flap counts and bandwidth samples are stored in a SQLite DB per switch
under DATA_DIR.  Flap deltas are computed each poll cycle; bandwidth 95th
percentile is calculated over a configurable rolling window (default 24 h).

A Xymon 'data' message is sent each run (column: net) so Xymon's rrddata
channel stores uplink bandwidth in net.rrd for native Xymon graphing.
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

CONF_DIR = os.environ.get("ARISTA_MONITOR_CONF_DIR", "/etc/xymon/conf.d")
DATA_DIR = os.environ.get("ARISTA_MONITOR_DATA_DIR", "/var/lib/xymon/arista-monitor")

SSH_BASE = [
    "ssh",
    "-o", "BatchMode=yes",
    "-o", "StrictHostKeyChecking=no",
    "-o", "ConnectTimeout=10",
]

GREEN  = "green"
YELLOW = "yellow"
RED    = "red"
PURPLE = "purple"

COLUMNS = ["cpu", "memory", "interfaces", "hardware", "net", "stp"]


# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

def find_configs(target=None):
    """Yield (short_name, fqdn, cfg_path, configparser) for each switch config.

    Scans CONF_DIR for *.cfg files.  Each file may contain one or more
    [switch-name] sections; a valid section must have HOST and XYMON_HOSTNAME.
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
            if target and section != target:
                continue
            fqdn = cget(cfg, section, "XYMON_HOSTNAME")
            yield section, fqdn, cfg_path, cfg


def cget(cfg, section, key, fallback=None, cast=None):
    try:
        val = cfg.get(section, key)
        return cast(val) if cast else val
    except (configparser.NoSectionError, configparser.NoOptionError):
        return fallback


# ---------------------------------------------------------------------------
# SSH helper
# ---------------------------------------------------------------------------

def ssh_run(host, user, key, command, timeout=30):
    """Run a single command on the Arista via SSH (BatchMode, user EXEC).

    Returns stdout as a stripped string.  Raises on timeout or connection
    failure — caller decides whether to abort or continue.
    """
    cmd = SSH_BASE + (["-i", key] if key else []) + [f"{user}@{host}", command]
    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True, timeout=timeout
        )
        return result.stdout.strip()
    except subprocess.TimeoutExpired as exc:
        raise TimeoutError(f"SSH timed out: {command}") from exc
    except Exception as exc:
        raise RuntimeError(f"SSH failed ({command}): {exc}") from exc


# ---------------------------------------------------------------------------
# Parsers — each returns structured data or None / empty on parse failure
# ---------------------------------------------------------------------------

def _rate_to_bps(value_str, unit):
    """Convert rate value + unit string to bits per second (int)."""
    try:
        val = float(value_str)
    except ValueError:
        return 0
    mult = {"bps": 1, "kbps": 1_000, "Mbps": 1_000_000, "Gbps": 1_000_000_000}
    return int(val * mult.get(unit, 1))


def parse_cpu(text):
    """Parse 'show processes top once'.
    Returns (load1, load5, load15, used_pct) or None.
    """
    m = re.search(r'load average:\s*([\d.]+),\s*([\d.]+),\s*([\d.]+)', text)
    if not m:
        return None
    l1, l5, l15 = float(m.group(1)), float(m.group(2)), float(m.group(3))
    m2 = re.search(r'%Cpu\(s\)\s*:\s*([\d.]+)\s+us.*?([\d.]+)\s+id', text, re.IGNORECASE)
    if m2:
        used = round(100.0 - float(m2.group(2)), 1)
    else:
        used = round(float(m.group(1)) / os.cpu_count() * 100 if os.cpu_count() else 0, 1)
    return l1, l5, l15, used


def parse_top_processes(text):
    """Parse process rows from 'show processes top once'.
    Returns list of (name, cpu_pct) sorted descending, top 10 non-zero.
    """
    procs = []
    in_procs = False
    for line in text.splitlines():
        if re.match(r'\s*PID\s+USER', line, re.IGNORECASE):
            in_procs = True
            continue
        if not in_procs:
            continue
        parts = line.split()
        if len(parts) < 12:
            continue
        try:
            cpu = float(parts[8])
            name = parts[11]
            if cpu > 0:
                procs.append((name, cpu))
        except (ValueError, IndexError):
            continue
    procs.sort(key=lambda x: -x[1])
    return procs[:10]


def parse_memory(text):
    """Parse 'show processes top once' for memory.
    Returns (used_pct, total_kb, used_kb, free_kb) or None.
    """
    # KiB Mem: 3796032 total, 1234567 free, 2345678 used, ...
    m = re.search(
        r'(?:KiB|MiB)\s+Mem\s*:\s*([\d,. ]+)\s+total,\s*([\d,. ]+)\s+free,\s*([\d,. ]+)\s+used',
        text, re.IGNORECASE
    )
    if not m:
        return None
    def _kb(s):
        return int(float(s.replace(",", "").strip()))
    total = _kb(m.group(1))
    free  = _kb(m.group(2))
    used  = _kb(m.group(3))
    # MiB variant needs unit conversion
    if 'MiB' in text[:m.start() + 10]:
        total, free, used = total * 1024, free * 1024, used * 1024
    if total == 0:
        return None
    used_pct = round(used / total * 100, 1)
    return used_pct, total, used, free


def parse_version_uptime(text):
    """Extract uptime string from 'show version'."""
    m = re.search(r'Uptime\s*:\s*(.+)', text, re.IGNORECASE)
    if m:
        return m.group(1).strip()
    m = re.search(r'[Uu]p\s+([\d][\d\w ,]+?)(?:\n|$)', text)
    return m.group(1).strip().rstrip(",") if m else "unknown"


def parse_version_model(text):
    """Extract hardware model from 'show version'."""
    m = re.search(r'Arista\s+([\w-]+)', text)
    return m.group(1) if m else "unknown"


def parse_all_interfaces(text):
    """Parse bulk 'show interfaces' output.

    Returns dict: port -> {connected, in_bps, out_bps, crc, input_errors,
                           output_errors, input_drops, flap_count}
    Rates are in bits per second (bps).
    """
    result = {}
    # Each interface block begins with "<PortName> is <status>"
    blocks = re.split(
        r'\n(?=(?:Ethernet|Management|Port-Channel)\S*\s+is\s+)',
        text.strip()
    )
    for block in blocks:
        hdr = re.match(
            r'((?:Ethernet|Management|Port-Channel)\S*)\s+is\s+(\w[\w-]*)',
            block
        )
        if not hdr:
            continue
        port = hdr.group(1)
        raw_status = hdr.group(2).lower()
        first_line = block.split('\n')[0].lower()
        if '(connected)' in first_line:
            connected = True
        elif '(notconnect' in first_line:
            connected = False
        else:
            connected = raw_status == 'up'

        # Rates — take the first match to avoid duplicate rate lines in Arista output
        rate_in_m  = re.search(r'input rate\s+([\d.]+)\s*(bps|kbps|Mbps|Gbps)',  block)
        rate_out_m = re.search(r'output rate\s+([\d.]+)\s*(bps|kbps|Mbps|Gbps)', block)
        in_bps  = _rate_to_bps(rate_in_m.group(1),  rate_in_m.group(2))  if rate_in_m  else 0
        out_bps = _rate_to_bps(rate_out_m.group(1), rate_out_m.group(2)) if rate_out_m else 0

        def _i(pat):
            m = re.search(pat, block, re.IGNORECASE)
            return int(m.group(1)) if m else 0

        # Arista: "0 input errors, 0 CRC, 0 alignment, 0 symbol"
        crc           = _i(r'(\d+)\s+CRC')
        input_errors  = _i(r'(\d+)\s+input errors')
        output_errors = _i(r'(\d+)\s+output errors')
        input_drops   = _i(r'(\d+)\s+input discards')

        # "895 link status changes since last cleared"
        # or "895 link status changes, last change ..."
        flap_m = re.search(r'(\d+)\s+link\s+status\s+changes', block, re.IGNORECASE)
        flap_count = int(flap_m.group(1)) if flap_m else 0

        result[port] = {
            "connected":      connected,
            "in_bps":         in_bps,
            "out_bps":        out_bps,
            "crc":            crc,
            "input_errors":   input_errors,
            "output_errors":  output_errors,
            "input_drops":    input_drops,
            "flap_count":     flap_count,
        }
    return result


def parse_environment(text):
    """Parse 'show environment all'.

    Trusts Arista's own Ok/NotOk indicators; flags any non-Ok status line.
    Returns (issues, max_temp_c, psu_ok, fan_ok, psu_wattage_lines).
    """
    issues  = []
    max_temp = None
    psu_ok  = True
    fan_ok  = True
    psu_watt = []

    # System temperature status line
    st_m = re.search(r'System temperature status\s*:\s*(\S+)', text, re.IGNORECASE)
    if st_m and st_m.group(1).lower() != 'ok':
        issues.append(f"System temperature status: {st_m.group(1)}")

    # Per-component status lines — "  Status: Ok" / "  Status: NotOk"
    for line in text.splitlines():
        m = re.search(r'^\s+Status\s*:\s*(\S+)', line)
        if m and m.group(1).lower() not in ('ok',):
            issues.append(line.strip()[:100])

    # PSU wattage lines for display
    for m in re.finditer(r'(PowerSupply\d+)\s*\(([^)]+)\).*?Output Power\s*:\s*(\d+)', text, re.DOTALL):
        psu_watt.append(f"{m.group(1)} ({m.group(2)}): {m.group(3)}W output")

    # Highest temperature across all sensors
    for m in re.finditer(r'Temperature\s*:\s*([\d.]+)\s*C', text):
        val = float(m.group(1))
        if max_temp is None or val > max_temp:
            max_temp = val

    # Determine PSU/fan health from issues
    for issue in issues:
        lc = issue.lower()
        if 'fan' in lc:
            fan_ok = False
        elif 'supply' in lc or 'psu' in lc or 'powersupply' in lc:
            psu_ok = False

    return issues, max_temp, psu_ok, fan_ok, psu_watt


def parse_stp_ports(text):
    """Parse 'show spanning-tree' port table.

    Returns (port_states, err_disabled_stp) where port_states is a dict of
    port -> state-string, and err_disabled_stp is a list of port names that
    appear in err-disabled or BPD-guard state within the STP output.
    """
    port_states = {}
    err_disabled_stp = []

    for m in re.finditer(
        r'^(\S+/?\d+)\s+(\w+)\s+(\w+)\s+\d+\s+[\d.]+\s+(.+)',
        text, re.MULTILINE
    ):
        port  = m.group(1)
        state = m.group(3).strip().upper()
        ptype = m.group(4).strip()
        port_states[port] = (state, ptype)
        if state in ('BPD', 'ERR', 'EDE', 'BRK'):
            err_disabled_stp.append(f"{port} (STP state: {state})")

    return port_states, err_disabled_stp


def parse_interfaces_status_errdis(text):
    """Parse 'show interfaces status' and return list of err-disabled port names."""
    errdis = []
    for line in text.splitlines():
        if 'err-disabled' in line.lower():
            parts = line.split()
            if parts:
                errdis.append(parts[0])
    return errdis


def parse_privilege(text):
    """Parse 'show privilege' output.  Returns privilege level int, default 1."""
    m = re.search(r'privilege level is\s+(\d+)', text, re.IGNORECASE)
    return int(m.group(1)) if m else 1


# Log event patterns for privileged-mode log parsing.
_LINK_PATTERNS = [
    r'LINEPROTO.*changed state',
    r'%ETH-\d+-(SPEED|HALF|FULL)',
    r'Interface \S+.*changed.*state',
    r'link.*(?:up|down)',
]
_STP_PATTERNS = [
    r'%SPANTREE',
    r'BPDUGUARD',
    r'topology.change',
    r'%STP-',
    r'spanning.tree',
]


def parse_log_events(text, patterns):
    """Extract log lines matching any pattern (case-insensitive).
    Returns up to the last 15 matching lines.
    """
    events = []
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        for pat in patterns:
            if re.search(pat, stripped, re.IGNORECASE):
                events.append(stripped)
                break
    return events[-15:]


# ---------------------------------------------------------------------------
# SQLite — port flap tracking and bandwidth 95th-pct
# ---------------------------------------------------------------------------

def _db_open(db_path):
    os.makedirs(os.path.dirname(db_path), exist_ok=True)
    con = sqlite3.connect(db_path)
    con.execute(
        "CREATE TABLE IF NOT EXISTS port_snapshots "
        "(ts INTEGER NOT NULL, port TEXT NOT NULL, count INTEGER NOT NULL)"
    )
    con.execute(
        "CREATE TABLE IF NOT EXISTS bw_samples "
        "(ts INTEGER NOT NULL, in_bps REAL NOT NULL, out_bps REAL NOT NULL)"
    )
    con.commit()
    return con


def flap_get_deltas_and_store(con, ts, current_counts):
    """Compute new-flap deltas for each port vs last stored snapshot.

    Returns dict: port -> delta (0 on first run; treats counter clear as all-new).
    Stores new snapshots and prunes rows older than 7 days.
    """
    deltas = {}
    for port, current in current_counts.items():
        row = con.execute(
            "SELECT count FROM port_snapshots WHERE port=? ORDER BY ts DESC LIMIT 1",
            (port,)
        ).fetchone()
        if row is None:
            deltas[port] = 0
        else:
            last = row[0]
            deltas[port] = (current - last) if current >= last else current
    con.executemany(
        "INSERT INTO port_snapshots VALUES (?,?,?)",
        [(ts, p, c) for p, c in current_counts.items()]
    )
    con.execute("DELETE FROM port_snapshots WHERE ts < ?", (ts - 86400 * 7,))
    con.commit()
    return deltas


def bw_store(con, ts, in_bps, out_bps):
    con.execute("INSERT INTO bw_samples VALUES (?,?,?)", (ts, in_bps, out_bps))
    con.execute("DELETE FROM bw_samples WHERE ts < ?", (ts - 86400 * 30,))
    con.commit()


def bw_percentile(con, window_hours):
    """Return (in_p95_mbps, out_p95_mbps, n_samples).  Values None if < 2 samples."""
    cutoff = int(time.time()) - window_hours * 3600
    rows = con.execute(
        "SELECT in_bps, out_bps FROM bw_samples WHERE ts >= ? ORDER BY ts", (cutoff,)
    ).fetchall()
    n = len(rows)
    if n < 2:
        return None, None, n
    in_s  = sorted(r[0] for r in rows)
    out_s = sorted(r[1] for r in rows)
    idx   = min(int(0.95 * n), n - 1)
    return in_s[idx] / 1_000_000, out_s[idx] / 1_000_000, n


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

def xymon_send_status(xymon_host, xymon_port, fqdn, column, color, body):
    ts  = time.strftime("%a %b %d %H:%M:%S %Z %Y")
    msg = f"status+600 {fqdn}.{column} {color} {ts}\n\n{body}\n"
    _xymon_tcp(xymon_host, xymon_port, msg)
    print(f"  [{color.upper():6}] {fqdn}.{column}")


def xymon_send_data(xymon_host, xymon_port, fqdn, rrd_name, ds_dict):
    lines = [f"data {fqdn}.{rrd_name}", f"[{rrd_name}.rrd]"]
    for ds, val in ds_dict.items():
        lines.append(f"DS:{ds}:GAUGE:600:0:U {int(val)}")
    _xymon_tcp(xymon_host, xymon_port, "\n".join(lines) + "\n")


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

def col_cpu(cpu_tuple, procs, uptime_str, model, cfg, section):
    if not cpu_tuple:
        return RED, "Could not parse 'show processes top once' output."
    l1, l5, l15, used_pct = cpu_tuple
    warn = cget(cfg, section, "CPU_WARN", 70, float)
    crit = cget(cfg, section, "CPU_CRIT", 85, float)
    color = threshold_color(used_pct, warn, crit)
    body  = (f"CPU used: {used_pct:.1f}%   "
             f"Load avg: {l1:.2f} / {l5:.2f} / {l15:.2f}  (1/5/15 min)\n"
             f"Uptime: {uptime_str}   Model: {model}\n")
    if procs:
        body += "\nTop processes (%CPU):\n"
        for name, pct in procs:
            marker = "  <-- !" if pct >= 20 else ""
            body  += f"  {pct:5.1f}%  {name}{marker}\n"
    return color, body


def col_memory(mem_tuple, cfg, section):
    if not mem_tuple:
        return RED, "Could not parse memory from 'show processes top once'."
    used_pct, total_kb, used_kb, free_kb = mem_tuple
    warn  = cget(cfg, section, "MEM_WARN", 80, int)
    crit  = cget(cfg, section, "MEM_CRIT", 90, int)
    color = threshold_color(used_pct, warn, crit)
    body  = (f"Memory used: {used_pct:.1f}%\n"
             f"  Total: {total_kb / 1024:.0f} MB\n"
             f"  Used:  {used_kb  / 1024:.0f} MB\n"
             f"  Free:  {free_kb  / 1024:.0f} MB\n")
    return color, body


def col_interfaces(iface_data, flap_deltas, log_events, priv_level, cfg, section):
    """Build interfaces column body.

    Flags ports with new flaps (since last poll) or high error/CRC counts.
    Shows all physically connected ports plus any with recent flaps.
    When priv_level >= 15, appends recent link-state log events.
    """
    flap_warn  = cget(cfg, section, "FLAP_WARN",     1,  int)
    flap_crit  = cget(cfg, section, "FLAP_CRIT",     5,  int)
    err_warn   = cget(cfg, section, "IFACE_ERR_WARN", 10, int)
    err_crit   = cget(cfg, section, "IFACE_ERR_CRIT", 100, int)

    colors = []
    flagged_lines = []
    summary_lines = ["Port             Status   Flaps  In Mbps  Out Mbps  Errors  CRC  Drops"]

    # Show connected ports and any port that had flaps this cycle
    ports_to_show = {
        p for p, d in iface_data.items()
        if d["connected"] or flap_deltas.get(p, 0) > 0
    }

    for port in sorted(ports_to_show, key=lambda x: (not iface_data[x]["connected"], x)):
        d        = iface_data[port]
        new_flaps = flap_deltas.get(port, 0)
        errs     = d["input_errors"] + d["output_errors"]
        crc      = d["crc"]
        drops    = d["input_drops"]
        in_m     = d["in_bps"]  / 1_000_000
        out_m    = d["out_bps"] / 1_000_000
        status   = "up" if d["connected"] else "DOWN"

        c_flap = threshold_color(new_flaps, flap_warn, flap_crit)
        c_err  = threshold_color(errs + crc, err_warn,  err_crit)
        c_port = worst_color(c_flap, c_err)
        colors.append(c_port)

        flag = f"  [{c_port}]" if c_port != GREEN else ""
        line = (f"{port:<16} {status:<8} {new_flaps:>5}  "
                f"{in_m:>7.2f}  {out_m:>8.2f}  "
                f"{errs:>6}  {crc:>3}  {drops:>5}{flag}")
        summary_lines.append(line)
        if c_port != GREEN:
            flagged_lines.append(f"  {port}: {new_flaps} new flap(s), {errs} errors, {crc} CRC")

    color = worst_color(*colors) if colors else GREEN
    body  = "\n".join(summary_lines) + "\n"
    if flagged_lines:
        body += "\nFlagged ports:\n" + "\n".join(flagged_lines) + "\n"

    if log_events:
        body += "\nRecent link events (from syslog):\n"
        for e in log_events:
            body += f"  {e}\n"
    elif priv_level < 15:
        body += f"\nLink event log: not available (privilege {priv_level} — needs 15)\n"

    return color, body


def col_hardware(issues, max_temp, psu_ok, fan_ok, psu_watt):
    """Color based solely on Arista-reported faults.

    Temperature is displayed informational only — Arista firmware flags its
    own thermal violations; we trust that rather than applying external limits.
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

    if psu_watt:
        lines.append("")
        lines.extend(psu_watt)

    if max_temp is not None:
        lines.append(f"\nMax sensor temperature: {max_temp:.1f} C  (Arista: Ok)")
    else:
        lines.append("\nTemperature: not parsed from output")

    return color, "\n".join(lines)


def col_net(uplink_ports, iface_data, in_95, out_95, n_samp, cfg, section):
    """Combine current uplink bandwidth and 95th percentile into net column."""
    commit  = cget(cfg, section, "COMMITMENT_MBPS",  100, float)
    window  = cget(cfg, section, "BW_WINDOW_HOURS",   24, int)

    # Show per-uplink rates
    lines = ["Uplink              In Mbps   Out Mbps"]
    total_in = total_out = 0
    for port in uplink_ports:
        d = iface_data.get(port)
        if d:
            in_m  = d["in_bps"]  / 1_000_000
            out_m = d["out_bps"] / 1_000_000
            total_in  += d["in_bps"]
            total_out += d["out_bps"]
        else:
            in_m = out_m = 0.0
            lines.append(f"  {port}: not found in interface data")
        lines.append(f"{port:<20} {in_m:>8.2f}  {out_m:>9.2f}")
    if len(uplink_ports) > 1:
        lines.append(f"{'(combined)':<20} {total_in/1_000_000:>8.2f}  {total_out/1_000_000:>9.2f}")

    lines.append("")

    if in_95 is None:
        color  = GREEN
        needed = max(0, window * 12 - n_samp)
        lines.append(
            f"95th percentile: accumulating "
            f"({n_samp} of {window * 12} samples, ~{needed * 5} min to go)"
        )
        lines.append(f"Commitment: {commit:.0f} Mbps")
    else:
        peak       = max(in_95, out_95)
        pct_commit = peak / commit * 100 if commit > 0 else 0
        color      = threshold_color(peak, commit * 0.85, commit)
        lines.append(f"95th percentile (last {window}h, {n_samp} samples):")
        lines.append(f"  In:  {in_95:.2f} Mbps")
        lines.append(f"  Out: {out_95:.2f} Mbps")
        lines.append(
            f"  Peak 95th: {peak:.2f} Mbps  =  {pct_commit:.0f}% of "
            f"{commit:.0f} Mbps commitment"
        )

    return color, "\n".join(lines) + "\n"


def col_stp(port_states, stp_errdis, iface_errdis, stp_events, priv_level, cfg, section):
    """Build spanning-tree column body.

    Red if any port is err-disabled.
    Yellow if any port is in an unexpected non-forwarding state (not FWD/BLK/DIS).
    Green if all ports are FWD as expected.
    When priv_level >= 15, appends recent STP log events.
    """
    all_errdis = sorted(set(iface_errdis + stp_errdis))
    unexpected = []
    for port, (state, ptype) in port_states.items():
        if state not in ("FWD", "BLK", "DIS", "LIS", "LRN"):
            unexpected.append(f"{port}: state={state} type={ptype}")

    lines = []
    if all_errdis:
        color = RED
        lines.append(f"Err-disabled ports: {len(all_errdis)}")
        for p in all_errdis:
            lines.append(f"  ERR-DISABLED: {p}")
    elif unexpected:
        color = YELLOW
        lines.append("Unexpected STP port states:")
        for u in unexpected:
            lines.append(f"  {u}")
    else:
        color = GREEN
        fwd_count = sum(1 for s, _ in port_states.values() if s == "FWD")
        blk_count = sum(1 for s, _ in port_states.values() if s == "BLK")
        lines.append("Spanning tree: normal")
        lines.append(f"  Forwarding: {fwd_count}  Blocking: {blk_count}")

    # Show BPDU guard / Edge type summary
    edge_ports = [p for p, (s, t) in port_states.items() if "Edge" in t]
    boundary_ports = [p for p, (s, t) in port_states.items() if "Boundary" in t]
    if edge_ports or boundary_ports:
        lines.append("")
        if edge_ports:
            lines.append(f"Portfast (Edge) ports ({len(edge_ports)}): {', '.join(sorted(edge_ports))}")
        if boundary_ports:
            lines.append(f"Boundary ports (STP BPDUs detected) ({len(boundary_ports)}): "
                         f"{', '.join(sorted(boundary_ports))}")

    body = "\n".join(lines) + "\n"

    if stp_events:
        body += "\nRecent STP events (from syslog):\n"
        for e in stp_events:
            body += f"  {e}\n"
    elif priv_level < 15:
        body += f"\nSTP event log: not available (privilege {priv_level} — needs 15)\n"

    return color, body


# ---------------------------------------------------------------------------
# Poll one switch
# ---------------------------------------------------------------------------

def poll(name, fqdn, cfg_path, cfg):
    section = name

    xymon_host  = cget(cfg, section, "XYMON_HOST",      "xymon.example.com")
    xymon_port  = cget(cfg, section, "XYMON_PORT",      "1984")
    sw_host     = cget(cfg, section, "HOST")
    ssh_user    = cget(cfg, section, "SSH_USER",        "admin")
    ssh_key     = cget(cfg, section, "SSH_KEY")
    uplink_str  = cget(cfg, section, "UPLINK_PORTS",    "")
    uplink_ports = uplink_str.split() if uplink_str else []
    bw_win      = cget(cfg, section, "BW_WINDOW_HOURS", 24, int)

    os.makedirs(DATA_DIR, exist_ok=True)
    db_path = os.path.join(DATA_DIR, f"{name}.db")

    print(f"\n{'='*60}")
    print(f"{fqdn}  ({sw_host})")
    print(f"{'='*60}")

    # --- Check privilege level first (determines available commands) ---
    try:
        priv_text  = ssh_run(sw_host, ssh_user, ssh_key, "show privilege", timeout=10)
    except Exception as exc:
        print(f"  SSH failed: {exc}")
        purple_all(xymon_host, xymon_port, fqdn, f"SSH failed: {exc}")
        return
    priv_level = parse_privilege(priv_text)
    limited    = priv_level < 15
    print(f"  Privilege level: {priv_level}{' (limited — log data not available)' if limited else ''}")

    # --- Collect data ---
    raw = {}
    commands = [
        ("show version",            "version"),
        ("show processes top once", "top"),
        ("show interfaces",         "interfaces"),
        ("show environment all",    "env"),
        ("show spanning-tree",      "stp"),
        ("show interfaces status",  "iface_status"),
    ]
    if not limited:
        # show logging requires privilege 15 on EOS
        commands.append(("show logging | tail 200", "log"))

    try:
        for cmd, key in commands:
            raw[key] = ssh_run(sw_host, ssh_user, ssh_key, cmd)
    except Exception as exc:
        print(f"  Collection error: {exc}")
        purple_all(xymon_host, xymon_port, fqdn, f"Data collection error: {exc}")
        return

    # --- Parse ---
    cpu_t       = parse_cpu(raw["top"])
    procs       = parse_top_processes(raw["top"])
    mem_t       = parse_memory(raw["top"])
    uptime_str  = parse_version_uptime(raw["version"])
    model       = parse_version_model(raw["version"])
    iface_data  = parse_all_interfaces(raw["interfaces"])
    env_issues, max_temp, psu_ok, fan_ok, psu_watt = parse_environment(raw["env"])
    port_states, stp_errdis = parse_stp_ports(raw["stp"])
    iface_errdis            = parse_interfaces_status_errdis(raw["iface_status"])
    log_text    = raw.get("log", "")
    link_events = parse_log_events(log_text, _LINK_PATTERNS)
    stp_events  = parse_log_events(log_text, _STP_PATTERNS)

    # --- SQLite ---
    now = int(time.time())
    con = _db_open(db_path)

    # Flap deltas for all parsed ports
    current_flaps = {p: d["flap_count"] for p, d in iface_data.items()}
    flap_deltas   = flap_get_deltas_and_store(con, now, current_flaps)

    # Bandwidth from uplink ports (aggregate)
    total_in_bps = total_out_bps = 0
    for port in uplink_ports:
        d = iface_data.get(port)
        if d:
            total_in_bps  += d["in_bps"]
            total_out_bps += d["out_bps"]

    if uplink_ports:
        bw_store(con, now, total_in_bps, total_out_bps)
    in_95, out_95, n_samp = bw_percentile(con, bw_win)
    con.close()

    # --- Send columns ---
    c, b = col_cpu(cpu_t, procs, uptime_str, model, cfg, section)
    xymon_send_status(xymon_host, xymon_port, fqdn, "cpu", c, b)

    c, b = col_memory(mem_t, cfg, section)
    xymon_send_status(xymon_host, xymon_port, fqdn, "memory", c, b)

    c, b = col_interfaces(iface_data, flap_deltas, link_events, priv_level, cfg, section)
    xymon_send_status(xymon_host, xymon_port, fqdn, "interfaces", c, b)

    c, b = col_hardware(env_issues, max_temp, psu_ok, fan_ok, psu_watt)
    xymon_send_status(xymon_host, xymon_port, fqdn, "hardware", c, b)

    c, b = col_net(uplink_ports, iface_data, in_95, out_95, n_samp, cfg, section)
    xymon_send_status(xymon_host, xymon_port, fqdn, "net", c, b)
    if uplink_ports:
        xymon_send_data(xymon_host, xymon_port, fqdn, "net",
                        {"in": total_in_bps, "out": total_out_bps})

    c, b = col_stp(port_states, stp_errdis, iface_errdis, stp_events, priv_level, cfg, section)
    xymon_send_status(xymon_host, xymon_port, fqdn, "stp", c, b)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    target  = sys.argv[1] if len(sys.argv) > 1 else None
    configs = list(find_configs(target))

    if not configs:
        msg = f"No config found for switch '{target}'" if target \
              else "No *.cfg files found under CONF_DIR"
        print(msg, file=sys.stderr)
        sys.exit(1)

    for args in configs:
        poll(*args)

    print("\nDone.")


if __name__ == "__main__":
    main()
