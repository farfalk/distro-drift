---
name: distro-drift
description: >-
  Use distro-drift to understand how a Debian/Ubuntu system deviates from
  stock: list and diff snapshots, verify custom modifications against live
  state, and help the user fix, update, or document their system — above all
  across a release upgrade. Includes a flow to build a shareable report of
  the user's customisations.
---

# distro-drift — agent skill

`distro-drift` inventories everything on a Debian/Ubuntu system that deviates
from the stock distribution: third-party repositories, non-official package
versions, modified package files, hand-added files, local systemd units,
custom kernel parameters, Xorg overrides, and software installed outside apt.
It is read-only: it never changes the system.

## When to use this skill

- The user asks "what changed on my system?", "what did I do to this machine?"
- After a distribution or kernel upgrade: something broke, or the user wants
  to check what survived.
- Before a release upgrade: take stock of what must be recreated by hand.
- A service, script, or config the user relies on stopped working.
- The user wants to document and share their customisations with other users
  of the same distribution.

## Commands and who runs them

| Command | Who runs it | Output |
|---|---|---|
| `distro-drift --snapshots --json` | the agent (no sudo) | JSON |
| `distro-drift --diff A B --json` | the agent (no sudo) | JSON |
| `sudo distro-drift --verify` | the human (sudo); paste the text back | text |
| `sudo distro-drift --save`, bare report | the human (sudo) | text |

Rules:

- The agent never runs anything under `sudo`. When a step needs root, ask the
  human to run it and paste the output.
- Snapshots are mode `0640 root:<group of the user who ran sudo>`, so the
  agent can read them and diff two stored snapshots without sudo. Snapshots
  written by distro-drift older than 1.3.0 are `0600 root:root` and not
  readable without sudo — ask the human to re-save (`sudo distro-drift --save`)
  or fix the permissions with sudo.
- `--json` applies to `--snapshots` and `--diff` only. On any error the JSON
  output is a single error object on stdout,
  `{"schema":1,...,"error":"...","hint":"..."}`, and the exit code is non-zero.
- `--diff` exit status follows `diff(1)`: 0 identical, 1 differs, 2 error.

### JSON shapes

`--snapshots --json`:
`{"schema":1,"tool":"distro-drift","version":"...","generated":"...","snapshots":[{"ref":"@0","name":"...","size_bytes":N,"age_days":N,"path":"..."}]}`
(`"snapshots":[]` when the store is empty). `@0` is the most recent snapshot.

`--diff A B --json`:
`{"schema":1,...,"a":"...","b":"...","identical":false,"diff":["<line>",...]}`
— `a`/`b` are the snapshot file names (`"now"` for the live system), `diff`
is the diff output as an array of lines. Exit 0 when identical, 1 when they
differ.

## Diagnostic workflow

1. **Orient.** `distro-drift --snapshots --json` — what snapshots exist.
2. **Measure drift.** `distro-drift --diff @1 @0 --json` — what changed between
   the two most recent snapshots. Read the `diff` lines critically: the report
   is an inventory, not a verdict (section 4 contains false positives).
3. **Check health.** Ask the human to run `sudo distro-drift --verify` and
   paste the output. It checks every custom modification recorded in the
   latest snapshot against the live system and reports `OK`, `MISSING` (gone)
   or `BROKEN` (present but wrong: unit failed, unmasked, not enabled) per
   item, ending with `Summary: N OK, N MISSING, N BROKEN`. Exit status:
   0 = all OK, 1 = some MISSING or BROKEN, 2 = error.
4. **Deep-dive per finding.** For each MISSING or BROKEN item, follow the
   two-branch playbook below.
5. **Propose fixes.** State what should change and why. The human applies it.
6. **Re-verify.** Ask the human to run `sudo distro-drift --verify` again (and
   optionally `sudo distro-drift --save` to record the new state).

## Two-branch playbook (per MISSING/BROKEN finding)

First classify the item.

### Branch A — package / ecosystem item

The path is owned by dpkg, the unit ships with a package, the binary lives in
`/usr/bin`, the repo is a vendor/PPA repository, or the package has a man
page. These exist in the distribution's ecosystem and have public
documentation.

1. Local read-only diagnostics: `dpkg -S <path>`, `dpkg -l <pkg>`,
   `apt policy <pkg>` / `apt-cache policy <pkg>` (queries only — never
   `apt update`), `systemctl status <unit>`, `journalctl -u <unit>`.
2. Package-expectation check: is this the package version the current
   distribution release is expected to ship, considering the latest updates
   of the distribution and its ecosystem? Compare the `apt policy` origin
   and candidate against what the distro release provides.
3. Search online for the state of the art: `<item> + <distro> + <version>`
   (e.g. "nvidia-powerd Ubuntu 24.04 service"). Cite what you find, or state
   plainly that nothing relevant was found.
