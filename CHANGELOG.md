# Changelog

Format based on [Keep a Changelog](https://keepachangelog.com/).
This project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Progress indicator on stderr during `--save` and report generation. Shows
  `[N/total] Section name ...` as each section is scanned. Uses carriage
  return on terminals (single updating line), newline when redirected to a
  file. Does not affect report output (stdout) or snapshot contents.

### Changed
- Replaced `AI_DISCLOSURE.md` (per-file SPDX headers from the ggfevans/ai-disclosure
  convention) with a contribution policy in `CONTRIBUTING.md`. Disclosure now
  happens in pull request descriptions via `.github/PULL_REQUEST_TEMPLATE.md`,
  not in source-file headers or commit messages.
- `AGENTS.md`: removed non-existent `make status` from the commands list; added
  a "Do not modify" boundaries section.

### Fixed
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
