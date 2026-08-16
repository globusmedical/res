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

Copies are unavoidable here, but silent copies are not. The bootstrap embeds its
own `bootstrap_version` and compares it against `pmas-bootstrap.version` on each
run, so a copy that has fallen behind says so:

```text
warning: PMAS bootstrap in Makefile.toml is v1; res publishes v2.
warning: re-copy makefile/pmas-bootstrap.ds from globusmedical/res into [config] load_script.
```

The check is quiet when the fetch fails, so an offline build is never blocked by
it. This is the same trade the GEM build surface makes above: what cannot stop
being duplicated should at least be reduced to a version number.

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

To sync more than the PMAS task set, add entries to the `files` array as
`"remote name|local name"` rather than adding a second sync block.

#### Changing the bootstrap

Edit `makefile/pmas-bootstrap.ds`, bump `bootstrap_version` inside it, and set
`makefile/pmas-bootstrap.version` to match. Every consumer still on the old
version starts warning on its next build; none of them break.
