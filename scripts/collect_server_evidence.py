"""Copy bounded diagnostic evidence from a STOPPED run, never modify its data.

This is a triage package, NOT a portable MATLAB checkpoint or full IQ archive.
Large/binary/linked files remain at source and are listed as omitted.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import stat
import sys
import zipfile

TEXT_SUFFIXES = {".csv", ".json", ".log", ".txt", ".yaml", ".yml", ".xml", ".md"}
IMAGE_SUFFIXES = {".png", ".svg"}
CHUNK = 1024 * 1024


def linked(path):
    info = path.lstat()
    return path.is_symlink() or bool(getattr(info, "st_file_attributes", 0) & 0x400)


def inventory(root):
    """Do not follow symlinks/junctions or read anything outside explicit roots."""
    for folder, directories, files in os.walk(root, followlinks=False):
        directories.sort()
        files.sort()
        for name in directories[:]:
            path = Path(folder) / name
            if linked(path):
                directories.remove(name)
                yield path, "linked_directory_not_copied"
        for name in files:
            path = Path(folder) / name
            yield path, "linked_file_not_copied" if linked(path) else ""


def identity(info):
    return info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns


def package(run, logs, output, max_file_bytes, max_total_bytes, include_images=False):
    run, output = Path(run).absolute(), Path(output).absolute()
    roots = [("run", run)] + [(f"logs/{index:02d}", Path(path).absolute()) for index, path in enumerate(logs, 1)]
    for _, root in roots:
        if linked(root) or not root.is_dir() or root.resolve() != root:
            raise ValueError("Use ordinary canonical directories, not junction/symlink roots: " + str(root))
        if output.resolve().is_relative_to(root.resolve()):
            raise ValueError("Write the package outside the source run/log folders.")
    if max_file_bytes <= 0 or max_total_bytes <= 0:
        raise ValueError("Positive evidence size limits are required.")
    if output.exists() or output.with_suffix(output.suffix + ".sha256").exists():
        raise FileExistsError("Preserve the existing package and use a new output filename.")
    output.parent.mkdir(parents=True, exist_ok=True)
    rows, total = [], 0
    # Reserve .zip exclusively. An interrupted ZIP is intentionally preserved;
    # only a ZIP containing manifest.json is a completed diagnostic package.
    with output.open("xb") as raw, zipfile.ZipFile(raw, "w", zipfile.ZIP_DEFLATED, allowZip64=True) as archive:
        for label, root in roots:
            for path, reason in inventory(root):
                relative = path.relative_to(root).as_posix()
                name = label + "/" + relative
                before = path.lstat()
                row = dict(path=name, source=str(path), bytes=before.st_size, status="omitted", reason=reason)
                rows.append(row)
                if reason:
                    continue
                if not stat.S_ISREG(before.st_mode):
                    row["reason"] = "not_regular_file"
                    continue
                # Do not collect deployment credentials or private keys.
                if path.name.startswith(".env") or path.suffix.lower() in {".key", ".pem", ".pfx"}:
                    row["reason"] = "private_configuration_excluded"
                    continue
                allowed = TEXT_SUFFIXES | (IMAGE_SUFFIXES if include_images else set())
                if path.suffix.lower() not in allowed:
                    row["reason"] = "binary_or_non_diagnostic_extension"
                    continue
                if before.st_size > max_file_bytes:
                    row["reason"] = "per_file_limit"
                    continue
                if total + before.st_size > max_total_bytes:
                    row["reason"] = "total_limit"
                    continue
                value = hashlib.sha256()
                written = 0
                with path.open("rb") as source, archive.open(name, "w", force_zip64=True) as target:
                    if identity(os.fstat(source.fileno())) != identity(before):
                        raise ValueError("Source changed before packaging: " + str(path))
                    for chunk in iter(lambda: source.read(CHUNK), b""):
                        written += len(chunk)
                        if written > before.st_size:
                            raise ValueError("Source grew while packaging: " + str(path))
                        value.update(chunk)
                        target.write(chunk)
                    if (identity(os.fstat(source.fileno())) != identity(before) or
                            identity(path.stat()) != identity(before) or written != before.st_size):
                        raise ValueError("Source changed while packaging: " + str(path))
                total += written
                row.update(status="included", reason="", sha256=value.hexdigest())
        manifest = dict(schema="SixGRServerDiagnosticPackage/v1", created_utc=datetime.now(timezone.utc).isoformat(),
                        scope="bounded_diagnostics_not_full_evidence_not_resumable_checkpoint",
                        source_run=str(run), source_log_folders=[str(path) for path in logs],
                        source_must_be_stopped=True, source_mutated=False,
                        max_file_bytes=max_file_bytes, max_total_bytes=max_total_bytes,
                        included_bytes=total, included_count=sum(r["status"] == "included" for r in rows),
                        omitted_count=sum(r["status"] == "omitted" for r in rows), files=rows)
        archive.writestr("manifest.json", json.dumps(manifest, indent=2))
    digest = hashlib.sha256()
    with output.open("rb") as source:
        for chunk in iter(lambda: source.read(CHUNK), b""):
            digest.update(chunk)
    # External checksum lets the receiving laptop verify the ZIP before opening.
    output.with_suffix(output.suffix + ".sha256").write_text(digest.hexdigest() + "\n", encoding="ascii")
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-folder", required=True)
    parser.add_argument("--log-folder", action="append", default=[])
    parser.add_argument("--output", required=True, help="New ZIP path, outside the input folders.")
    parser.add_argument("--max-file-mib", type=int, default=16)
    parser.add_argument("--max-total-mib", type=int, default=512)
    parser.add_argument("--include-images", action="store_true")
    parser.add_argument("--confirm-stopped", action="store_true", required=True)
    args = parser.parse_args()
    result = package(args.run_folder, args.log_folder, args.output,
                     args.max_file_mib * CHUNK, args.max_total_mib * CHUNK, args.include_images)
    print(json.dumps({key: result[key] for key in ("scope", "included_count", "omitted_count", "included_bytes")}, indent=2))
    print("Package: " + args.output + " | checksum: " + args.output + ".sha256")
    print("Keep all source IQ/MAT/checkpoints and large CSVs; this package is triage only.")


if __name__ == "__main__":
    main()
