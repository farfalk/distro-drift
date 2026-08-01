# Changelog

Format based on [Keep a Changelog](https://keepachangelog.com/).
This project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
