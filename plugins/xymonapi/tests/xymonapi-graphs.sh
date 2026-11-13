#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# plugins/xymonapi/tests/xymonapi-graphs.sh
#
# /graphs gives the PNG showgraph.cgi draws. On the Xymon server it runs
# that program itself, $XYMONHOME/bin/showgraph.cgi or the one
# XYMONAPI_SHOWGRAPH names, as a CGI, and needs no web server. Where the
# program is not there, or the setting is empty, it fetches the graph
# through the wrapper showgraph.sh at XYMONSERVERCGIURL. xymonserver.cfg ships that as a path,
# /xymon-cgi, which the web pages use relative to themselves; the API then
# needs XYMONWEBHOST for the host, as Xymon's own pages do. An absolute
# XYMONSERVERCGIURL needs no XYMONWEBHOST; a path without one is a 502 that
# names the missing setting, not a stack trace.
#
# What comes back must be a PNG: showgraph.cgi answers an error as HTML with
# status 200, and that is a 502, not an image. And a graph that takes long
# holds up its own request alone: /health answers meanwhile.
#
# The web server is tests/lib/fake-showgraph.py, which records the request
# and answers a PNG. Skips where the API cannot run (tests/lib/xymonapi.sh).
# Needs the xymon client of the Xymon tree in XYMON_SRC (for a free port)
# and curl.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../../../tests/lib/xymonapi.sh"

ROOT=$(find_root)

require_bin XYMONCLIENT "$XYMON_SRC/common/xymon"
command -v curl >/dev/null 2>&1 || skip "curl is not installed"

work=$(mktempdir)
WEB_PID=""
register_cleanup 'stop_process "$WEB_PID" "$API_PID"'

"${XYMONAPI_PYTHON:-python3}" "$ROOT/tests/lib/fake-showgraph.py" "$work/web.port" "$work/web.req" &
# shellcheck disable=SC2034 # read by the cleanup
WEB_PID=$!
for _ in $(seq 1 50); do [ -s "$work/web.port" ] && break; sleep 0.1; done
[ -s "$work/web.port" ] || fail "the stand-in web server did not start"
WEB="http://127.0.0.1:$(cat "$work/web.port")"

# graph QUERY -- fetch /graphs?QUERY into $work/graph, print the status code.
graph() {
	curl -s --max-time 30 -o "$work/graph" -w '%{http_code}' \
		"http://127.0.0.1:$API_PORT/xymon/api/v1/graphs?$1"
}

# The launcher refuses to start without XYMSRV; /graphs needs no xymond.
export XYMON="$XYMONCLIENT" XYMSRV="127.0.0.1:1"

# 1. As xymonserver.cfg ships it: a path, and XYMONWEBHOST for the host.
export XYMONSERVERCGIURL="/xymon-cgi" XYMONWEBHOST="$WEB"
start_api
assert_equal "200" "$(graph 'entity=web.example.com&test=conn&from=1699999800&to=1700000700')" "/graphs with a path and XYMONWEBHOST"
assert_equal "89504e470d0a1a0a" "$(od -An -tx1 -N8 "$work/graph" | tr -d ' \n')" "and the answer is the PNG showgraph sent"
req=$(cat "$work/web.req")
assert_match '^/xymon-cgi/showgraph\.sh\?' "$req" "showgraph.sh is asked under XYMONSERVERCGIURL"
assert_contains 'host=web.example.com' "$req" "for the host"
assert_contains 'service=conn' "$req" "and the test"
assert_contains 'graph_start=1699999800' "$req" "from the time asked"
assert_contains 'graph_end=1700000700' "$req" "to the time asked"
assert_contains 'action=view' "$req" "as a view"

assert_equal "200" "$(graph 'entity=web.example.com&test=tcp.http.web.example.com%3A8080%2C')" "/graphs of an HTTP test, whose name holds a colon"
assert_contains 'service=tcp.http.web.example.com%3A8080%2C' "$(cat "$work/web.req")" "which reaches showgraph.sh encoded"

assert_equal "502" "$(graph 'entity=html.example.com&test=conn')" "an HTML page from showgraph"
assert_contains 'did not answer with a PNG' "$(cat "$work/graph")" "is refused, and the answer says why"

# A graph that takes five seconds, and /health asked one second into it.
graph 'entity=slow.example.com&test=conn' > "$work/slow.code" &
SLOW_PID=$!
sleep 1
began=$(date +%s)
assert_contains '"alive"' "$(api_get /health)" "/health answers while a graph is being drawn"
took=$(( $(date +%s) - began ))
[ "$took" -lt 3 ] || fail "/health took $took seconds while a graph was being drawn: the handlers block each other"
wait "$SLOW_PID"
assert_equal "200" "$(cat "$work/slow.code")" "and the slow graph itself still arrives"
stop_process "$API_PID"; API_PID=""

