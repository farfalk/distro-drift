#!/usr/bin/env bats
#
# Tests for the parts of distro-drift that can be exercised without root.
# The report itself needs root and a real dpkg database, so it is not
# unit-tested here — CI only guarantees that the CLI surface behaves.

setup() {
    DD="${BATS_TEST_DIRNAME}/../distro-drift"
}

@test "script passes a syntax check" {
    run bash -n "$DD"
    [ "$status" -eq 0 ]
}

@test "--version prints a semver-looking string" {
    run "$DD" --version
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^distro-drift\ [0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "-V is equivalent to --version" {
    run "$DD" -V
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^distro-drift ]]
}

@test "--help exits 0 and mentions the main options" {
    run "$DD" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--sections"* ]]
    [[ "$output" == *"--save"* ]]
    [[ "$output" == *"--diff"* ]]
    [[ "$output" == *"--verify"* ]]
    [[ "$output" == *"--json"* ]]
}

@test "--list prints all nine sections" {
    run "$DD" --list
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 9 ]
    [[ "${lines[0]}" == *"Third-party software sources"* ]]
    [[ "${lines[8]}" == *"Software outside apt"* ]]
}

@test "unknown option exits 2 with a hint" {
    run "$DD" --definitely-not-an-option
    [ "$status" -eq 2 ]
    [[ "$output" == *"--help"* ]]
}

@test "--sections without an argument exits 2" {
    run "$DD" --sections
    [ "$status" -eq 2 ]
}

@test "--sections rejects unknown section numbers" {
    run "$DD" -s 99
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown section '99'"* ]]
    run "$DD" -s 1,99
    [ "$status" -eq 2 ]
    [[ "$output" == *"'99'"* ]]
}

@test "--sections rejects an empty list" {
    run "$DD" -s ,
    [ "$status" -eq 2 ]
    [[ "$output" == *"no sections requested"* ]]
}

@test "--snapshots does not require root" {
    run "$DD" --snapshots
    [ "$status" -eq 0 ]
}

@test "report mode refuses to run without root" {
    if [ "$(id -u)" -eq 0 ]; then
        skip "running as root"
    fi
    run "$DD"
    [ "$status" -eq 1 ]
    [[ "$output" == *"root"* ]]
}

@test "--diff with an unresolvable snapshot exits 2 (diff error)" {
    if [ "$(id -u)" -ne 0 ]; then
        skip "needs root to reach the diff branch"
    fi
    run "$DD" --diff /nonexistent-snapshot-file.txt
    [ "$status" -eq 2 ]
}

# ── snapshot reference resolution ──────────────────────────────────────
# These use a throwaway snapshot directory, so they need no root and touch
# nothing on the host.

setup_fake_snapshots() {
    export DISTRO_DRIFT_SNAPDIR="${BATS_TEST_TMPDIR}/snaps"
    mkdir -p "$DISTRO_DRIFT_SNAPDIR"
    local i=0
    for d in 2026-06-01-1000 2026-07-01-1000 2026-07-15-1000 2026-08-01-0900; do
        printf 'distro-drift 1.0.0 — fake\nhost: x\ndpkg index: 1\nMARK-%s\nshared\n' \
            "$d" > "$DISTRO_DRIFT_SNAPDIR/$d.txt"
        touch -d "2026-01-0$((++i))" "$DISTRO_DRIFT_SNAPDIR/$d.txt"
    done
}

@test "--snapshots lists refs newest first" {
    setup_fake_snapshots
    run "$DD" --snapshots
    [ "$status" -eq 0 ]
    [[ "$output" == *"@0"* ]]
    [[ "$output" == *"@3"* ]]
}

@test "--diff between two stored snapshots needs no root" {
    setup_fake_snapshots
    run "$DD" --diff @3 @0
    [ "$status" -eq 1 ]           # 1 = differences found, as diff(1)
    [[ "$output" == *"MARK-"* ]]
}

@test "--diff of a snapshot against itself reports identical" {
    setup_fake_snapshots
    run "$DD" --diff @0 @0
    [ "$status" -eq 0 ]
    [[ "$output" == *"identical"* ]]
}

