This repository hosts *non-proprietary* binary resources

## `makefile/`

`makefile/Makefile-gem.toml`, `makefile/gem-builder-compat.toml`, and
`makefile/gem-docker-run.sh` are the canonical GEM build-task set for
consumer repositories (e.g. `rs-gm_mctrl`). Consumers vendor a git-tracked
copy pulled from here deliberately — there is no automatic sync, so a
consumer's copy only changes when someone pulls an update on purpose.

This is a transitional arrangement: per
`gm-ethercat-master/docs/plans/build-layer-architecture.md` (phase P6), these
files are planned to be replaced by a versioned `gem-build` binary owned by
`gm-ethercat-master`, removing the need for this directory.

`makefile/Makefile-pmas.toml` is unrelated PMAS cross-compilation tooling and
is out of scope for that migration.
