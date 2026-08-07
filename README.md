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
