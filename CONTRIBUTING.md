# Contributing

## Fork-based workflow

1. Fork, branch, commit, push, open a PR against `master`.
2. Run `make check` before pushing - shellcheck and bats must pass.
3. Keep changes minimal and focused. Match existing style.
4. Read [AGENTS.md](AGENTS.md) - it documents invariants that are easy to break by accident.

## AI-assisted contributions

This project accepts AI-assisted contributions under the following conditions.

### Disclosure

If you use AI tools to help write or modify code, **disclose this in your pull
request description**: which tool, what was generated, and how you verified it.
This helps reviewers apply appropriate scrutiny.

### Human accountability

All contributions must be submitted by a human who understands the changes and
is prepared to answer questions about them. The decision to include a
contribution is made by a human. AI agents may not open pull requests or push
commits directly.

You take full responsibility for every line you submit. If a maintainer asks why
a choice was made, the answer must never be "the AI did it."

### Scope

AI-generated changes should be **non-creative** - mechanical conversions,
small-scoped code completions, refactors, and boilerplate. This avoids
questions about copyright authorship and keeps the quality bar where it belongs.

### What stays the same

AI-assisted contributions must meet the same standards as any other: pass
`make check`, match existing style, and not break the invariants documented in
[AGENTS.md](AGENTS.md). Reviewers may ask you to explain any line.
