# AGENTS.md

Single Bash script (`distro-drift`) that audits a Debian/Ubuntu system for
deviations from the stock distribution. No build step.

## Commands

```sh
make check                        # shellcheck + bats — run before every commit
make lint                         # shellcheck only
make test                         # bats only
./distro-drift --help             # dev copy
sudo make install                 # -> /usr/local/bin/distro-drift
```

Run tests with `DISTRO_DRIFT_SNAPDIR` pointing at a temp dir. Tests must never
read or write `/var/lib/distro-drift`.

## Invariants — violating any of these is a bug, not a style choice

**READ-ONLY.** The script must never create, modify or delete anything outside
`$SNAPDIR` and `$TMP`. No `apt`, no `systemctl start/stop`, no `rm` outside
`$TMP`. A user must be able to run it on a production machine without thinking.

**DO NOT add `set -e` or `set -u`.** The script runs dozens of probes that are
*expected* to fail on systems lacking a given tool or path. `set -e` would abort
on the first one. This is deliberate and documented in the script header — every
agent tries to "fix" it.

**Output format is a long-lived data format.** Users diff today's report against
one saved months ago. Changing a section heading, a `--- subsection ---` label,
or the `%5sd  %s` line format silently breaks every historical comparison.
Treat these strings as an API: additive changes only, unless the CHANGELOG
records the break and the version gets a minor bump.

**Every section must stay independently runnable.** Section bodies are guarded
by `if want N; then ... fi`. Never let section N read state produced by section
M. `-s 8` alone must produce valid output.

**`--diff` exit status follows `diff(1)`**: 0 identical, 1 differs, 2 error.
Do not "improve" this to always-0.

## Non-obvious implementation details

`build_index` reads `/var/lib/dpkg/info/*.list` **once** into `$TMP/pkgfiles`.
Do not call `dpkg -S` per file — on a real system that is 700k+ lookups and
turns seconds into many minutes.

`norm()` rewrites `/bin/` → `/usr/bin/` etc. On usrmerge systems dpkg records
some paths the old way and some the new way; without normalisation the unowned-
file detection produces hundreds of false positives. Any new path comparison
must go through `norm`.

The noise filter is the heredoc in `write_noise_filter`. It is the tuning knob
of section 4. Adding a pattern there is the correct fix for a false positive —
do not add ad-hoc `grep -v` inside individual sections.

Optional tools (`debsums`, `cruft-ng`, `apt-forktracer`) must be probed with
`command -v` and skipped with a one-line "not installed" hint. Never make them
hard dependencies.

## Do not modify

- `tests/` are CLI-surface tests only. Do not add tests that require root or a
  real dpkg database — the `smoke` CI job covers that.
- The noise filter heredoc in `write_noise_filter` is the only place to add
  section-4 exclusions. Never add `grep -v` inside individual sections.
- Do not add new shellcheck disable directives without justification.

## Testing constraints

The full report needs root and a real dpkg database, so it cannot be unit
tested. Tests cover the CLI surface only: argument parsing, snapshot reference
resolution, exit codes. New CLI behaviour needs a test in `tests/cli.bats`.
New report *content* does not — the CI `smoke` job runs the real thing on a
throwaway Ubuntu runner.

## Definition of done

- [ ] `make check` passes
- [ ] `CHANGELOG.md` updated under `[Unreleased]`
- [ ] `VERSION` bumped if behaviour changed (semver)
- [ ] `--help` updated if flags changed
- [ ] No new output-format break without a CHANGELOG note
- [ ] Ran `sudo ./distro-drift` once on a real system and eyeballed the section
      you touched