@test "a date prefix resolves when unambiguous" {
    setup_fake_snapshots
    run "$DD" --diff 2026-07-15 @0
    [ "$status" -eq 1 ]
    [[ "$output" == *"2026-07-15"* ]]
}

@test "an ambiguous prefix is rejected and lists the candidates" {
    setup_fake_snapshots
    run "$DD" --diff 2026-07 @0
    [ "$status" -eq 2 ]           # 2 = error, not "differs" — diff(1) convention
    [[ "$output" == *"ambiguous"* ]]
}

@test "an out-of-range @N is rejected with the count" {
    setup_fake_snapshots
    run "$DD" --diff @99 @0
    [ "$status" -eq 2 ]           # 2 = error, per diff(1)
    [[ "$output" == *"only 4 stored"* ]]
}

@test "an unknown name is rejected with a pointer to --snapshots" {
    setup_fake_snapshots
    run "$DD" --diff nosuchthing @0
    [ "$status" -eq 2 ]           # 2 = error, per diff(1)
    [[ "$output" == *"--snapshots"* ]]
}

@test "a non-numeric @N is rejected cleanly" {
    setup_fake_snapshots
    run "$DD" --diff @5x @0
    [ "$status" -eq 2 ]
    [[ "$output" == *"invalid snapshot reference"* ]]
}

@test "'latest' is an alias for @0" {
    setup_fake_snapshots
    run "$DD" --diff latest @0
    [ "$status" -eq 0 ]
    [[ "$output" == *"identical"* ]]
}

@test "--diff on an unreadable snapshot exits 2, not falsely identical" {
    if [ "$(id -u)" -eq 0 ]; then
        skip "root can read chmod 000 files"
    fi
    setup_fake_snapshots
    chmod 000 "$DISTRO_DRIFT_SNAPDIR/2026-08-01-0900.txt"
    run "$DD" --diff @3 @0
    [ "$status" -eq 2 ]
    [[ "$output" == *"cannot read snapshot"* ]]
    [[ "$output" != *"identical"* ]]
}

@test "-v flag is accepted and does not error" {
    run "$DD" -v --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"verbose"* ]]
}

# ── F1 regression test: noise filter cleaning ──────────────────────────────
# grep -vEf treats blank lines as matching everything, which hides all unowned files.
# This test verifies the cleaning step works.

@test "noise filter cleaning removes comments and blank lines" {
    local tmpdir
    tmpdir=$(mktemp -d)
    
    # Create a fake noise file with comments, blank lines, and one real pattern
    printf '# Comment line\n\n/real/pattern\n\n# Another comment\n\n' > "$tmpdir/noise"
    
    # Run the cleaning command
    run grep -vE '^[[:space:]]*(#|$)' "$tmpdir/noise"
    [ "$status" -eq 0 ]
    # Should have exactly one non-empty line
    local count
    count=$(echo "$output" | grep -c .)
    [ "$count" -eq 1 ]
    [[ "$output" == *"/real/pattern"* ]]
    
    rm -rf "$tmpdir"
}

# ── F3 regression test: origin detection with dots and slashes ────────────
# The original regex [A-Za-z][A-Za-z -]* missed origins like riot.im: and
# packagecloud.io/filips/FirefoxPWA:

@test "origin regex matches dots and slashes" {
    # Create a temp file with test lines
    local tmpdir
    tmpdir=$(mktemp -d)
    printf 'element-desktop (1.12.24) [riot.im: 1.12.24]\n' > "$tmpdir/test1"
    printf 'firefoxpwa (2.18.4) [packagecloud.io/filips/FirefoxPWA: 2.18.4]\n' > "$tmpdir/test2"
    printf 'zotero (9.0.6)\n' > "$tmpdir/test3"
    
    # Test with the corrected regex: extract origins
    run grep -oE '\[[^]:]+:' "$tmpdir/test1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[riot.im:"* ]]
    
    run grep -oE '\[[^]:]+:' "$tmpdir/test2"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[packagecloud.io/filips/FirefoxPWA:"* ]]
    
    run grep -oE '\[[^]:]+:' "$tmpdir/test3"
    [ "$status" -eq 1 ]

    rm -rf "$tmpdir"
}

