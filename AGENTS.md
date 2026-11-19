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

**The JSON schema is also a long-lived data format.** `--json` (supported on
`--snapshots` and `--diff` only) is versioned via the `schema` field; breaking
changes need a CHANGELOG entry and a semver minor bump. Rule: no code path
exits non-zero with non-JSON stdout while `--json` is set — every error path
goes through `die`/`ref_die`.

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

The noise filter only filters *printed* lines; it cannot make a slow scan
faster. Section 4 therefore has a second, separate exclusion mechanism: the
`$TMP/cruft-ignore` file passed to `cruft-ng -I`. Entries are literal path
prefixes — cruft-ng appends a trailing `/` and does no glob expansion, so
`/tmp/.mount_*` would match nothing. cruft-ng already skips `/home`, `/mnt`,
`/tmp`, `/root` and `/dev` itself.

That list serves two purposes, and a new entry should say which one it is for:

- **Runtime.** The big non-dpkg content stores (`/timeshift`,
  `/var/lib/flatpak`, container layers). On a Timeshift+Flatpak machine those
  are 11.6M of 16M paths: without them section 4 takes 34 minutes, with them
  about a minute.
- **Noise.** Trees where *every* file is unowned by definition, so listing them
  is pure noise. `/boot/efi` is the case in point: the ESP is written by
  `grub-install`, shim and Windows, and its hundreds of Windows Boot Manager
  files fill the whole `unexplained` budget on their own.

The `cruft-ng` output budget is split per block, not one `head -100` over the
whole stream: `---- missing: dpkg ----` gets 20 lines and
`---- unexplained: / ----` gets 80. The first block is mostly ruleset false
positives and would otherwise starve the second, which is the part worth
reading.

Progress goes to fd 4, a saved copy of stderr, because each section does
`exec > file 2>&1` and would otherwise swallow it. `progress_show` prints the
section counter; `progress_run LABEL CMD` draws a spinner with elapsed seconds
while `CMD` runs. `progress_run` keeps `CMD` in the foreground and backgrounds
only the spinner, so stdin and the exit status are untouched — do not "simplify"
it by backgrounding the command. Both are silent when fd 4 is not a tty, which
is what keeps logs, CI and `--json` clean.

Optional tools (`debsums`, `cruft-ng`, `apt-forktracer`) must be probed with
`command -v` and skipped with a one-line "not installed" hint. Never make them
hard dependencies.

Snapshots are written `0640 root:<group of the invoking sudo user>`, not
`0600`, so the user who ran `sudo distro-drift --save` can read and diff them
without sudo (their agents/tools run as them). The content is paths and names,
not secrets. The `chmod`+`chgrp` happen on the temp file before the atomic
rename — the final file is never world-readable even briefly. Existing
snapshots stay `0600` until re-saved.

`jesc()` passes valid UTF-8 through raw and escapes only backslash, quote and
C0 control chars. A path containing invalid UTF-8 bytes therefore yields
invalid JSON — accepted limit: snapshot names are ASCII and user paths with
invalid UTF-8 are rare. Do not "fix" this by escaping every non-ASCII byte as
`\u00XX`: that mangles valid UTF-8 (`café` → `cafÃ©`). A UTF-8-aware escaper
is the upgrade path if it ever bites.

## Do not modify

- `tests/` are CLI-surface tests only. Do not add tests that require root or a
  real dpkg database — the `smoke` CI job covers that.
- The noise filter heredoc in `write_noise_filter` is the only place to add
  section-4 *output* exclusions. Never add `grep -v` inside individual
  sections. (The `cruft-ignore` list above is a runtime knob, not a filter.)
- Do not add new shellcheck disable directives without justification.

## Testing constraints

The full report needs root and a real dpkg database, so it cannot be unit
tested. Tests cover the CLI surface only: argument parsing, snapshot reference
resolution, exit codes. New CLI behaviour needs a test in `tests/cli.bats`.
New report *content* does not — the CI `smoke` job runs the real thing on a
throwaway Ubuntu runner.

## --verify mode

`--verify` parses a stored snapshot and checks each custom modification
against the live system. It does **not** re-run any report sections — it
reads the snapshot text and checks live state with `systemctl`, `test -f`,
and `grep`. Parsing depends on the snapshot output format (subsection
labels like `--- Enabled units not owned by any package ---`, the
`unit  ->  path` pattern, the `[path]` block format, the `%5sd  %s` line
format). If you change any of these output strings, update the parsers in
`verify_snapshot()` too.

## Definition of done

- [ ] `make check` passes
- [ ] `CHANGELOG.md` updated under `[Unreleased]`
- [ ] `VERSION` bumped if behaviour changed (semver)
- [ ] `--help` updated if flags changed
- [ ] No new output-format break without a CHANGELOG note
- [ ] Ran `sudo ./distro-drift` once on a real system and eyeballed the section
      you touched
