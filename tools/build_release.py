#!/usr/bin/env python3
from pathlib import Path
import shutil
import zipfile

ROOT = Path(__file__).resolve().parent.parent
VERSION = "1.0.0"
PREFIX = f"sticky-blood-v{VERSION}"
OUTPUT = ROOT / "dist" / f"{PREFIX}.zip"

ROOT_FILES = [
    "addon.json",
    "install.bat",
    "install.sh",
    "uninstall.bat",
    "uninstall.sh",
    "README.md",
    "CHANGELOG.md",
    "LICENSE",
    "patches/v1.0.0.json",
    "tools/sticky_blood.py",
    "tools/sticky_blood.ps1",
]


def release_files():
    files = [ROOT / name for name in ROOT_FILES]
    files.extend(path for path in (ROOT / "lua").rglob("*") if path.is_file())
    return sorted(files)


def add_file(archive, path):
    relative = path.relative_to(ROOT).as_posix()
    destination = f"{PREFIX}/{relative}"
    info = zipfile.ZipInfo.from_file(path, destination)
    mode = 0o755 if path.name in {"install.sh", "uninstall.sh", "sticky_blood.py"} else 0o644
    info.external_attr = (mode & 0xFFFF) << 16
    with path.open("rb") as handle:
        archive.writestr(info, handle.read(), compress_type=zipfile.ZIP_DEFLATED)


def validate_names(names):
    forbidden = (
        ".cursor/",
        "agent-transcripts/",
        "cursor.md",
        "agents.md",
        "claude.md",
        ".plan.md",
        "__pycache__/",
    )
    for name in names:
        lower = name.lower()
        if lower.endswith((".dll", ".bak")):
            raise RuntimeError(f"Forbidden binary or backup in release: {name}")
        if any(token in lower for token in forbidden):
            raise RuntimeError(f"Forbidden metadata in release: {name}")


def main():
    files = release_files()
    missing = [str(path) for path in files if not path.is_file()]
    if missing:
        raise RuntimeError("Missing release file(s): " + ", ".join(missing))
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    temp = OUTPUT.with_suffix(".zip.tmp")
    temp.unlink(missing_ok=True)
    try:
        with zipfile.ZipFile(temp, "w") as archive:
            for path in files:
                add_file(archive, path)
        with zipfile.ZipFile(temp) as archive:
            names = archive.namelist()
            validate_names(names)
            bad = archive.testzip()
            if bad:
                raise RuntimeError(f"Corrupt ZIP entry: {bad}")
        shutil.move(temp, OUTPUT)
    finally:
        temp.unlink(missing_ok=True)
    print(OUTPUT)


if __name__ == "__main__":
    main()