# ── --verify tests ──────────────────────────────────────────────────────

@test "--verify refuses to run without root" {
    if [ "$(id -u)" -eq 0 ]; then
        skip "running as root"
    fi
    run "$DD" --verify
    [ "$status" -eq 1 ]
    [[ "$output" == *"root"* ]]
}

@test "--verify with no snapshots fails cleanly" {
    if [ "$(id -u)" -ne 0 ]; then
        skip "needs root to reach the verify branch"
    fi
    export DISTRO_DRIFT_SNAPDIR="${BATS_TEST_TMPDIR}/empty"
    mkdir -p "$DISTRO_DRIFT_SNAPDIR"
    run "$DD" --verify
    [ "$status" -eq 2 ]
}

# ── --json tests ────────────────────────────────────────────────────────
# JSON output is validated with python3 -m json.tool (no jq dependency).
# Every test skips cleanly when python3 is absent.

@test "--snapshots --json emits valid JSON listing the snapshots" {
    command -v python3 >/dev/null || skip "python3 not available"
    setup_fake_snapshots
    run "$DD" --snapshots --json
    [ "$status" -eq 0 ]
    echo "$output" | python3 -m json.tool > /dev/null
    [[ "$output" == *'"snapshots":['* ]]
    [[ "$output" == *'"ref":"@0"'* ]]
    [[ "$output" == *'"name":"2026-08-01-0900"'* ]]
    [[ "$output" == *'"size_bytes":'* ]]
    [[ "$output" == *'"age_days":'* ]]
}

@test "--snapshots --json emits an empty array when no snapshots exist" {
    command -v python3 >/dev/null || skip "python3 not available"
    export DISTRO_DRIFT_SNAPDIR="${BATS_TEST_TMPDIR}/empty-json"
    mkdir -p "$DISTRO_DRIFT_SNAPDIR"
    run "$DD" --snapshots --json
    [ "$status" -eq 0 ]
    echo "$output" | python3 -m json.tool > /dev/null
    [[ "$output" == *'"snapshots":[]'* ]]
}

@test "--diff --json marks identical snapshots and exits 0" {
    command -v python3 >/dev/null || skip "python3 not available"
    setup_fake_snapshots
    run "$DD" --diff @0 @0 --json
    [ "$status" -eq 0 ]
    echo "$output" | python3 -m json.tool > /dev/null
    [[ "$output" == *'"identical":true'* ]]
    [[ "$output" == *'"diff":[]'* ]]
}

@test "--diff --json reports differences as a line array and exits 1" {
    command -v python3 >/dev/null || skip "python3 not available"
    setup_fake_snapshots
    run "$DD" --diff @3 @0 --json
    [ "$status" -eq 1 ]           # 1 = differs, as diff(1)
    echo "$output" | python3 -m json.tool > /dev/null
    [[ "$output" == *'"identical":false'* ]]
    [[ "$output" == *'MARK-'* ]]
}

@test "--diff --json with an unresolvable ref emits a JSON error object and exits 2" {
    command -v python3 >/dev/null || skip "python3 not available"
    setup_fake_snapshots
    run "$DD" --diff @99 @0 --json
    [ "$status" -eq 2 ]           # 2 = error, per diff(1)
    echo "$output" | python3 -m json.tool > /dev/null
    [[ "$output" == *'"error":'* ]]
    [[ "$output" == *'"schema":1'* ]]
}

@test "--json turns the root refusal into a JSON error object and exits 1" {
    command -v python3 >/dev/null || skip "python3 not available"
    if [ "$(id -u)" -eq 0 ]; then
        skip "running as root"
    fi
    run "$DD" --save --json
    [ "$status" -eq 1 ]
    echo "$output" | python3 -m json.tool > /dev/null
    [[ "$output" == *'"error":'* ]]
    [[ "$output" == *'root'* ]]
}
