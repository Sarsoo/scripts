#!/usr/bin/env bash
# Regression tests for lib/so-rec.sh.
#
# Each case runs the recorder inside a throwaway `bash -c` child, because
# sourcing it installs a DEBUG trap and redirects the calling shell's stdout.
# The file name deliberately does not start with `so-`, so the dispatcher never
# discovers it as a command.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

# run_rec BODY: sources the recorder in a bash child; $1 is the repo root and
# $2 the log path. Sets OUTPUT (stdout+stderr) and RC.
run_rec() {
    OUTPUT="$(bash -c "$1" _ "$REPO_ROOT" "${2:-}" 2>&1)"
    RC=$?
}

assert_contains() {
    local desc="$1" needle="$2"
    if [[ "$OUTPUT" == *"$needle"* ]]; then
        pass=$((pass + 1))
        printf 'ok   - %s\n' "$desc"
    else
        fail=$((fail + 1))
        printf 'FAIL - %s\n       missing: %q\n       actual:  %q\n' "$desc" "$needle" "$OUTPUT"
    fi
}

assert_rc() {
    local desc="$1" expected="$2"
    if [[ "$RC" -eq "$expected" ]]; then
        pass=$((pass + 1))
        printf 'ok   - %s\n' "$desc"
    else
        fail=$((fail + 1))
        printf 'FAIL - %s\n       expected rc: %s\n       actual rc:   %s\n' "$desc" "$expected" "$RC"
    fi
}

assert_log() {
    local desc="$1" file="$2" needle="$3"
    if grep -qF -- "$needle" "$file"; then
        pass=$((pass + 1))
        printf 'ok   - %s\n' "$desc"
    else
        fail=$((fail + 1))
        printf 'FAIL - %s\n       %s missing %q\n' "$desc" "$file" "$needle"
    fi
}

assert_log_absent() {
    local desc="$1" file="$2" needle="$3"
    if grep -qF -- "$needle" "$file"; then
        fail=$((fail + 1))
        printf 'FAIL - %s\n       %s unexpectedly contains %q\n' "$desc" "$file" "$needle"
    else
        pass=$((pass + 1))
        printf 'ok   - %s\n' "$desc"
    fi
}

# 1. Commands and their output are recorded.
log="$TMP/basic.log"
run_rec 'source "$1/lib/so-rec.sh"; rec start "$2"; echo hello; printf "x=[%s]\n" ok; rec stop' "$log"
assert_rc "start/stop exits 0" 0
assert_contains "stop reports the log path" "rec: wrote $log"
assert_log "banner is recorded" "$log" '=== rec started'
assert_log "command line is recorded with timestamp" "$log" '$ echo hello'
assert_log "stdout is recorded" "$log" 'hello'
assert_log "output is recorded" "$log" 'x=[ok]'

# 2. Markers never leak into command substitution or pipelines.
log="$TMP/subst.log"
run_rec 'source "$1/lib/so-rec.sh"; rec start "$2"
v=$(printf abc); printf "v=[%s]\n" "$v"
printf "one\ntwo\n" | grep two; rec stop' "$log"
assert_log "command substitution stays clean" "$log" 'v=[abc]'
assert_log_absent "no marker inside captured output" "$log" 'v=[1'
assert_log "pipeline output is recorded" "$log" 'two'

# 3. Default mode does not trace inside functions.
log="$TMP/plain.log"
run_rec 'source "$1/lib/so-rec.sh"; f() { echo in-f; }; rec start "$2"; f; rec stop' "$log"
assert_log "function output is recorded" "$log" 'in-f'
assert_log "function call is recorded once" "$log" '$ f'
assert_log_absent "function internals are not recorded" "$log" '$   echo in-f'

# 4. Trace mode records function internals, indented.
log="$TMP/trace.log"
run_rec 'source "$1/lib/so-rec.sh"; f() { echo in-f; }; rec start -t "$2"; f; rec stop' "$log"
assert_log "trace banner is marked" "$log" '=== rec started'
assert_log "trace records function internals indented" "$log" '$   echo in-f'
assert_log_absent "trace does not duplicate the function call" "$log" '$   f'

# 5. Trace mode tags command substitution.
log="$TMP/trace-sub.log"
run_rec 'source "$1/lib/so-rec.sh"; rec start -t "$2"; x=$(echo sub); rec stop' "$log"
assert_log "trace tags subshell commands" "$log" '$ echo sub   # (subshell)'

# 6. State handling.
run_rec 'source "$1/lib/so-rec.sh"; rec status'
assert_contains "status before start reports idle" 'rec: not recording'
run_rec 'source "$1/lib/so-rec.sh"; rec stop'
assert_rc "stop when idle fails" 1
assert_contains "stop when idle reports idle" 'rec: not recording'

# 7. The file refuses to run as a script.
OUTPUT="$(bash "$REPO_ROOT/lib/so-rec.sh" 2>&1)"
RC=$?
assert_rc "executing the library fails" 2
assert_contains "executing the library says to source it" 'source this file'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
