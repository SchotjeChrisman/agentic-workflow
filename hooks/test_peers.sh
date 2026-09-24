#!/usr/bin/env bash
# Self-check for peers.sh: fake registry with self, live peers in and out of scope, and a dead peer.
set -e
dir=$(mktemp -d); trap 'rm -rf "$dir"' EXIT
mkdir -p "$dir/reg" "$dir/repo/sub" "$dir/other"
git init -q "$dir/repo"
sleep 60 & live=$!
entry() { echo "{\"sessionId\":\"$1\",\"pid\":$2,\"name\":\"$1\",\"cwd\":\"$3\",\"status\":\"idle\"}" >"$dir/reg/$1.json"; }
entry me $$ "$dir/repo"
entry samedir $live "$dir/repo"
entry subdir $live "$dir/repo/sub"
entry elsewhere $live "$dir/other"
entry dead 999999999 "$dir/repo"
echo '{"sessionId":' >"$dir/reg/0-half-written.json"
run() { echo "{\"session_id\":\"me\",\"cwd\":\"$1\"}" | CLAUDE_SESSIONS_DIR=$2 bash "$(dirname "$0")/peers.sh"; }
out=$(run "$dir/repo" "$dir/reg")
for want in samedir subdir; do grep -q "$want (idle)" <<<"$out" || { echo "FAIL: $want missing"; exit 1; }; done
for bad in "me (" elsewhere dead; do ! grep -q "$bad" <<<"$out" || { echo "FAIL: listed $bad"; exit 1; }; done
out=$(run "$dir/other" "$dir/reg")
grep -q 'elsewhere' <<<"$out" && ! grep -q samedir <<<"$out" || { echo "FAIL: non-repo dir should match exact cwd only"; exit 1; }
[ -z "$(run "$dir/repo" "$dir/none")" ] || { echo "FAIL: output with no peers"; exit 1; }
kill $live
echo PASS
