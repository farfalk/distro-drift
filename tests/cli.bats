#!/usr/bin/env bats
#
# Tests for the parts of distro-drift that can be exercised without root.
# The report itself needs root and a real dpkg database, so it is not
# unit-tested here — CI only guarantees that the CLI surface behaves.

setup_file() {
    # Use Bats' temporary directory for test snapshots
    # This ensures tests never write to /var/lib/distro-drift
    export DISTRO_DRIFT_SNAPDIR="$BATS_TMPDIR/distro-drift-snapdir"
    mkdir -p "$DISTRO_DRIFT_SNAPDIR"
}

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

@test "--diff without a snapshot fails cleanly rather than crashing" {
    if [ "$(id -u)" -ne 0 ]; then
        skip "needs root to reach the diff branch"
    fi
    run "$DD" --diff /nonexistent-snapshot-file.txt
    [ "$status" -eq 1 ]
}

# ── snapshot reference resolution ──────────────────────────────────────
# These use a throwaway snapshot directory, so they need no root and touch
# nothing on the host.

setup_fake_snapshots() {
    export DISTRO_DRIFT_SNAPDIR="${BATS_TMPDIR}/snaps"
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
    [ "$status" -eq 1 ]
    [[ "$output" == *"ambiguous"* ]]
}

@test "an out-of-range @N is rejected with the count" {
    setup_fake_snapshots
    run "$DD" --diff @99 @0
    [ "$status" -eq 1 ]
    [[ "$output" == *"only 4 stored"* ]]
}

@test "an unknown name is rejected with a pointer to --snapshots" {
    setup_fake_snapshots
    run "$DD" --diff nosuchthing @0
    [ "$status" -eq 1 ]
    [[ "$output" == *"--snapshots"* ]]
}

@test "'latest' is an alias for @0" {
    setup_fake_snapshots
    run "$DD" --diff latest @0
    [ "$status" -eq 0 ]
    [[ "$output" == *"identical"* ]]
}

@test "-v flag is accepted and does not error" {
    run "$DD" -v --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"verbose"* ]]
}
