This repository hosts *non-proprietary* binary resources

## `makefile/`

`makefile/Makefile-pmas.toml` is PMAS cross-compilation tooling, targeting
static musl. It is the default.

`makefile/Makefile-pmas-glibc.toml` is the same thing for
`armv7-unknown-linux-gnueabihf`, and it is opt-in. It exists so musl is a choice
rather than the only thing that builds, and so `LD_PRELOAD`, `perf`, and
`gdbserver` work against the Elmo SDK, none of which they do against a static
musl binary. It needs no compiler: `rust-lld` links a pure-Rust build directly
against the 6.7 MB sysroot in `gm/armv7l-linux-gnueabihf-sysroot/`, on Windows
and on Linux alike. See `docker/glibc-sysroot/README.md` for the version window
that sysroot has to sit in, and for when to prefer it.

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

A consumer cannot download this block, because it is what does the downloading.
So it is copied by hand — which means it must stay small, and it must announce
when it goes stale. It does one thing, fetch `Makefile-pmas.toml`; everything
else lives in the file it fetches, which is downloaded rather than copied.

That includes the drift check. The bootstrap sets `PMAS_BOOTSTRAP_VERSION`, and
`check_bootstrap` in `Makefile-pmas.toml` compares it:

```text
warning: the PMAS bootstrap in Makefile.toml is v2; res publishes v3.
warning: re-copy makefile/pmas-bootstrap.ds from globusmedical/res into [config] load_script.
```

Unset is silent, not stale — either a pre-v2 bootstrap, which self-reports, or a
crate whose makefile chain has no bootstrap. It warns rather than fails, so an
offline build is never blocked.

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

Commit the downloaded `makefile/Makefile.toml` too — it is the offline fallback,
and committing it turns an upstream change into a reviewable diff.

`load_script` runs only from the directory holding that `Makefile.toml`. Crates
that `extend` the downloaded file directly never refresh it, so the committed
copy is what their builds use.

#### Changing the bootstrap

Edit `makefile/pmas-bootstrap.ds`, bump the version it sets, and set both
`makefile/pmas-bootstrap.version` and `expected` in the `check_bootstrap` task
to match. Every consumer still on the old version starts warning on its next
build; none of them break.

`pmas-bootstrap.version` exists only for bootstraps predating v2, which fetch it
directly. Keep it in step so those copies still report themselves.
