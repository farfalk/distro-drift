# Changelog

Format based on [Keep a Changelog](https://keepachangelog.com/).
This project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- `--json` flag: machine-readable JSON output for `--snapshots` and `--diff` —
  the two commands that run without root, meant for scripts and agents.
  `--snapshots --json` prints a `snapshots` array (`ref`, `name`,
  `size_bytes`, `age_days`, `path`); `--diff A B --json` prints `a`, `b`,
  `identical` and the diff as a `diff` array of lines (exit status still
  follows `diff(1)`). Every non-zero exit emits a JSON error object on
  stdout. Other modes ignore `--json` and keep their text output. The JSON
  schema is a versioned API: breaking changes bump the `schema` field and
  need a semver minor.
- `skills/distro-drift/SKILL.md`: agent skill with the diagnostic workflow, a
  two-branch playbook for `--verify` MISSING/BROKEN findings (package vs
  user-authored items), and a "system customisation report" flow that helps
  the user document their customisations as diffs from stock behavior and
  share them with other users of the distribution.

### Changed
- Snapshots are now written mode `0640 root:<group of the invoking sudo
  user>` instead of `0600 root:root`, so the user who ran
  `sudo distro-drift --save` can read snapshots and diff two stored ones
  without sudo. Snapshots written by older versions stay `0600` until
  re-saved.
- `--save` success output now shows both diff forms: `sudo distro-drift
  --diff` (latest snapshot vs now) and `distro-drift --diff @1 @0` (two
  stored snapshots, no root).
- `-s`/`--sections` now rejects unknown section numbers (exit 2) instead of
  silently producing an empty report. An empty list is also rejected.
- `--save` refuses to overwrite a snapshot taken in the same minute (exit 1)
  instead of silently replacing it.
- CI pins `ludeeus/action-shellcheck` to the v2.0.0 commit SHA instead of the
  mutable `@master` ref (supply-chain hygiene).

### Fixed
- Sections 5–7 iterate unowned paths with `while read` instead of `for x in
  $(...)`: paths containing spaces no longer break the report (previously
  each such path was split into garbage entries).

### Fixed
- `--save` writes snapshots atomically: report goes to a temp file in the
  snapshot dir, `chmod 600` is applied there, then a rename installs it. An
  interrupted `--save` (Ctrl+C, full disk) no longer leaves a partial
  header-only snapshot that looks like a valid one, and the file is never
  briefly world-readable. Write failures now exit 1 with an error instead of
  printing "Snapshot written".
- `--diff` exits 2 (diff error) on unresolvable or missing snapshot
  references, instead of 1 which means "differs" per `diff(1)`. Previously a
  typo'd reference masqueraded as drift found.
- `--verify` refuses snapshots without the `Done` footer (interrupted
  `--save`) with exit 2, instead of reporting `0 OK` and a false pass.
- `--verify`: ExecStart binaries are deduplicated against the custom-files
  section (each script was printed and counted twice).
- `--verify`: malformed lines without the `unit -> path` pattern are skipped
  instead of producing a bogus MISSING entry.
- Section 6 "User units" now inventories symlinks, not just regular files. The
  `*.target.wants/` and `*.service.wants/` links are a user unit's enabled
  state — previously enabling or disabling a user unit produced no drift.
  `--verify` checks these paths too: a disabled unit (symlink removed) or a
  broken link is now reported MISSING instead of silently passing.
- Non-numeric `@N` references (`@5x`) are rejected cleanly instead of
  emitting a bash arithmetic error.
- Section 2 fallback: removed a dead branch (the elif and else arms were
  identical). No behaviour change.

## [1.2.0] - 2026-09-24

### Added
- `--verify [REF]` mode: reads a stored snapshot and checks each custom
  modification against the live system. Reports which custom systemd units
  are still enabled/active, which ExecStart target binaries still exist,
  which custom config files (modprobe, udev, sysctl, systemd drop-ins) are
  still present, which custom scripts are still on disk, and which
  third-party repositories are still listed. Exit status: 0 = all OK,
  1 = some MISSING or BROKEN, 2 = error.
- Progress indicator on stderr during `--save` and report generation. Shows
  `[N/total] Section name ...` as each section is scanned. Uses carriage
  return on terminals (single updating line), newline when redirected to a
  file. Does not affect report output (stdout) or snapshot contents.

### Changed
- Section 4: intro text now says "Oldest first." to match the actual sort order
  (`sort -n | tac` lists highest age first). Previously claimed "Newest first."
  Diffing a snapshot from an older version against a newer one shows this as a
  one-line change.
- `--diff` now strips the `cruft report:` timestamp line from section 4 —
  cruft-ng embeds the current time in its output, so the line changed on every
  run and masked real drift.
- Replaced `AI_DISCLOSURE.md` (per-file SPDX headers from the ggfevans/ai-disclosure
  convention) with a contribution policy in `CONTRIBUTING.md`. Disclosure now
  happens in pull request descriptions via `.github/PULL_REQUEST_TEMPLATE.md`,
  not in source-file headers or commit messages.
- `AGENTS.md`: removed non-existent `make status` from the commands list; added
  a "Do not modify" boundaries section.

### Fixed
- `--diff` between two stored snapshots reported "(identical)" with exit 0
  when the snapshot files were unreadable (e.g. run without root against
  mode-0600 snapshots): both streams diffed as empty. Now exits 2 (error)
  with a "cannot read snapshot" message, per the `diff(1)` convention.
- ShellCheck warnings in `distro-drift` (SC2034 unused variable, SC2002 useless
  cat) that broke `make check` and CI lint.

## [1.1.2] - 2026-08-01

### Changed
- Section 4: extended noise filter to hide `/usr/local/(lib|lib64|share|include|libexec)/`
  and `/etc/libreoffice/registry/` — payload of locally compiled software. Added
  a summary line showing the count of hidden files under `/usr/local`. Section 4
  output **shrunk** from ~1255 to ~250-400 lines. Snapshots taken with 1.1.x
  will show a large spurious diff for `/usr/local`.

### Fixed
- Section 2: group 1 packages now print one per line instead of being concatenated
  on a single line. Section 2 line count in the summary increases by 5.

## [1.1.1] - 2026-08-01

### Fixed
- Section 4, 5, 6: **1.1.0 reports are unreliable** — `unowned()` returned nothing due to
  blank lines in the noise filter file causing `grep -vEf` to match everything. Anyone
  who saved a snapshot with 1.1.0 must retake it.
- Section 2: literal `\n` sequences appeared in group 1 output due to incorrect
  string accumulation. Now uses `printf` to handle newlines correctly.
- Section 2: origin detection regex now matches labels with dots and slashes
  (e.g., `riot.im:`, `packagecloud.io/filips/FirefoxPWA:`). Previously these were
  incorrectly classified as having no origin.

## [1.1.0] - 2026-08-01

### Added
- `--diff` now accepts up to two snapshot references, git-style: no argument
  compares the latest snapshot against the current state, one argument compares
  that snapshot against the current state, two compare stored snapshots
  against each other.
- Snapshot references: `@N` by age, `latest`, date prefixes, bare names, paths,
  and `now` for the live system.
- `--snapshots` lists each snapshot with its `@N` reference, size and age.
- Comparing two stored snapshots no longer requires root.
- Exit status of `--diff` follows `diff(1)`: 0 identical, 1 differs, 2 error.
- `DISTRO_DRIFT_SNAPDIR` overrides the snapshot directory (used by the tests).
- `-v`/`--verbose` flag in section 2 to show all packages (including those that
  differ only in version within official repos).
- Section summary showing line counts for each requested section.

### Changed
- Section 2 (Packages not from official repositories): output now groups packages
  into three categories — no known origin, third-party origins, and official-repo
  version differences (hidden by default, shown with `-v`). **Reports from 1.0.x
  will show large spurious diffs against 1.1.0 reports.**
- Section 4 (Unowned files): extended noise filter to exclude NetworkManager
  configs, gettext catalogs, manual pages, pkg-config files, and SSH host keys.
  Added `generated (gpu-manager)` label for NVIDIA X11 configs in section 8.

## [1.0.0] - 2026-08-01

First release.

### Added
- Nine inventory sections: sources, packages, modified package files,
  unowned files, kernel/boot, systemd, autostart, graphics, non-apt software.
- `--save` / `--diff` snapshot workflow.
- `--sections` to run a subset, `--quick` to skip slow filesystem scans.
- Delegation to `debsums`, `cruft-ng` and `apt-forktracer` when installed.
- dpkg file index built once from `/var/lib/dpkg/info/*.list`, with usrmerge
  path normalisation, `dpkg-divert` and `update-alternatives` entries folded in.
