#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# plugins/xymonapi/tests/xymonapi-pages.sh
#
# /pages gives the layout hosts.cfg describes and xymond does not keep: the
# pages with their subpages inside them, the groups of each with their hosts
# in the file's order, and what the file says of a host. Read from a running
# xymond with its own "config hosts.cfg", so an included file is part of it.
# One hosts.cfg with one of each thing the answer distinguishes:
#
#   - hosts before any page are on the top page, and hosts a page lists
#     before any group are a group with no title;
#   - page, subpage and subparent, the last under the page it names, each
#     with its path from the top; a page with no title has none;
#   - group-only and group-except give their columns, and a title line is
#     the pretitle of what follows it;
#   - NAME, COMMENT and DESCR, quoted or not, are the host's name, comment
#     and description, and a title line above a host its pretitle; a host
#     with nodisp is in no group; the .default. line is no host;
#   - as xymongen does, a subpage before any page and a subparent whose
#     parent page has not come yet are left out, and the hosts after them
#     stay in the group they were in.
#
# Without a xymond to ask, /pages is the upstream error and not an empty
# layout.
#
# Skips where the API cannot run (tests/lib/xymonapi.sh). Needs a built Xymon
# server tree in XYMON_SRC, and curl.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../../../tests/lib/xymonapi.sh"

ROOT=$(find_root)

require_bin XYMOND "$XYMON_SRC/xymond/xymond"
require_bin XYMONCLIENT "$XYMON_SRC/common/xymon"
command -v curl >/dev/null 2>&1 || skip "curl is not installed"

work=$(mktempdir)

# shellcheck disable=SC2034 # read by xymond-daemon.sh and the cleanup
XYMOND_PID=""
register_cleanup 'stop_process "$API_PID" "$XYMOND_PID"'

mkdir -p "$work/home/etc" "$work/home/tmp" "$work/home/www"
# xymond's "config" gives a file of $XYMONHOME/etc, so the hosts.cfg it
# loads is put there.
cat > "$work/home/etc/hosts.cfg" <<EOF
0.0.0.0		.default.	# CLIENT:noconn
10.0.0.1	top1.example.com	# noconn COMMENT:"On the top page"
subpage early Early

title Production
page servers Servers
group-compress Web servers
10.0.0.11	web1.example.com	# noconn NAME:"web one" DESCR:frontend
group-only cpu|disk Databases
title Primary
10.0.0.21	db1.example.com		# noconn
group-except info|trends Rest
10.0.0.22	db2.example.com		# noconn

subpage linux Linux boxes
10.0.0.31	app1.example.com	# noconn
group Apps
10.0.0.32	app2.example.com	# noconn
10.0.0.33	hidden.example.com	# noconn nodisp

page network
title Core
group Routers
10.0.1.1	rtr1.example.com	# noconn

subparent servers bsd BSD
10.0.0.41	bsd1.example.com	# noconn
subparent nosuch orphan Orphan
10.0.0.42	orphan1.example.com	# noconn

include $work/home/etc/extra.cfg
EOF
printf 'page extra Extra\n10.0.9.1 extra1.example.com # noconn\n' > "$work/home/etc/extra.cfg"

require_cfg XYMONSERVER_CFG "$XYMON_SRC/xymond/etcfiles/xymonserver.cfg"
sed -e 's|^XYMONHOME=.*|XYMONHOME="'"$work"'/home"|' \
    -e 's|^XYMONTMP=.*|XYMONTMP="'"$work"'/home/tmp"|' \
	"$XYMONSERVER_CFG" > "$work/xymonserver.cfg"

xymond_launch() {
	local port=$1; shift
	"$XYMOND" --no-daemon --listen="127.0.0.1:$port" \
		--hosts="$work/home/etc/hosts.cfg" --env="$work/xymonserver.cfg" \
		--pidfile="$work/xymond.pid" --checkpoint-file="$work/chk.out" \
		"$@" \
		> "$work/xymond.log" 2>&1 &
	# shellcheck disable=SC2034 # read by xymond-daemon.sh and the cleanup
	XYMOND_PID=$!
}

start_xymond

export XYMON="$XYMONCLIENT" XYMSRV="127.0.0.1:$PORT"
start_api

pages=$(api_get /pages)

# The top page, and what is on it.
assert_contains '"root":{"name":"","title":null,"path":"","groups":[{"title":null,"hosts":["top1.example.com"]}]' "$pages" \
	"hosts before any page are on the top page, in a group with no title"
assert_not_contains '.default.' "$pages" "the .default. line is no host"

# Pages, with their paths from the top.
assert_contains '"name":"servers","title":"Servers","path":"servers"' "$pages" "a page, with its title"
assert_contains '"name":"linux","title":"Linux boxes","path":"servers/linux"' "$pages" "a subpage, under the page before it"
assert_contains '"name":"bsd","title":"BSD","path":"servers/bsd"' "$pages" "a subparent, under the page it names and not the one before it"
assert_contains '"name":"network","title":null,"path":"network"' "$pages" "a page with no title has none"
assert_contains '"name":"extra","title":"Extra","path":"extra"' "$pages" "a page of an included file"
assert_contains '"hosts":["extra1.example.com"]' "$pages" "with its host"

# Groups, with their hosts and columns.
assert_contains '{"title":"Web servers","hosts":["web1.example.com"]}' "$pages" "a group, with its title and hosts"
assert_contains '{"title":"Databases","hosts":["db1.example.com"],"only":["cpu","disk"]}' "$pages" "group-only gives its columns, in its order"
assert_contains '{"title":"Rest","hosts":["db2.example.com"],"except":["info","trends"]}' "$pages" "group-except gives the columns left out"
assert_contains '{"title":null,"hosts":["app1.example.com"]},{"title":"Apps","hosts":["app2.example.com"]}' "$pages" \
	"hosts a page lists before any group are a group with no title; a host with nodisp is in no group"
assert_contains '{"title":"Routers","hosts":["rtr1.example.com"],"pretitle":"Core"}' "$pages" "a title line is the pretitle of the group after it"
assert_contains '"pretitle":"Production"' "$pages" "and of the page after it"

# What hosts.cfg says of a host.
assert_contains '"web1.example.com":{"name":"web one","description":"frontend"}' "$pages" "NAME, quoted, and DESCR"
assert_contains '"top1.example.com":{"comment":"On the top page"}' "$pages" "COMMENT"
assert_contains '"db2.example.com":{}' "$pages" "a host hosts.cfg says nothing of"
assert_contains '"db1.example.com":{"pretitle":"Primary"}' "$pages" "a title line above a host is that host's pretitle"

# What xymongen leaves out.
assert_not_contains '"name":"early"' "$pages" "a subpage before any page is left out"
assert_not_contains '"name":"orphan"' "$pages" "a subparent whose parent page has not come is left out"
assert_contains '"hosts":["bsd1.example.com","orphan1.example.com"]' "$pages" "and the host after it stays in the group it was in"

# Without xymond there is no layout to give: an error, not an empty one.
stop_process "$XYMOND_PID"
XYMOND_PID=""
assert_equal "502" "$(api_code /pages)" "/pages with no xymond to ask"
assert_contains '"error":"upstream"' "$(api_get /pages)" "is the upstream error"

pass "/pages gives hosts.cfg's pages, subpages and groups with their hosts and columns, an included file's too, and each host's name, comment and description"