4. Propose the fix accordingly (reinstall, reconfigure, pin, remove the PPA,
   ...).

### Branch B — user-authored, machine-specific item

The script lives in `/usr/local/bin` or `/usr/local/sbin`, the file is owned
by no package, it is the `ExecStart` target of a custom unit, or it contains
hardware-specific strings. Heuristics that mark an item as Branch B:

- path under `/usr/local/` (the FHS-reserved place for locally installed
  software) or inside the user's home;
- `dpkg -S <path>` finds no owner;
- it is the `ExecStart=` target of a unit not owned by any package;
- its content references this machine's hardware (a specific laptop model, a
  PCI/USB id, a DMI string);
- it has no man page and no upstream project.

For Branch B items **never search online** — a script written for this one
machine has no public footprint, and search results would be noise. Instead:

1. `cat` the script and its unit file. Read the comments, the commands, the
   files it touches, the `Description=` line.
2. Infer its purpose from that content; read its logs (`journalctl -u <unit>`,
   or `--user` for user units).
3. Explain to the user what it does and why it exists.
4. If it is MISSING, treat it as **user data loss**: look for backups (`.bak`
   files, timeshift snapshots, git). Never "reinstall the package" — no
   package ever shipped it.

## System customisation report (shareable)

Goal: help the user build a full report of every customisation they added to
the system, so they can share "how I made my machine work on this distro"
with other users of the same distribution.

Each customisation is read **as a diff from the default distribution
behavior** and listed with:

- **Location** — the path or unit.
- **Purpose** — why it exists (drafted by the agent, confirmed by the user).
- **Mechanism** — how it works, explained verbally from the code, the
  comments, and the surrounding context.

Flow:

1. **Source the list.** Read the latest snapshot (the agent can read it:
   mode `0640`), sections 4 (unowned files), 5 (kernel/boot configs), 6
   (systemd), 9 (software outside apt). Optionally ask the human to take a
   fresh `sudo distro-drift --save` first so the list is current.
2. **Filter to shareable customisations.** Focus on user-authored,
   machine-specific, purposeful customisations: scripts in `/usr/local`,
   custom systemd units, hardware-fix configs, custom udev/modprobe/sysctl
   rules, deliberately added PPAs/repos. Skip apt-managed config drift
   (php.ini tweaks, apparmor locals, dpkg merge artefacts) unless the user
   explicitly asks for a full-inventory appendix.
3. **Gather per entry.** Location; `cat` the file/unit; read comments,
   related files, `journalctl` logs.
4. **Frame as a diff from default.** For additions (most customisations) the
   stock behavior is "absent". For modified stock files, describe the delta
   from reading; where useful, fetch the stock version from the package
   (`dpkg`) to show the exact change, otherwise note "modified stock file".
5. **Draft each entry**: Location / Purpose / Mechanism. The purpose is
   **inferred** from code, comments and context — always label it as inferred.
6. **User review (mandatory).** Present the draft entry by entry; the user
   confirms or corrects each purpose/mechanism. Never present an inferred
   purpose as confirmed fact. Only user-confirmed entries are final.
7. **Render.** Markdown, grouped by category (systemd, scripts, config,
   kernel/boot, repos, graphics/drivers, autostart), each entry Location /
   Purpose / Mechanism. A header carries the system context (distribution,
   kernel, hardware model) so readers know how applicable it is.
8. **Write to `~/.distro-drift/`** (e.g. `customisations.md`). Create the
   directory if needed; never write into a system directory. (Per-tool
   dot-directory convention, like `~/.ssh` or `~/.gnupg`; the XDG Base
   Directory Specification would prefer `~/.local/share/distro-drift/` — a
   one-line change if the user ever wants it.)

Safety: this flow only READS (snapshot, files, logs) and WRITES one report
file to a user-chosen path. Root-only (`0600`) files cannot be read by the
agent — ask the human to paste the content, or mark the entry "human to
provide". Never fabricate content.

## Safety boundary

The agent runs distro-drift and read-only diagnostics only. Allowed:

- `cat`, `ls`, `file`, `stat`, `head`, `tail`, `grep`, `find`, `du`, `df`
- `journalctl` (read-only)
- `systemctl status`, `show`, `is-active`, `is-enabled`, `list-unit-files`
- `dpkg -S`, `dpkg -l`
- `apt policy`, `apt-cache policy` (queries only — never `apt update`)
- `distro-drift --snapshots --json`, `distro-drift --diff A B --json`

Never: `apt install`/`upgrade`/`update`, `systemctl start`/`stop`/`enable`/
`disable`/`mask`, `rm`, `mv`, `chmod`, editing files, or anything under
`sudo`. Fixes are **proposed** by default; implementation help is given only
when the human explicitly asks for it, and state-changing commands are never
executed by the agent — the human applies them.
