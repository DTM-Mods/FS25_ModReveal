"""Builds FS25_ModReveal.zip from the shipped files only (forward-slash paths, modDesc at the root)
and checks every entry against the source by SHA-256.
Usage: python -I tools\build_zip.py <out.zip>"""
import hashlib
import pathlib
import sys
import zipfile

project = pathlib.Path(__file__).resolve().parent.parent
out = pathlib.Path(sys.argv[1])

files = ["modDesc.xml", "icon_ModReveal.dds"]
files += sorted(p.relative_to(project).as_posix() for p in (project / "scripts").glob("*.lua"))
files += sorted(p.relative_to(project).as_posix() for p in (project / "translations").glob("*.xml"))

if out.exists():
    sys.exit(f"{out} already exists: move it out of the way first")

with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
    for name in files:
        zf.write(project / name, name)

with zipfile.ZipFile(out) as zf:
    names = zf.namelist()
    assert names == files, (names, files)
    for name in files:
        assert "\\" not in name
        if hashlib.sha256(zf.read(name)).digest() != hashlib.sha256((project / name).read_bytes()).digest():
            sys.exit(f"mismatch: {name}")
        if name.endswith(".lua"):
            assert len(zf.read(name)) <= 512 * 1024, f"{name} is over 0.5 MB"
    assert len(files) <= 128

print(f"{out} {out.stat().st_size:,} B, {len(files)} files, all match the source")
print("sha256", hashlib.sha256(out.read_bytes()).hexdigest())
for name in files:
    print("  " + name)
