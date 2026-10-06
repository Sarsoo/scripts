#!/usr/bin/env bash
# Dispatcher regression tests for the `so` porcelain.
#
# The suite builds an isolated command root in a temp directory, copies the
# real dispatcher into it, and exercises resolution against fake leaves. The
# file name deliberately does not start with `so-` so it is never discovered
# as a command by the dispatcher.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cp "$REPO_ROOT/so" "$TMP/so"
chmod +x "$TMP/so"

# make_leaf NAME TAG writes a public fixture command that prints "TAG:$*".
make_leaf() {
    local name="$1" tag="$2"
    cat > "$TMP/$name" <<EOF
#!/usr/bin/env bash
# sarsoo: summary="fixture $name"
# sarsoo: visibility="public"
printf '%s:%s\n' '$tag' "\$*"
EOF
    chmod +x "$TMP/$name"
}

make_leaf so-echo echo
make_leaf so-echo-nested nested
make_leaf so-echo-nested-deep deep
make_leaf so-echo-bar bar
make_leaf so-umbrella-child umbrella-child

cat > "$TMP/so-fail" <<'EOF'
#!/usr/bin/env bash
# sarsoo: summary="fixture that fails"
# sarsoo: visibility="public"
exit 42
EOF
chmod +x "$TMP/so-fail"

pass=0
fail=0

# run <args...>: sets OUTPUT (stdout+stderr) and RC.
run() {
    OUTPUT="$("$TMP/so" "$@" 2>&1)"
    RC=$?
}

assert_output() {
    local desc="$1" expected="$2"
    if [[ "$OUTPUT" == "$expected" ]]; then
        pass=$((pass + 1))
        printf 'ok   - %s\n' "$desc"
    else
        fail=$((fail + 1))
        printf 'FAIL - %s\n       expected: %q\n       actual:   %q\n' "$desc" "$expected" "$OUTPUT"
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

# 1. Plain positional to a leaf.
run echo alpha
assert_output "leaf accepts a single positional" 'echo:alpha'
assert_rc "leaf positional exits 0" 0

# 2. Argument boundaries preserved.
run echo "a b" c
assert_output "leaf preserves argument boundaries" 'echo:a b c'

# 3. Greedy subcommand resolution still wins.
run echo nested
assert_output "greedy subcommand wins over leaf positional" 'nested:'

# 4. Deep greedy resolution.
run echo nested deep
assert_output "deep greedy subcommand resolves" 'deep:'

# 5. Fallback when a token is not a subcommand.
run echo alpha beta
assert_output "fallback forwards multiple positionals" 'echo:alpha beta'

# 6. `--` overrides greedy subcommand matching.
run echo bar
assert_output "subcommand match without --" 'bar:'
run echo -- bar
assert_output "-- forces positional past a subcommand" 'echo:bar'

# 7. Help handling at a leaf and after `--`.
run echo --help
assert_output "leaf --help is handled by the leaf" 'echo:--help'
run echo -- -h
assert_output "-- bypasses help interception" 'echo:-h'

# 8. Root help.
run
assert_contains "root with no args prints usage" 'Available commands'
assert_contains "root help lists public command" 'echo'
assert_rc "root help exits 0" 0

# 9. Unknown root command.
run nope
assert_rc "unknown root command exits 1" 1
assert_contains "unknown root command is reported" "unknown command 'nope'"

# 10. Umbrella with an unknown token.
run umbrella nope
assert_rc "umbrella unknown token exits 1" 1
assert_contains "umbrella unknown token is reported" "unknown command 'nope'"

# 11. Umbrella and bare `--` print help.
run umbrella
assert_contains "umbrella with no args prints help" 'Available commands'
assert_rc "umbrella help exits 0" 0
run --
assert_contains "bare -- prints root help" 'Available commands'
assert_rc "bare -- exits 0" 0

# 12. A non-leaf cannot receive positional arguments.
run -- foo
assert_rc "root -- with leftover errors" 1
assert_contains "root -- leftover is reported" "unknown command 'foo'"

# 13. Exit status propagation.
run fail
assert_rc "leaf exit status propagates" 42

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
