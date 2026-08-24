# distro-drift

Inventory everything on a Debian/Ubuntu system that deviates from the stock
distribution: third-party repositories, non-official package versions, modified
package files, hand-added files, local systemd units, custom kernel parameters,
Xorg overrides, and software installed outside apt.

Read-only. Written for the moment before a release upgrade, when you need to
know what you'll have to recreate by hand — and for the more common moment when
you're staring at a machine wondering what past-you did to it.

## Why this exists

There is no single tool for this. The pieces exist and are fragmented:

| Tool | Covers |
|---|---|
| `dpkg --verify` / `debsums` | files belonging to packages that were modified |
| `cruft` / `cruft-ng` | files present on disk but owned by no package |
| `apt-forktracer` | installed versions not available from official repos |
| `etckeeper` | changes to `/etc` **from the moment you install it** |

None of them covers services, kernel parameters, autostart, or software
installed outside the package manager. `distro-drift` runs the ones that exist,
adds the parts nobody covers, and prints one report.

## Known limitation

Debian has no formal way to distinguish *file shipped by a package* from
*file legitimately generated at runtime* from *file the admin put there*.
`cruft` approximates the distinction with a hand-maintained ruleset that
[Debian's own wiki](https://wiki.debian.org/Cruft) describes as neither
exhaustive nor current, and notes that fixing this properly would require dpkg
to record which files `--purge` will remove — something RPM has via `%ghost`
and dpkg does not.

So section 4 contains false positives. It is an inventory to read, not a list
of things to delete. Distributions that solve this properly (NixOS, Guix) do so
by making the entire system declarative, which is a different bargain.

## Install

```sh
sudo make install                     # -> /usr/local/bin/distro-drift
sudo apt install debsums cruft-ng apt-forktracer   # optional, recommended
```

Or manually:

```sh
sudo install -m 755 distro-drift /usr/local/bin/distro-drift
```

## Usage

```sh
sudo distro-drift                 # full report to stdout
sudo distro-drift --save          # dated snapshot in /var/lib/distro-drift/
sudo distro-drift --diff          # what changed since the last snapshot
sudo distro-drift -s 4            # only hand-added files
sudo distro-drift -s 1,2 --quick  # sources and packages, fast
distro-drift --snapshots          # list stored snapshots and their refs
distro-drift --help
```

### The workflow that makes it worth having

```sh
sudo distro-drift --save          # today
# ...months of tinkering...
sudo distro-drift --diff          # before the release upgrade
```

The diff is the point. A single report tells you the state; two reports tell
you what you did.

### Snapshot references

`--diff` takes zero, one or two references, git-style:

```sh
sudo distro-drift --diff              # latest snapshot vs current state
sudo distro-drift --diff @3           # 4th-newest snapshot vs current state
distro-drift      --diff @3 @1        # two stored snapshots — no root needed
distro-drift      --diff 2026-06 @0   # by date prefix
sudo distro-drift --diff @2 now       # explicit; 'now' means current state
```

| Reference | Meaning |
|---|---|
| `@0`, `@1`, `@2` … | by age, `@0` is the most recent (like `HEAD~N`) |
| `latest` | alias for `@0` |
| `2026-06` | date prefix; must match exactly one snapshot |
| `2026-06-01-1000` | full name, with or without `.txt` |
| `./path/to/file.txt` | any path |
| `now` | the current system state (requires root) |

`distro-drift --snapshots` prints the reference for each stored snapshot.

Exit status follows `diff(1)`: **0** if identical, **1** if they differ, **2**
on error. That makes it usable in scripts and CI.

Comparing two stored snapshots generates nothing, so it does not require root.

## Sections

| # | Section | What it answers |
|---|---|---|
| 1 | Third-party software sources | Which PPAs and external repos are configured, and when they were added |
| 2 | Packages not from official repositories | What won't downgrade cleanly on an upgrade |
| 3 | Modified package files | Which shipped files you edited |
| 4 | Files not owned by any package | What no upgrade will preserve for you |
| 5 | Kernel, modules, boot | Kernel command line, modprobe.d, sysctl, udev, DKMS |
| 6 | systemd services | Non-package units, masked units, drop-in overrides |
| 7 | Autostart and scheduling | cron, user crontabs, desktop autostart, profile.d |
| 8 | Graphics | Xorg config, including which files are modified vs hand-added |
| 9 | Software outside apt | Flatpak, Snap, AppImage, pipx, cargo, npm globals |

Section 8 flags Xorg files under `/usr/share` as `** MODIFIED **`. Those get
silently reverted by the next package update — if a change there matters, move
it to `/etc/X11/xorg.conf.d/`, which takes precedence.

## Snapshots

Stored in `/var/lib/distro-drift/YYYY-MM-DD-HHMM.txt`, mode 0600. They can
contain hostnames, usernames, package inventories and repository URLs — treat
them as system documentation, and keep copies off the machine they describe.

## Development

```sh
make lint      # shellcheck
make test      # bats
make check     # both
```

CI runs both on every push (see `.github/workflows/ci.yml`).

`set -e` is deliberately not used: this script runs dozens of probes that are
expected to fail on systems lacking a given tool or path. `pipefail` is on.

## Compatibility

Written for Debian/Ubuntu and derivatives (tested on Linux Mint 22.x). Depends
only on coreutils, dpkg, apt and systemd. Optional tools are detected at
runtime and skipped when absent.

---

Contributing: see [CONTRIBUTING.md](CONTRIBUTING.md).
