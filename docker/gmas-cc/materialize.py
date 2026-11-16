"""Copy a Cygwin install tree, replacing Cygwin symlinks with real files.

Cygwin 1.7 stores a symlink as an ordinary file holding "!<symlink>" followed by
the UTF-16 target path. Only cygwin1.dll understands them; ld and every native
tool sees a 40-byte file, so they must be dereferenced before the sysroot can be
used outside Cygwin. Symlinks whose target is missing are dropped.

Runs under Debian 8's Python 3.4.
"""
import os
import shutil
import sys

MAGIC = b"!<symlink>"


def link_target(path):
    if os.path.getsize(path) > 4096:
        return None
    with open(path, "rb") as f:
        data = f.read()
    if not data.startswith(MAGIC):
        return None
    raw = data[len(MAGIC):]
    if raw.startswith(b"\xff\xfe"):
        txt = raw[2:].decode("utf-16-le")
    else:
        txt = raw.decode("utf-8")
    return txt.rstrip("\x00")


def resolve(path, depth=0):
    if depth > 20:
        raise RuntimeError("symlink loop at %s" % path)
    if not os.path.isfile(path):
        return path
    tgt = link_target(path)
    if tgt is None:
        return path
    if tgt.startswith("/"):
        raise RuntimeError("absolute symlink %s -> %s" % (path, tgt))
    return resolve(os.path.normpath(os.path.join(os.path.dirname(path), tgt)), depth + 1)


def copy_tree(src, dst):
    for root, _dirs, files in os.walk(src):
        out = os.path.join(dst, os.path.relpath(root, src))
        if not os.path.isdir(out):
            os.makedirs(out)
        for fn in files:
            shutil.copy2(os.path.join(root, fn), os.path.join(out, fn))


def main(src, dst):
    links = dropped = 0
    for root, _dirs, files in os.walk(src):
        out = os.path.join(dst, os.path.relpath(root, src))
        if not os.path.isdir(out):
            os.makedirs(out)
        for fn in files:
            s = os.path.join(root, fn)
            real = resolve(s)
            if real != s:
                links += 1
                if os.path.isdir(real):
                    copy_tree(real, os.path.join(out, fn))
                    continue
                if not os.path.exists(real):
                    dropped += 1
                    print("dropping dangling symlink %s" % os.path.relpath(s, src))
                    continue
            shutil.copy2(real, os.path.join(out, fn))
    print("dereferenced %d Cygwin symlinks, dropped %d dangling" % (links, dropped))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
