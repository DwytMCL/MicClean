#!/usr/bin/env python3
"""Zips module/ into a flashable Magisk module: dist/MicClean-<version>.zip"""
import os, re, zipfile
root = os.path.dirname(os.path.abspath(__file__))
mod = os.path.join(root, "module")
ver = re.search(r"^version=(\S+)", open(os.path.join(mod, "module.prop")).read(), re.M).group(1)
for d in ("lib", "lib64"):
    if not os.path.exists(os.path.join(mod, "system/vendor", d, "libmicclean_aurisys.so")):
        raise SystemExit("run native/build.sh first")
os.makedirs(os.path.join(root, "dist"), exist_ok=True)
out = os.path.join(root, "dist", f"MicClean-{ver}.zip")
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for r, _, files in os.walk(mod):
        for n in files:
            p = os.path.relpath(os.path.join(r, n), mod).replace(os.sep, "/")
            zi = zipfile.ZipInfo(p); zi.compress_type = zipfile.ZIP_DEFLATED
            zi.external_attr = (0o755 if p.endswith((".sh", "micclean", "update-binary")) else 0o644) << 16
            z.writestr(zi, open(os.path.join(r, n), "rb").read())
print(out)
