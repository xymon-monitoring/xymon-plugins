#!/usr/bin/env python3
# interface - Xymon client extension: network interface health check.
#
# Reports an "interface" status column summarising, for each physical NIC,
# its link state, negotiated speed/duplex, IPv4 assignment and (for bond
# members) MII status, using `ethtool` and sysfs.
#
# This is an original, clean-room reimplementation written for the
# xymon-monitoring/xymon-plugins collection. It reproduces the observable
# behaviour of the earlier "iface" check (interface column, --debug/--speed
# options, per-interface colour logic) but shares no code with it.
#
# Copyright (C) 2026 xymon-monitoring contributors
# SPDX-License-Identifier: GPL-2.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 2 of the License, or (at your option)
# any later version. See <https://www.gnu.org/licenses/> for details.

import argparse
import os
import re
import subprocess
import sys
import time

# Interfaces never reported on. Extend at runtime with --skip.
DEFAULT_SKIP = ["lo", "docker0", "virbr0"]

# Xymon colours, ordered from least to most severe so the overall status can
# be reduced to the worst interface seen.
SEVERITY = {"clear": 0, "green": 1, "yellow": 2, "red": 3}


def worst(a, b):
    return a if SEVERITY[a] >= SEVERITY[b] else b


def run(cmd):
    """Run a command, returning (stdout, ok). Never raises."""
    try:
        out = subprocess.run(
            cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            universal_newlines=True,
        )
        return out.stdout, out.returncode == 0
    except OSError:
        return "", False


def is_bond_master(name):
    return os.path.isfile("/proc/net/bonding/%s" % name)


def physical_interfaces():
    """List candidate interfaces from sysfs, skipping pure-virtual devices."""
    try:
        names = sorted(os.listdir("/sys/class/net"))
    except OSError:
        return []
    result = []
    for name in names:
        # A real NIC has a backing device directory; bond masters are virtual
        # but we still want to report their aggregate health.
        if os.path.islink(os.path.join("/sys/class/net", name, "device")):
            result.append(name)
        elif is_bond_master(name):
            result.append(name)
    return result


def bond_slave_of(name):
    """Return the bond master name if `name` is a bond member, else None."""
    link = os.path.join("/sys/class/net", name, "master")
    if os.path.islink(link):
        return os.path.basename(os.readlink(link))
    return None


def parse_ethtool(name):
    """Return negotiated speed/duplex/link plus the best supported speed."""
    text, ok = run(["sudo", "ethtool", name])
    info = {"link": None, "speed": None, "duplex": None, "supported_max": None}
    if not ok:
        return info

    supported = []
    in_modes = False
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("Supported link modes:"):
            in_modes = True
            stripped = stripped[len("Supported link modes:"):].strip()
        elif line[:1] not in (" ", "\t"):
            in_modes = False

        if in_modes:
            for token in stripped.split():
                m = re.match(r"(\d+)base", token)
                if m:
                    supported.append(int(m.group(1)))

        m = re.match(r"Speed:\s*(\d+)Mb/s", stripped)
        if m:
            info["speed"] = int(m.group(1))
        m = re.match(r"Duplex:\s*(\S+)", stripped)
        if m:
            info["duplex"] = m.group(1)
        m = re.match(r"Link detected:\s*(\w+)", stripped)
        if m:
            info["link"] = (m.group(1).lower() == "yes")

    if supported:
        info["supported_max"] = max(supported)
    return info


def ipv4_address(name):
    """Return the first IPv4 address of `name`, or None."""
    text, ok = run(["ip", "-o", "-4", "addr", "show", "dev", name])
    if not ok:
        return None
    m = re.search(r"inet\s+(\d+\.\d+\.\d+\.\d+)", text)
    return m.group(1) if m else None


def bond_mii_ok(name):
    """True if a bond master reports MII Status: up, None if unreadable."""
    try:
        with open("/proc/net/bonding/%s" % name) as fh:
            head = fh.read(4096)
    except OSError:
        return None
    m = re.search(r"MII Status:\s*(\w+)", head)
    if not m:
        return None
    return m.group(1).lower() == "up"


def check_interface(name, expected_speed):
    """Return (colour, report_text) for a single interface.

    expected_speed is an int (Mbps) forced via --speed, or None to compare
    against the interface's own fastest supported mode.
    """
    lines = ["%s:" % name]

    # A bond master's health is its aggregate MII status.
    if is_bond_master(name):
        mii = bond_mii_ok(name)
        ip = ipv4_address(name)
        colour = "green" if mii else "red"
        lines.append("    %sbond MII status: %s"
                     % ("" if mii else "&red ", "up" if mii else "down"))
        if ip:
            lines.append("    address: %s" % ip)
        return colour, "\n".join(lines)

    eth = parse_ethtool(name)
    link = eth["link"]
    speed = eth["speed"]
    ip = ipv4_address(name)
    master = bond_slave_of(name)

    if link is None:
        lines.append("    no ethtool data")
        return "clear", "\n".join(lines)

    if not link:
        if ip:
            lines.append("    &red link down but address %s configured" % ip)
            return "red", "\n".join(lines)
        lines.append("    link down, unused")
        return "clear", "\n".join(lines)

    # Link is up from here on.
    lines.append("    link up, %s duplex, %s Mb/s"
                 % (eth["duplex"] or "?", speed if speed else "?"))

    colour = "green"
    if ip:
        lines.append("    address: %s" % ip)
    elif master:
        lines.append("    member of bond %s (no address expected)" % master)
    else:
        lines.append("    &yellow link up but no IPv4 address")
        colour = worst(colour, "yellow")

    target = expected_speed if expected_speed else eth["supported_max"]
    if target and speed and speed < target:
        if expected_speed:
            lines.append("    &red speed %d Mb/s below required %d Mb/s"
                         % (speed, target))
            colour = worst(colour, "red")
        else:
            lines.append("    &yellow speed %d Mb/s below supported %d Mb/s"
                         % (speed, target))
            colour = worst(colour, "yellow")

    return colour, "\n".join(lines)


def send_to_xymon(colour, body, debug):
    try:
        xymon = os.environ["XYMON"]
        servers = os.environ["XYMONSERVERS"]
        machine = os.environ["MACHINE"]
    except KeyError:
        sys.stderr.write(
            "ERROR: XYMON, XYMONSERVERS and MACHINE must be set in the "
            "Xymon client environment\n")
        return 1

    stamp = time.strftime("%a %b %d %H:%M:%S %Y")
    message = "status %s.interface %s %s\n%s\n" % (machine, colour, stamp, body)
    if debug:
        print(message)
    subprocess.run([xymon, servers, message])
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Report network interface link, speed and duplex to Xymon.")
    parser.add_argument("--debug", action="store_true",
                        help="print the status message to stdout as well")
    parser.add_argument("--speed", metavar="MBPS", type=int,
                        help="expected link speed for every interface, in Mbps "
                             "(use when the NIC is faster than the switch)")
    parser.add_argument("--skip", metavar="IFACE", action="append", default=[],
                        help="interface to ignore; may be repeated")
    args = parser.parse_args(argv)

    skip = set(DEFAULT_SKIP) | set(args.skip)

    overall = "clear"
    sections = []
    for name in physical_interfaces():
        if name in skip:
            continue
        colour, report = check_interface(name, args.speed)
        overall = worst(overall, colour)
        sections.append(report)

    body = "\n\n".join(sections) if sections else "No interfaces to report."
    return send_to_xymon(overall, body, args.debug)


if __name__ == "__main__":
    sys.exit(main())
