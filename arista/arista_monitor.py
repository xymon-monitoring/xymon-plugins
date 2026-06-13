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
    hardware     PSU status, fan status, temperature (show environment all)
    net          Uplink bandwidth (95th pct vs commitment), per-port status,
                 and spanning-tree health (err-disabled, unexpected states)

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

CONF_DIR     = os.environ.get("ARISTA_MONITOR_CONF_DIR", "/etc/xymon/conf.d")
DATA_DIR     = os.environ.get("ARISTA_MONITOR_DATA_DIR", "/var/lib/xymon/arista-monitor")
XYMON_RRD_DIR = os.environ.get("XYMON_RRD_DIR",          "/var/lib/xymon/rrd")

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

COLUMNS = ["cpu", "memory", "hardware", "net"]


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
            dt = cget(cfg, section, "DEVICE_TYPE")
            if dt and dt.lower() != "arista":
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

    Returns (used_pct, total_kb, app_used_kb, available_kb) or None.

    Strips page cache and buffers so used_pct reflects application memory
    pressure rather than kernel bookkeeping:
      app_used  = total - free - buffers - cached   (old top format)
      app_used  = total - free - buff/cache          (new top format)
      available = total - app_used

    Old format (EOS 4.x / pre-3.3 top):
      KiB Mem:  X total,  X used,    X free,  X buffers
      KiB Swap: X total,  X used,    X free,  X cached
    New format:
      KiB Mem:  X total,  X free,    X used,  X buff/cache
    """
    m = re.search(r'(KiB|MiB)\s+Mem\s*:(.+)', text, re.IGNORECASE)
    if not m:
        return None
    is_mib   = m.group(1).upper() == 'MiB'
    mem_line = m.group(2)

    def _extract(label, line):
        mm = re.search(r'([\d,. ]+)\s+' + label, line, re.IGNORECASE)
        return int(float(mm.group(1).replace(',', '').strip())) if mm else None

    total = _extract('total', mem_line)
    free  = _extract('free',  mem_line)
    if not total or free is None:
        return None

    buff_cache = _extract(r'buff/cache', mem_line)
    if buff_cache is not None:
        # New top: buff/cache combined on Mem line
        reclaimable = buff_cache
    else:
        # Old top: buffers on Mem line, page cache on Swap line
        buffers = _extract('buffers', mem_line) or 0
        swap_m  = re.search(r'(?:KiB|MiB)\s+Swap\s*:(.+)', text, re.IGNORECASE)
        cached  = (_extract('cached', swap_m.group(1)) if swap_m else None) or 0
        reclaimable = buffers + cached

    app_used  = max(0, total - free - reclaimable)
    available = total - app_used
    if is_mib:
        total, app_used, available = total * 1024, app_used * 1024, available * 1024
    if total == 0:
        return None
    return round(app_used / total * 100, 1), total, app_used, available


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


_STP_STATE_MAP = {
    "FORWARDING":  "FWD",
    "BLOCKING":    "BLK",
    "DISABLED":    "DIS",
    "LISTENING":   "LIS",
    "LEARNING":    "LRN",
    "BROKEN":      "BRK",
    "BPDUGUARD":   "BPD",
    "ERRDISABLED": "ERR",
}


def parse_stp_ports(text):
    """Parse 'show spanning-tree' port table.

    Returns (port_states, err_disabled_stp) where port_states is a dict of
    port -> state-string, and err_disabled_stp is a list of port names that
    appear in err-disabled or BPD-guard state within the STP output.

    EOS 4.x outputs full-word states (FORWARDING, BLOCKING, …); newer EOS
    and some versions use abbreviations (FWD, BLK, …).  _STP_STATE_MAP
    normalises both to the abbreviated form so col_stp comparisons are
    version-independent.
    """
    port_states = {}
    err_disabled_stp = []

    for m in re.finditer(
        r'^(\S+/?\d+)\s+(\w+)\s+(\w+)\s+\d+\s+[\d.]+\s+(.+)',
        text, re.MULTILINE
    ):
        port      = m.group(1)
        state_raw = m.group(3).strip().upper()
        state     = _STP_STATE_MAP.get(state_raw, state_raw)
        ptype = m.group(4).strip()
        port_states[port] = (state, ptype)
        if state in ('BPD', 'ERR', 'EDE', 'BRK'):
            err_disabled_stp.append(f"{port} (STP state: {state})")

    return port_states, err_disabled_stp


def parse_interfaces_status(text):
    """Parse 'show interfaces status'.

    Returns (iface_meta, errdis) where:
      iface_meta  dict: Ethernet-expanded port name ->
                        {'description': str, 'speed': str}
      errdis      list of expanded port names that are err-disabled

    Port names are expanded from EOS abbreviations (Et, Ma, Po) to match
    the long-form keys produced by parse_all_interfaces ('show interfaces').
    Speed strips the 'a-' auto-negotiated prefix so '1G', '10G', etc. are
    returned rather than 'a-1G'.
    """
    iface_meta = {}
    errdis = []

    # Find the header line to get exact column byte offsets.
    header = None
    for line in text.splitlines():
        if re.match(r'\s*Port\s+Name\s+Status', line, re.IGNORECASE):
            header = line
            break
    if header is None:
        return iface_meta, errdis

    name_col   = header.index('Name')
    status_col = header.index('Status')
    speed_col  = header.index('Speed')
    type_col   = header.index('Type') if 'Type' in header else speed_col + 10

    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith('Port'):
            continue
        if len(line) < status_col:
            continue
        short = line[:name_col].strip()
        if not short:
            continue

        # Expand abbreviated names: Et→Ethernet, Ma→Management, Po→Port-Channel
        port = re.sub(r'^Et(\d)', r'Ethernet\1', short)
        port = re.sub(r'^Ma(\d)', r'Management\1', port)
        port = re.sub(r'^Po(\d)', r'Port-Channel\1', port)

        description  = line[name_col:status_col].strip() or 'Unknown'
        status_field = line[status_col:speed_col].strip() if len(line) > speed_col else line[status_col:].strip()
        speed_raw    = line[speed_col:type_col].strip()   if len(line) > speed_col else 'auto'
        speed        = re.sub(r'^a-', '', speed_raw) or 'auto'

        iface_meta[port] = {'description': description, 'speed': speed}

        if 'err-disabled' in status_field.lower():
            errdis.append(port)

    return iface_meta, errdis


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


def xymon_send_data(xymon_host, xymon_port, fqdn, column, ds_dict, rrd_file=None):
    if rrd_file is None:
        rrd_file = column
    lines = [f"data {fqdn}.{column}", f"[{rrd_file}.rrd]"]
    for ds, val in ds_dict.items():
        lines.append(f"DS:{ds}:GAUGE:600:0:U {int(val)}")
    _xymon_tcp(xymon_host, xymon_port, "\n".join(lines) + "\n")


def port_to_rrd(name):
    """Map a port name to an ifstat.*.rrd stem for the [ifstat] graph stanza."""
    return "ifstat." + re.sub(r'[/\s]+', '-', name)


def expand_port_name(name):
    """Expand EOS abbreviated port name to long form (Et→Ethernet, Ma→Management, Po→Port-Channel)."""
    name = re.sub(r'^Et(\d)', r'Ethernet\1', name)
    name = re.sub(r'^Ma(\d)', r'Management\1', name)
    name = re.sub(r'^Po(\d)', r'Port-Channel\1', name)
    return name


def _xymon_tcp(host, port, msg):
    try:
        with socket.create_connection((host, int(port)), timeout=10) as s:
            s.sendall(msg.encode())
    except Exception as exc:
        print(f"  Xymon TCP send failed: {exc}", file=sys.stderr)


# Standard Xymon RRA set: 5-min/30-min/2-hr/1-day resolution, 576 rows each.
_STD_RRAS = [
    "RRA:AVERAGE:0.5:1:576",
    "RRA:AVERAGE:0.5:6:576",
    "RRA:AVERAGE:0.5:24:576",
    "RRA:AVERAGE:0.5:288:576",
]

_MEM_RRD_SPEC = ["--step", "300", "DS:realmempct:GAUGE:600:0:U"] + _STD_RRAS
_NET_RRD_SPEC = ["--step", "300", "DS:in:GAUGE:600:0:U", "DS:out:GAUGE:600:0:U"] + _STD_RRAS
_LA_RRD_SPEC  = ["--step", "300", "DS:la:GAUGE:600:U:U"] + _STD_RRAS
_IFSTAT_RRD_SPEC = ["--step", "300",
                    "DS:bytesReceived:GAUGE:600:0:U",
                    "DS:bytesSent:GAUGE:600:0:U"] + _STD_RRAS


def _rrd_update_memory(fqdn, real_pct, swap_pct=0.0):
    """Directly update Xymon memory RRD files via rrdtool.

    Xymon 5.x populates memory.*.rrd only from its client-data channel;
    external monitors cannot inject into that channel.  Calling rrdtool
    directly is the only reliable way to get the standard [memory] graph
    to appear for a non-client host.

    Uses timestamp 'N' (rrdtool's "now") which is always strictly after the
    xymond_rrd status-triggered update, so our value wins the race.
    """
    host_dir = os.path.join(XYMON_RRD_DIR, fqdn)
    os.makedirs(host_dir, exist_ok=True)

    files = {
        "memory.real.rrd":   int(round(real_pct)),
        "memory.actual.rrd": int(round(real_pct)),
        "memory.swap.rrd":   int(round(swap_pct)),
    }
    for fname, value in files.items():
        path = os.path.join(host_dir, fname)
        if not os.path.exists(path):
            r = subprocess.run(
                ["rrdtool", "create", path] + _MEM_RRD_SPEC,
                capture_output=True, text=True,
            )
            if r.returncode != 0:
                print(f"  rrdtool create {fname}: {r.stderr.strip()}", file=sys.stderr)
                continue
        r = subprocess.run(
            ["rrdtool", "update", path, f"N:{value}"],
            capture_output=True, text=True,
        )
        if r.returncode != 0:
            print(f"  rrdtool update {fname}: {r.stderr.strip()}", file=sys.stderr)
        else:
            print(f"  [RRD   ] {fname} → {value}%")


def _rrd_write(host_dir, fname, spec, value_str):
    """Create (if needed) and update a single RRD file."""
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
    """Update net.rrd with aggregate uplink bandwidth (bits/sec)."""
    host_dir = os.path.join(XYMON_RRD_DIR, fqdn)
    os.makedirs(host_dir, exist_ok=True)
    _rrd_write(host_dir, "net.rrd", _NET_RRD_SPEC, f"{int(in_bps)}:{int(out_bps)}")
    print(f"  [RRD   ] net.rrd → {in_bps/1_000_000:.1f}/{out_bps/1_000_000:.1f} Mbps")


def _rrd_update_cpu_la(fqdn, cpu_pct):
    """Update la.rrd with CPU %. Stored ×100 to match [la] graph CDEF (/100)."""
    host_dir = os.path.join(XYMON_RRD_DIR, fqdn)
    os.makedirs(host_dir, exist_ok=True)
    _rrd_write(host_dir, "la.rrd", _LA_RRD_SPEC, str(int(cpu_pct * 100)))
    print(f"  [RRD   ] la.rrd → {cpu_pct:.1f}%")


def _rrd_update_ifstat(fqdn, port, in_bytes_sec, out_bytes_sec):
    """Update ifstat.<port>.rrd (bytes/sec) for per-port [ifstat] graphing."""
    host_dir = os.path.join(XYMON_RRD_DIR, fqdn)
    os.makedirs(host_dir, exist_ok=True)
    fname = f"{port_to_rrd(port)}.rrd"
    _rrd_write(host_dir, fname, _IFSTAT_RRD_SPEC,
               f"{int(in_bytes_sec)}:{int(out_bytes_sec)}")


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
    used_pct, total_kb, app_used_kb, available_kb = mem_tuple
    warn  = cget(cfg, section, "MEM_WARN", 80, int)
    crit  = cget(cfg, section, "MEM_CRIT", 90, int)
    color = threshold_color(used_pct, warn, crit)
    total_mb    = int(total_kb    // 1024)
    app_used_mb = int(app_used_kb // 1024)
    avail_mb    = int(available_kb // 1024)
    pct_int     = int(round(used_pct))
    body = (
        f"Memory used: {used_pct:.1f}%  (application, excl. page cache + buffers)\n"
        f"  Total:     {total_mb} MB\n"
        f"  App used:  {app_used_mb} MB\n"
        f"  Available: {avail_mb} MB  (free + buffers + cached)\n"
        f"\n"
        f"   Memory                  Used       Total  Percentage\n"
        f"&{color} Real/Physical   {app_used_mb:>10}M {total_mb:>10}M {pct_int:>10}%\n"
        f"&{color} Actual/Virtual  {app_used_mb:>10}M {total_mb:>10}M {pct_int:>10}%\n"
        f"&green Swap/Page                  0M          0M          0%\n"
    )
    return color, body


def col_net(uplink_ports, iface_data, iface_meta, flap_deltas, link_events,
            port_states, stp_errdis, iface_errdis, stp_events,
            priv_level, in_95, out_95, n_samp, cfg, section):
    """Net column: bandwidth + interface table + spanning tree."""
    commit      = cget(cfg, section, "COMMITMENT_MBPS",    100, float)
    window      = cget(cfg, section, "BW_WINDOW_HOURS",     24, int)
    flap_warn   = cget(cfg, section, "FLAP_WARN",            1, int)
    flap_crit   = cget(cfg, section, "FLAP_CRIT",            5, int)
    err_warn    = cget(cfg, section, "IFACE_ERR_WARN",      10, int)
    err_crit    = cget(cfg, section, "IFACE_ERR_CRIT",     100, int)
    flap_ignore = {expand_port_name(p) for p in cget(cfg, section, "FLAP_IGNORE_PORTS", "").split()}
    muted_ports = {expand_port_name(p) for p in cget(cfg, section, "MUTED_PORTS",        "").split()}

    # --- Bandwidth ---
    bw_lines = ["Uplink              In Mbps   Out Mbps"]
    for port in uplink_ports:
        d = iface_data.get(port)
        if d:
            in_m  = d["in_bps"]  / 1_000_000
            out_m = d["out_bps"] / 1_000_000
        else:
            in_m = out_m = 0.0
            bw_lines.append(f"  {port}: not found in interface data")
        bw_lines.append(f"{port:<20} {in_m:>8.2f}  {out_m:>9.2f}")
    if len(uplink_ports) > 1:
        total_in  = sum(iface_data[p]["in_bps"]  for p in uplink_ports if p in iface_data)
        total_out = sum(iface_data[p]["out_bps"] for p in uplink_ports if p in iface_data)
        bw_lines.append(f"{'(combined)':<20} {total_in/1_000_000:>8.2f}  {total_out/1_000_000:>9.2f}")
    bw_lines.append("")

    if in_95 is None:
        bw_color = GREEN
        needed = max(0, window * 12 - n_samp)
        bw_lines.append(
            f"95th percentile: accumulating "
            f"({n_samp} of {window * 12} samples, ~{needed * 5} min to go)"
        )
        bw_lines.append(f"Commitment: {commit:.0f} Mbps")
    else:
        peak     = max(in_95, out_95)
        bw_color = threshold_color(peak, commit * 0.85, commit)
        bw_lines.append(f"95th percentile (last {window}h, {n_samp} samples):")
        bw_lines.append(f"  In:  {in_95:.2f} Mbps")
        bw_lines.append(f"  Out: {out_95:.2f} Mbps")
        bw_lines.append(
            f"  Peak 95th: {peak:.2f} Mbps  =  "
            f"{peak / commit * 100 if commit > 0 else 0:.0f}% of {commit:.0f} Mbps commitment"
        )
    bw_body = "\n".join(bw_lines) + "\n"

    # --- Interfaces ---
    iface_colors  = []
    flagged_lines = []
    iface_lines   = [
        f"{'Port':<16} {'Description':<25} {'Speed':>5}  {'Status':<7} "
        f"{'Flaps':>5}  {'In Mbps':>7}  {'Out Mbps':>8}  {'Errors':>6}  {'CRC':>3}  {'Drops':>5}"
    ]
    ports_to_show = {
        p for p, d in iface_data.items()
        if d["connected"] or flap_deltas.get(p, 0) > 0
    }
    for port in sorted(ports_to_show, key=lambda x: (not iface_data[x]["connected"], x)):
        d         = iface_data[port]
        meta      = iface_meta.get(port, {})
        desc      = (meta.get('description') or 'Unknown')[:25]
        speed     = meta.get('speed') or '?'
        new_flaps = flap_deltas.get(port, 0)
        errs      = d["input_errors"] + d["output_errors"]
        crc       = d["crc"]
        drops     = d["input_drops"]
        in_m      = d["in_bps"]  / 1_000_000
        out_m     = d["out_bps"] / 1_000_000
        status    = "up" if d["connected"] else "DOWN"

        # Raw color from actual counts — used for table annotation and flagged section.
        c_flap_raw = threshold_color(new_flaps, flap_warn, flap_crit)
        c_err_raw  = threshold_color(errs + crc, err_warn, err_crit)
        c_port_raw = worst_color(c_flap_raw, c_err_raw)

        # Color that counts toward overall column: suppressed for muted/ignored ports.
        if port in muted_ports:
            c_port_col = GREEN                  # fully suppressed
        elif port in flap_ignore:
            c_port_col = c_err_raw              # errors still count; flaps don't
        else:
            c_port_col = c_port_raw
        iface_colors.append(c_port_col)

        if port in muted_ports:
            note = "  [MUTED]"
        elif port in flap_ignore and c_flap_raw != GREEN:
            note = "  [flap-ignored]"
        elif c_port_raw != GREEN:
            note = f"  [{c_port_raw}]"
        else:
            note = ""
        iface_lines.append(
            f"{port:<16} {desc:<25} {speed:>5}  {status:<7} {new_flaps:>5}  "
            f"{in_m:>7.2f}  {out_m:>8.2f}  {errs:>6}  {crc:>3}  {drops:>5}{note}"
        )
        if port in muted_ports and c_port_raw != GREEN:
            flagged_lines.append(
                f"  {port} ({desc}): MUTED — {new_flaps} flap(s), {errs} errors, {crc} CRC")
        elif c_port_raw != GREEN and port not in muted_ports:
            flagged_lines.append(
                f"  {port} ({desc}): {new_flaps} new flap(s), {errs} errors, {crc} CRC")

    iface_color = worst_color(*iface_colors) if iface_colors else GREEN
    iface_body  = "\n".join(iface_lines) + "\n"
    if flagged_lines:
        iface_body += "\nFlagged ports:\n" + "\n".join(flagged_lines) + "\n"
    if link_events:
        iface_body += "\nRecent link events (from syslog):\n"
        for e in link_events:
            iface_body += f"  {e}\n"
    elif priv_level < 15:
        iface_body += f"\nLink event log: not available (privilege {priv_level} — needs 15)\n"

    # --- Spanning Tree ---
    all_errdis = sorted(set(iface_errdis + stp_errdis))
    unexpected = [
        f"{port}: state={state} type={ptype}"
        for port, (state, ptype) in port_states.items()
        if state not in ("FWD", "BLK", "DIS", "LIS", "LRN")
    ]
    stp_lines = []
    if all_errdis:
        stp_color = RED
        stp_lines.append(f"Err-disabled ports: {len(all_errdis)}")
        for p in all_errdis:
            stp_lines.append(f"  ERR-DISABLED: {p}")
    elif unexpected:
        stp_color = YELLOW
        stp_lines.append("Unexpected STP port states:")
        for u in unexpected:
            stp_lines.append(f"  {u}")
    else:
        stp_color = GREEN
        fwd_count = sum(1 for s, _ in port_states.values() if s == "FWD")
        blk_count = sum(1 for s, _ in port_states.values() if s == "BLK")
        stp_lines.append("Spanning tree: normal")
        stp_lines.append(f"  Forwarding: {fwd_count}  Blocking: {blk_count}")

    edge_ports     = [p for p, (s, t) in port_states.items() if "Edge"     in t]
    boundary_ports = [p for p, (s, t) in port_states.items() if "Boundary" in t]
    if edge_ports or boundary_ports:
        stp_lines.append("")
        if edge_ports:
            stp_lines.append(
                f"Portfast (Edge) ports ({len(edge_ports)}): {', '.join(sorted(edge_ports))}")
        if boundary_ports:
            stp_lines.append(
                f"Boundary ports (STP BPDUs detected) ({len(boundary_ports)}): "
                f"{', '.join(sorted(boundary_ports))}")

    stp_body = "\n".join(stp_lines) + "\n"
    if stp_events:
        stp_body += "\nRecent STP events (from syslog):\n"
        for e in stp_events:
            stp_body += f"  {e}\n"
    elif priv_level < 15:
        stp_body += f"\nSTP event log: not available (privilege {priv_level} — needs 15)\n"

    color = worst_color(bw_color, iface_color, stp_color)
    body  = (f"=== Bandwidth ===\n{bw_body}"
             f"=== Interfaces ===\n{iface_body}"
             f"=== Spanning Tree ===\n{stp_body}")
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
    if not priv_text:
        reason = f"SSH connection failed — no response from {sw_host}"
        print(f"  {reason}")
        purple_all(xymon_host, xymon_port, fqdn, reason)
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
    iface_meta, iface_errdis = parse_interfaces_status(raw["iface_status"])
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

    c, b = col_hardware(env_issues, max_temp, psu_ok, fan_ok, psu_watt)
    xymon_send_status(xymon_host, xymon_port, fqdn, "hardware", c, b)

    c, b = col_net(uplink_ports, iface_data, iface_meta, flap_deltas, link_events,
                   port_states, stp_errdis, iface_errdis, stp_events,
                   priv_level, in_95, out_95, n_samp, cfg, section)
    xymon_send_status(xymon_host, xymon_port, fqdn, "net", c, b)

    # --- Direct RRD updates (bypass xymond_rrd write cache) ---
    if cpu_t:
        _rrd_update_cpu_la(fqdn, cpu_t[3])  # used_pct

    if uplink_ports:
        _rrd_update_net(fqdn, total_in_bps, total_out_bps)

    graphed = cget(cfg, section, "GRAPHED_PORTS", "").split()
    for port in graphed:
        d = iface_data.get(port)
        if d:
            # Arista in_bps is bits/sec; ifstat RRD uses bytes/sec
            _rrd_update_ifstat(fqdn, port, d["in_bps"] // 8, d["out_bps"] // 8)

    if mem_t:
        _rrd_update_memory(fqdn, real_pct=mem_t[0], swap_pct=0.0)


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