# 2. An absolute XYMONSERVERCGIURL stands alone.
export XYMONSERVERCGIURL="$WEB/xymon-cgi"
unset XYMONWEBHOST
start_api
assert_equal "200" "$(graph 'entity=web.example.com&test=conn')" "/graphs with an absolute XYMONSERVERCGIURL and no XYMONWEBHOST"
assert_match '^/xymon-cgi/showgraph\.sh\?' "$(cat "$work/web.req")" "asks the same showgraph.sh"
stop_process "$API_PID"; API_PID=""

# 3. A path with nothing to put in front of it is refused, and says what is missing.
export XYMONSERVERCGIURL="/xymon-cgi"
start_api
assert_equal "502" "$(graph 'entity=web.example.com&test=conn')" "/graphs with a path and no XYMONWEBHOST"
assert_contains 'XYMONWEBHOST' "$(cat "$work/graph")" "and the answer names the missing setting"

stop_process "$API_PID"; API_PID=""

# 4. On the Xymon server the API runs showgraph.cgi itself, as the web
# server would, and asks no web server: $XYMONHOME/bin/showgraph.cgi when it
# is there. The stand-in records the request it was given as a CGI and
# answers the PNG signature after its headers; for host=html.* an error
# page, as showgraph does.
mkdir -p "$work/home/bin"
cat > "$work/home/bin/showgraph.cgi" <<CGI
#!/bin/sh
printf '%s %s %s\\n' "\$REQUEST_METHOD" "\$SCRIPT_NAME" "\$QUERY_STRING" > "$work/cgi.req"
case "\$QUERY_STRING" in
*host=html.*) printf 'Content-type: text/html\\n\\n<html>no such graph</html>\\n' ;;
*) printf 'Content-type: image/png\\nExpires: 0\\n\\n\\211PNG\\r\\n\\032\\n' ;;
esac
CGI
chmod 755 "$work/home/bin/showgraph.cgi"
export XYMONHOME="$work/home" XYMONWEBHOST="$WEB"
: > "$work/web.req"
start_api
assert_equal "200" "$(graph 'entity=web.example.com&test=conn&from=1699999800&to=1700000700')" "/graphs with a showgraph.cgi in XYMONHOME/bin"
assert_equal "89504e470d0a1a0a" "$(od -An -tx1 -N8 "$work/graph" | tr -d ' \n')" "and the answer is the PNG it wrote, without its CGI headers"
req=$(cat "$work/cgi.req")
assert_match '^GET /xymon-cgi/showgraph\.sh ' "$req" "it is run as a GET of showgraph.sh under XYMONSERVERCGIURL"
assert_contains 'host=web.example.com' "$req" "for the host"
assert_contains 'service=conn' "$req" "and the test"
assert_contains 'graph_start=1699999800' "$req" "from the time asked"
assert_contains 'graph_end=1700000700' "$req" "to the time asked"
assert_equal "" "$(cat "$work/web.req")" "and the web server is not asked"
assert_equal "502" "$(graph 'entity=html.example.com&test=conn')" "an HTML page from showgraph.cgi"
assert_contains 'showgraph.cgi did not answer with a PNG' "$(cat "$work/graph")" "is refused, and the answer says why"
stop_process "$API_PID"; API_PID=""

# 5. XYMONAPI_SHOWGRAPH names another program; set empty, the graph is
# fetched from the web server as before, with the program still there.
mv "$work/home/bin/showgraph.cgi" "$work/other.cgi"
rm -f "$work/cgi.req"
XYMONAPI_SHOWGRAPH="$work/other.cgi" start_api
assert_equal "200" "$(graph 'entity=web.example.com&test=conn')" "/graphs with the program XYMONAPI_SHOWGRAPH names"
assert_contains 'host=web.example.com' "$(cat "$work/cgi.req")" "which is the one that was run"
stop_process "$API_PID"; API_PID=""
mv "$work/other.cgi" "$work/home/bin/showgraph.cgi"
rm -f "$work/cgi.req"
XYMONAPI_SHOWGRAPH="" start_api
assert_equal "200" "$(graph 'entity=web.example.com&test=conn')" "/graphs with XYMONAPI_SHOWGRAPH set empty"
assert_match '^/xymon-cgi/showgraph\.sh\?' "$(cat "$work/web.req")" "asks the web server"
[ -e "$work/cgi.req" ] && fail "XYMONAPI_SHOWGRAPH set empty, and showgraph.cgi was run"

pass "/graphs runs showgraph.cgi where it is, else reaches showgraph.sh through XYMONWEBHOST; it serves only a PNG, and a slow graph does not hold up /health"
