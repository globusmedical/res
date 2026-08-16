This repository hosts *non-proprietary* binary resources

## `makefile/`

`makefile/Makefile-pmas.toml` is PMAS cross-compilation tooling. It is the
only build-task file left here.

The GEM build-task set that used to live alongside it
(`Makefile-gem.toml`, `gem-builder-compat.toml`, `gem-docker-run.sh`) is gone.
Consumer repositories no longer vendor a copy of it: they resolve a versioned
`gem-build` binary published by `gm-ethercat-master` instead, so the GEM build
surface is now a version number rather than a set of files kept in sync by
hand. See `gm-ethercat-master/docs/plans/build-layer-architecture.md` (phase
P6) for the reasoning, and `rs-gm_mctrl/makefile/gem-bootstrap.mjs` for how a
consumer resolves the binary.

`gem-builder-compat.toml` still exists, but it is consumer data — it records
which GEM OS release a given `gm_mctrl_gem` version needs — so it lives in the
consumer repository next to the crate it describes, not here.

### The bootstrap

`makefile/Makefile-pmas.toml` is pulled in by a short duckscript block that each
consumer runs from `[config] load_script` in its root `Makefile.toml`.
`makefile/pmas-bootstrap.ds` is the canonical text of that block, and
`makefile/pmas-bootstrap.version` is the version it currently stands at.

That block is the one thing a consumer cannot download from here, because it is
what does the downloading. So it is copied by hand, and the usual consequence
followed: four copies across `maverick` and `rs-gm_mctrl` drifted, and all four
carried the same defect — an age check reading a `${current_time}` that
duckscript never defines, which aborted the script before the download and
pinned every checkout to its first fetch. Fixing it meant finding and editing
each copy.

Copies are unavoidable here, but silent copies are not — and a copy that every
PMAS repository carries should be as small as it can be. The bootstrap does one
thing: fetch `Makefile-pmas.toml`. Everything else lives in the file it fetches,
which is downloaded rather than copied and so costs consumers nothing.

That includes the drift check. The bootstrap sets `PMAS_BOOTSTRAP_VERSION`; the
`check_bootstrap` task in `Makefile-pmas.toml` compares it against the version
that file expects and warns when a copy has fallen behind:

```text
warning: the PMAS bootstrap in Makefile.toml is v1 or older; res publishes v2.
warning: re-copy makefile/pmas-bootstrap.ds from globusmedical/res into [config] load_script.
```

A bootstrap predating v2 does not set the variable at all, which the check
reports as `v1 or older`. It warns rather than fails: a stale bootstrap still
fetches this file correctly, and an offline build must not break on a version
comparison.

This is the same trade the GEM build surface makes above: what cannot stop being
duplicated should at least be reduced to a version number — and, here, to ten
lines.

#### Adding a consumer

Paste `makefile/pmas-bootstrap.ds` verbatim into `[config] load_script` in the
repository's root `Makefile.toml`, and `extend` the file it writes:

```toml
extend = "makefile/Makefile.toml"

[config]
load_script = '''
<contents of makefile/pmas-bootstrap.ds>
'''
```

Commit the downloaded `makefile/Makefile.toml` as well. It is the fallback when
the download fails, and committing it makes an upstream change show up as a diff
rather than as a silent behaviour change.

Note that `load_script` runs only when `cargo make` is invoked from the
directory holding that `Makefile.toml`. A repository whose crates each carry
their own loader refreshes per crate; one where crates `extend` the downloaded
file directly never refreshes from those directories at all, and the committed
copy is what those builds use.

#### Changing the bootstrap

Edit `makefile/pmas-bootstrap.ds`, bump the version it sets, and set both
`makefile/pmas-bootstrap.version` and `expected` in the `check_bootstrap` task
to match. Every consumer still on the old version starts warning on its next
build; none of them break.

`pmas-bootstrap.version` exists only for bootstraps predating v2, which fetch it
directly. Keep it in step so those copies still report themselves.
