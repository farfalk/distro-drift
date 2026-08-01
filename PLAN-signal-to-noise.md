# Work plan: signal-to-noise fixes in `distro-drift`

**Context.** A first real-world run on a Linux Mint 22.3 laptop produced a
6472-line report. Roughly 4000 of those lines are noise concentrated in three
places, burying findings that matter. This plan fixes that.

**Scope.** Three independent tasks, T1–T3. Each is a separate commit. They do
not depend on each other and may be done in any order, but T4 (release) comes
last.

**Read `AGENTS.md` first.** In particular the output-format invariant: users
diff reports across months, so section and subsection labels are an API.

---

## T1 — Filter `apt-forktracer` output in section 2

### Problem

`apt-forktracer` reports every package whose installed version is not the
highest available across all configured sources. On a system with
`-updates`, `-security` and `-backports` enabled, that is nearly every package.

Measured on the reference report:

| Origin in output | Lines | Verdict |
|---|---|---|
| `[Ubuntu:` or `[linuxmint:` only | 3623 | noise |
| third-party origin (`[NVIDIA:`, `[Docker:`, `[Valve…`, `[obs:` …) | ~90 | signal |
| no origin at all (external `.deb`, locally built) | 6 | **highest signal** |

The last group — packages apt cannot see in any repository — is what actually
breaks a release upgrade, and it is invisible at 4107 lines.

### Required behaviour

Split the `apt-forktracer` output into three labelled groups, in this order:

1. `Packages with no known origin (external .deb or locally built)` — lines
   with no `[Origin: ...]` bracket at all. These are unrecoverable on upgrade.
2. `Packages from third-party origins` — lines whose bracket set contains at
   least one origin that is **not** `Ubuntu` and not `linuxmint`.
3. A single summary line for the rest, e.g.
   `(3623 further packages differ only in version within official repos — hidden)`

Add `--verbose` / `-v` as a new global flag that suppresses the hiding in
group 3 and prints everything. Default is hidden.

Apply the same three-way grouping to the fallback heuristic used when
`apt-forktracer` is absent, so both paths look the same.

### Acceptance criteria

- On the reference report input, section 2 shrinks from ~4110 lines to under 120.
- All 6 no-origin packages appear, under group 1.
- `-v` restores the full listing.
- The three group labels are new `--- ... ---` subsections; the section heading
  `2. Packages not from official repositories` is unchanged.
- `--help` documents `-v`.
- New test in `tests/cli.bats` asserting `-v` is accepted and does not error.

### Notes

`apt-forktracer` output lines look like:

```
  libvulkan1 (1.3.275.0-1build1) [Ubuntu: 1.3.275.0-1build1]
  containerd.io (2.2.6-1~ubuntu.24.04~noble) [Docker: 2.2.6-1~... 1.6.28-2]
  zotero (9.0.6)
```

Parse the bracket names with something like `grep -oE '\[[A-Za-z][A-Za-z ]*:'`.
Do not attempt to parse versions.

---

## T2 — Extend the noise filter for section 4

### Problem

Three families of legitimately-generated files dominate the unowned-file
listing and hide real findings:

| Pattern | Count in reference run | What it is |
|---|---|---|
| `/etc/netplan/90-NM-*.yaml` | 17 | one per network NetworkManager has seen |
| `/usr/local/share/locale/*/LC_MESSAGES/*.mo` | ~300 | from a `make install` of a library |
| `/usr/share/X11/xorg.conf.d/11-nvidia-*.conf` | 1 | written by `gpu-manager` at boot |

The third one is worse than noise: it is currently labelled `HAND-ADDED` in
section 8, which is actively wrong.

### Required behaviour

Add to the `write_noise_filter` heredoc:

```
^/etc/netplan/90-NM-[0-9a-f-]+\.yaml$
^/usr/local/share/locale/
^/usr/local/(share/man|lib/pkgconfig)/
^/etc/ssh/ssh_host_
```

In section 8, add a third state alongside `package:` and `HAND-ADDED`:
`generated (gpu-manager)` for files matching
`/usr/share/X11/xorg.conf.d/1[01]-nvidia-(prime|offload)\.conf`.

### Acceptance criteria

- Section 4 `/etc` and `/usr/local` listings shrink by the counts above.
- `11-nvidia-offload.conf` is no longer labelled `HAND-ADDED`.
- Files added by the user under `/usr/local/bin` still appear — verify with
  the reference finding `/usr/local/bin/asusctl-next-aura.sh`.
- Add a comment above the new patterns explaining *why* each is noise. A future
  maintainer must be able to tell a deliberate exclusion from an accidental one.

### Do not

Do not filter `/etc/sddm.conf*`, `/etc/X11/default-display-manager`, or
`*.dpkg-tmp`. Those are leftovers from an uninstalled desktop environment and
are exactly what the tool exists to surface.

---

## T3 — Per-section line counts

### Problem

Nothing tells the reader which sections are worth opening. A 6472-line file
gives no landmarks.

### Required behaviour

Emit a summary immediately after the header block (before section 1), listing
each requested section with the number of content lines it produced:

```
Section summary:
   1  Third-party software sources                      163 lines
   2  Packages not from official repositories           118 lines
   ...
```

Implementation constraint: sections write directly to stdout, so counts are not
known in advance. Buffer each section body to a file in `$TMP`, count, then
emit the summary followed by the concatenated bodies. Do not restructure the
section bodies themselves.

### Acceptance criteria

- Summary appears once, after the header, before section 1.
- Counts match the actual body line count of each section.
- `-s 4` produces a summary with one entry.
- Section bodies are byte-identical to before this change, so historical diffs
  of section content still work.
- The summary block itself is excluded by the `strip()` filter in `--diff`
  (line counts change constantly and would mask real drift).

---

## T4 — Release

Only after T1–T3 are merged and `make check` passes.

- Bump `VERSION` to `1.1.0` (new flag `-v`, changed output — minor bump).
- Move the `[Unreleased]` entries in `CHANGELOG.md` under `## [1.1.0] - <date>`.
- Note explicitly in the CHANGELOG that section 2 and section 4 output changed,
  so reports from 1.0.x will show large spurious diffs against 1.1.0 ones.
- Tag `v1.1.0`.

---

## Out of scope

Do not attempt these as part of this plan; they are separate decisions.

- Machine-readable output (`--json`). Worth doing, needs its own design.
- Snapshot rotation / pruning.
- Rewriting section 4 to use `cruft-ng` rulesets instead of the local filter.
- Supporting non-Debian package managers.

## Verification before handing back

Run on a real Debian-family system, not only in CI:

```sh
make check
sudo ./distro-drift > /tmp/new.txt
wc -l /tmp/new.txt                     # expect a large drop from 6472
sudo ./distro-drift -s 2 -v | wc -l    # expect the old volume back
sudo ./distro-drift -s 4 | grep asusctl-next-aura   # signal survived
```
