"""Byte-exact evidence containers, not PHY execution or qualification.

Python API: create(source, output, policy), verify(container), restore(container, output).
The CLI accepts a JSON/YAML job config and an output directory only. Sources
and existing outputs are never overwritten or deleted. A manifest is published
only after a complete archive verification. Failed outputs remain incomplete.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import sys
import tarfile

import yaml
import zstandard as zstd


class ArchiveError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise ArchiveError(message)


def _unique_pairs(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, f"Duplicate configuration key: {key}")
        result[key] = value
    return result


class _UniqueLoader(yaml.SafeLoader):
    pass


def _yaml_mapping(loader, node):
    return _unique_pairs((loader.construct_object(k), loader.construct_object(v))
                         for k, v in node.value)


_UniqueLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _yaml_mapping)


def read_config(path):
    text = Path(path).read_text(encoding="utf-8-sig")
    value = (json.loads(text, object_pairs_hook=_unique_pairs) if Path(path).suffix == ".json"
             else yaml.load(text, Loader=_UniqueLoader))
    require(type(value) is dict, "Configuration must be one mapping")
    return value


def validate_policy(policy):
    bounds = {"compression_level": (1, 19), "window_log": (10, 27), "threads": (0, 16),
              "read_block_bytes": (4096, 16 * 1024 * 1024),
              "max_total_bytes": (1, 2**53 - 1), "max_members": (1, 100000)}
    fields = set(bounds) | {"schema_version", "research_class", "codec", "retain_source_files"}
    require(type(policy) is dict and set(policy) == fields, "Missing or unknown archive policy fields")
    require(type(policy["schema_version"]) is int and policy["schema_version"] == 1,
            "Expected archive schema_version 1")
    require(policy["research_class"] == "optional_research_experiment" and policy["codec"] == "tar_zstd",
            "Expected explicitly labeled tar_zstd evidence experiment")
    require(policy["retain_source_files"] is True, "This utility never removes source files")
    for key, (low, high) in bounds.items():
        require(type(policy[key]) is int and low <= policy[key] <= high,
                f"{key} must be an integer in [{low}, {high}]")


def safe_name(name):
    require(type(name) is str and bool(name), "Empty or non-text archive member")
    path = PurePosixPath(name)
    require(not path.is_absolute() and path.as_posix() == name, "Noncanonical archive member")
    reserved = {"con", "prn", "aux", "nul"} | {f"{prefix}{n}" for prefix in ("com", "lpt") for n in range(1, 10)}
    for part in path.parts:
        require(part not in (".", "..") and not part.endswith((".", " ")) and
                not any(ord(c) < 32 or c in '<>:"\\|?*' for c in part) and
                part.split(".")[0].casefold() not in reserved, "Unsafe or nonportable archive member")
    return name


def digest(path, block=1024 * 1024):
    result = hashlib.sha256()
    with Path(path).open("rb") as source:
        for data in iter(lambda: source.read(block), b""):
            result.update(data)
    return result.hexdigest()


def _link(path):
    # Check reparse attributes too: Path.is_junction is absent before Python
    # 3.12, while Windows junctions must never bypass the no-links rule.
    attributes = getattr(path.lstat(), "st_file_attributes", 0)
    return path.is_symlink() or bool(attributes & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400))


def inventory(root, policy):
    root = Path(root)
    require(root.is_dir() and not _link(root), "Source must be an ordinary directory")
    rows = []
    for parent, directories, files in os.walk(root, followlinks=False):
        for name in directories + files:
            require(not _link(Path(parent) / name), "Links/junctions are forbidden in evidence sources")
        for name in files:
            path = Path(parent) / name
            require(path.is_file(), "Evidence members must be regular files")
            rows.append({"path": safe_name(path.relative_to(root).as_posix()),
                         "bytes": path.stat().st_size, "sha256": digest(path, policy["read_block_bytes"])})
    rows.sort(key=lambda row: row["path"])
    validate_records(rows, policy)
    return rows


def validate_records(rows, policy):
    require(type(rows) is list and 0 < len(rows) <= policy["max_members"], "Invalid archive member count")
    names = set()
    total = 0
    for row in rows:
        require(type(row) is dict and set(row) == {"path", "bytes", "sha256"}, "Invalid member record")
        name = safe_name(row["path"])
        require(name.casefold() not in names, "Duplicate or case-colliding archive member")
        names.add(name.casefold())
        require(type(row["bytes"]) is int and row["bytes"] >= 0, "Invalid member byte count")
        require(type(row["sha256"]) is str and re.fullmatch("[0-9a-f]{64}", row["sha256"]), "Invalid member SHA-256")
        total += row["bytes"]
    require(total <= policy["max_total_bytes"], "Archive exceeds configured uncompressed byte limit")
    # A file must not also be the parent directory of another file.
    for name in names:
        require(not any(parent.as_posix().casefold() in names for parent in PurePosixPath(name).parents
                        if parent.as_posix() != "."), "File/directory member collision")


def _walk_archive(archive, records, policy, destination=None):
    expected = {row["path"]: row for row in records}
    seen = set()
    # The producer emits at most a small PAX header per ordinary file.
    # Bound decompressed tar framing as well as the actual file data.
    budget = policy["max_total_bytes"] + policy["max_members"] * 65536 + 10240
    with Path(archive).open("rb") as source:
        # Unlike stream_reader, decompressobj exposes completion of the frame.
        # Feed small compressed chunks to bound expansion before the byte-limit
        # check. A zstd block expands to at most 128 KiB; 1 KiB input keeps
        # even highly compressible multi-block chunks bounded in memory.
        decoder = zstd.ZstdDecompressor(max_window_size=2**policy["window_log"]).decompressobj()
        class BoundedReader:
            consumed = 0
            pending = b""

            def read(self, size=-1):
                require(size >= 0, "Unbounded tar read forbidden")
                while len(self.pending) < size and not decoder.eof:
                    compressed = source.read(1024)
                    require(bool(compressed), "Truncated zstd frame")
                    data = decoder.decompress(compressed)
                    self.consumed += len(data)
                    require(self.consumed <= budget, "Decompressed archive exceeds byte budget")
                    self.pending += data
                    if decoder.eof:
                        require(not decoder.unused_data and not source.read(1), "Trailing compressed data")
                result, self.pending = self.pending[:size], self.pending[size:]
                return result

        reader = BoundedReader()
        with tarfile.open(fileobj=reader, mode="r|") as tar:
            for member in tar:
                name = safe_name(member.name)
                require(member.isfile() and name in expected and name not in seen,
                        "Unexpected, duplicate or non-regular archive member")
                row = expected[name]
                require(member.size == row["bytes"], "Archive member size mismatch")
                target = None
                if destination is not None:
                    target_path = destination.joinpath(*PurePosixPath(name).parts)
                    target_path.parent.mkdir(parents=True, exist_ok=True)
                    require(target_path.parent.resolve().is_relative_to(destination.resolve()), "Restore escaped output root")
                    target = target_path.open("xb")
                h = hashlib.sha256()
                size = 0
                try:
                    with tar.extractfile(member) as payload:
                        for data in iter(lambda: payload.read(policy["read_block_bytes"]), b""):
                            size += len(data)
                            h.update(data)
                            if target is not None:
                                target.write(data)
                finally:
                    if target is not None:
                        target.close()
                require(size == row["bytes"] and h.hexdigest() == row["sha256"], "Restored member hash mismatch")
                seen.add(name)
            # Inspect tar's read-ahead buffer too, not only its underlying
            # reader: unmanifested bytes after the end marker must not hide
            # inside an already-prefetched block. Canonical padding is zero.
            for padding in iter(lambda: tar.fileobj.read(policy["read_block_bytes"]), b""):
                require(not any(padding), "Unmanifested trailing tar data")
    require(seen == set(expected), "Archive is missing required members")


def create(source, output, policy):
    validate_policy(policy)
    require(not _link(Path(source)), "Source directory cannot be a link/junction")
    source, output = Path(source).resolve(), Path(output).resolve()
    require(not output.is_relative_to(source), "Archive output cannot be inside its source")
    records = inventory(source, policy)
    output.mkdir(parents=True, exist_ok=False)
    archive = output / "evidence.tar.zst"
    params = zstd.ZstdCompressionParameters.from_level(policy["compression_level"],
                                                      window_log=policy["window_log"], threads=policy["threads"])
    with archive.open("xb") as destination:
        with zstd.ZstdCompressor(compression_params=params).stream_writer(destination, closefd=False) as encoder:
            with tarfile.open(fileobj=encoder, mode="w|") as tar:
                for row in records:
                    tar.add(source / row["path"], arcname=row["path"], recursive=False)
    _walk_archive(archive, records, policy)
    require(inventory(source, policy) == records, "Source changed while archiving; no manifest published")
    manifest = {"schema_version": 1, "scope": "lossless_container_not_PHY_attestation",
                "archive_sha256": digest(archive), "policy": policy, "members": records,
                "zstandard_version": zstd.__version__, "source_files_removed": False,
                "detector_qualified": False}
    with (output / "manifest.json").open("x", encoding="utf-8") as destination:
        json.dump(manifest, destination, indent=2)
    return manifest


def _manifest(container):
    container = Path(container)
    require((container / "manifest.json").stat().st_size <= 16 * 1024 * 1024, "Manifest too large")
    manifest = read_config(container / "manifest.json")
    require(set(manifest) == {"schema_version", "scope", "archive_sha256", "policy", "members",
                             "zstandard_version", "source_files_removed", "detector_qualified"}, "Invalid manifest fields")
    require(type(manifest["schema_version"]) is int and manifest["schema_version"] == 1 and
            manifest["scope"] == "lossless_container_not_PHY_attestation" and
            manifest["source_files_removed"] is False and manifest["detector_qualified"] is False,
            "Archive metadata cannot assert source removal or PHY qualification")
    validate_policy(manifest["policy"])
    validate_records(manifest["members"], manifest["policy"])
    require(digest(container / "evidence.tar.zst") == manifest["archive_sha256"], "Archive SHA-256 mismatch")
    return manifest


def verify(container):
    manifest = _manifest(container)
    _walk_archive(Path(container) / "evidence.tar.zst", manifest["members"], manifest["policy"])
    return manifest


def restore(container, output):
    # Reject corruption before creating any output files.
    manifest = verify(container)
    output = Path(output).resolve()
    output.mkdir(parents=True, exist_ok=False)
    _walk_archive(Path(container) / "evidence.tar.zst", manifest["members"], manifest["policy"], output)
    require(inventory(output, manifest["policy"]) == manifest["members"], "Restored tree differs from manifest")
    require(digest(Path(container) / "evidence.tar.zst") == manifest["archive_sha256"], "Archive changed during restoration")
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    job = read_config(args.config)
    require(set(job) == {"operation", "input", "policy_path"}, "Expected operation, input and policy_path")
    if job["operation"] == "create":
        result = create(job["input"], args.output, read_config(job["policy_path"]))
    elif job["operation"] == "restore":
        require(job["policy_path"] is None, "Restoration uses the archive's frozen policy")
        result = restore(job["input"], args.output)
    else:
        raise ArchiveError("operation must be create or restore")
    print(json.dumps({"status": "passed", "file_count": len(result["members"]),
                      "scope": result["scope"], "new_RF_episodes": 0, "detector_qualified": False}))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"EVIDENCE_ARCHIVE_FAILED: {type(error).__name__}: {error}", file=sys.stderr)
        raise
