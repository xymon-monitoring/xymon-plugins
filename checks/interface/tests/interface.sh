#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# checks/interface/tests/interface.sh
#
# interface.py gives each network interface the colour its state calls for,
# and reports the worst to Xymon as the interface column:
#   - link up, an IPv4 address, at its fastest supported speed: green;
#   - below its fastest supported speed: yellow; below the speed --speed asks
#     for: red;
#   - link up with no address: yellow, unless it is a bond member, which needs
#     none;
#   - link down with an address configured: red; down and unused: clear;
#   - a bond master: green when its MII status is up, red when down;
#   - lo, docker0 and virbr0 are skipped, and any interface --skip names.
#
# Run against a sysfs and procfs tree of its own (SYS_NET and PROC_BONDING
# pointed at it) and stand-ins for sudo, ethtool, ip and the xymon command at
# the head of PATH: no network interface of the machine is read.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../../../tests/lib/xymonapi.sh"

ROOT=$(find_root)
PY=${XYMONAPI_PYTHON:-python3}
command -v "$PY" >/dev/null 2>&1 || skip "no Python 3 ($PY)"
work=$(mktempdir)
sys=$work/sys; proc=$work/proc; fx=$work/fixtures; bin=$work/bin
mkdir -p "$sys" "$proc" "$fx" "$bin" "$work/devices/nic"

# One fake NIC per case: a device link makes it physical.
for n in eth0 eth1 eth2 eth3 eth4 eth5 lo; do
	mkdir -p "$sys/$n"
	ln -s "$work/devices/nic" "$sys/$n/device"
done
# bond0 is a master, with no device link; eth5 is its member.
mkdir -p "$sys/bond0"
ln -s "$sys/bond0" "$sys/eth5/master"
printf 'Bonding Mode: active-backup\nMII Status: up\n' > "$proc/bond0"

ethtool() { # NAME LINK SPEED SUPPORTED_MAX
	printf 'Settings for %s:\n\tSupported link modes:   10baseT/Full\n\t                        %sbaseT/Full\n\tSpeed: %sMb/s\n\tDuplex: Full\n\tLink detected: %s\n' \
		"$1" "$4" "$3" "$2" > "$fx/ethtool.$1"
}
ethtool eth0 yes 1000 1000
ethtool eth1 yes 100 1000
ethtool eth2 yes 1000 1000
ethtool eth3 no 1000 1000
ethtool eth4 no 1000 1000
ethtool eth5 yes 1000 1000
for n in eth0 eth1 eth3 bond0; do
	printf '2: %s    inet 192.0.2.%d/24 brd 192.0.2.255 scope global %s\n' "$n" "${#n}" "$n" > "$fx/ip.$n"
done

cat > "$bin/sudo" <<'EOF'
#!/bin/sh
exec "$@"
EOF
cat > "$bin/ethtool" <<EOF
#!/bin/sh
[ -f "$fx/ethtool.\$1" ] || exit 1
cat "$fx/ethtool.\$1"
EOF
cat > "$bin/ip" <<EOF
#!/bin/sh
# ip -o -4 addr show dev NAME
for a; do last=\$a; done
[ -f "$fx/ip.\$last" ] && cat "$fx/ip.\$last"
exit 0
EOF
cat > "$bin/xymon" <<EOF
#!/bin/sh
printf '%s\n' "\$2" > "$work/sent"
EOF
chmod 755 "$bin"/*

# check NAME [SPEED] -- the colour interface.py gives NAME.
check() {
	PATH="$bin:$PATH" "$PY" - "$ROOT/checks/interface/interface.py" "$sys" "$proc" "$@" <<'EOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("interface", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
m.SYS_NET, m.PROC_BONDING = sys.argv[2], sys.argv[3]
speed = int(sys.argv[5]) if len(sys.argv) > 5 else None
print(m.check_interface(sys.argv[4], speed)[0])
EOF
}

assert_equal green  "$(check eth0)"      "eth0, up at its fastest speed with an address"
assert_equal yellow "$(check eth1)"      "eth1, below its fastest supported speed"
assert_equal red    "$(check eth1 1000)" "eth1, below the speed --speed asks for"
assert_equal green  "$(check eth0 1000)" "eth0, at the speed --speed asks for"
assert_equal yellow "$(check eth2)"      "eth2, up with no address"
assert_equal red    "$(check eth3)"      "eth3, down with an address configured"
assert_equal clear  "$(check eth4)"      "eth4, down and unused"
assert_equal green  "$(check eth5)"      "eth5, a bond member with no address"
assert_equal green  "$(check bond0)"     "bond0, MII status up"
printf 'Bonding Mode: active-backup\nMII Status: down\n' > "$proc/bond0"
assert_equal red    "$(check bond0)"     "bond0, MII status down"
printf 'Bonding Mode: active-backup\nMII Status: up\n' > "$proc/bond0"

# The whole run: the worst colour, sent as the interface column; lo skipped
# by default, eth3 by --skip.
PATH="$bin:$PATH" XYMON="$bin/xymon" XYMONSERVERS=192.0.2.1 MACHINE=host.example \
	"$PY" - "$ROOT/checks/interface/interface.py" "$sys" "$proc" <<'EOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("interface", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
m.SYS_NET, m.PROC_BONDING = sys.argv[2], sys.argv[3]
sys.exit(m.main(["--skip", "eth3"]))
EOF
sent=$(cat "$work/sent")
assert_contains "status host.example.interface yellow" "$(first_line "$sent")" "the worst colour once eth3 is skipped is yellow"
assert_not_contains "lo:" "$sent" "lo is skipped by default"
assert_not_contains "eth3:" "$sent" "eth3 is skipped by --skip"
assert_contains "eth5:" "$sent" "a bond member is reported"

pass "interface.py colours each interface by link, speed, address and bond state, skips lo and what --skip names, and sends the worst as the interface column"
