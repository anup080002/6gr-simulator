"""Declared byte/security fixtures only; never generated PHY observations."""
import copy
import hashlib
import io
import json
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import lossless_evidence_archive as archive
import zstandard as zstd


class ArchiveTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="sixgr_declared_archive_test_")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "source"
        (self.source / "nested").mkdir(parents=True)
        self.data = {"nested/complex_bytes.mat": bytes(range(256)) * 257,
                     "empty.csv": b"", "unicode_\u03b1.json": b'{"scope":"declared_unit_fixture"}'}
        for name, data in self.data.items():
            (self.source / name).write_bytes(data)
        repo = Path(__file__).resolve().parents[2]
        self.policy = archive.read_config(repo / "simulator/configs/validation/lossless_evidence_archive.yaml")
        self.container = self.root / "container"

    def make(self):
        return archive.create(self.source, self.container, self.policy)

    def change_manifest(self, callback):
        path = self.container / "manifest.json"
        manifest = json.loads(path.read_text())
        callback(manifest)
        path.write_text(json.dumps(manifest))

    def test_roundtrip_all_bytes_and_no_source_change(self):
        manifest = self.make()
        self.assertFalse(manifest["detector_qualified"])
        archive.verify(self.container)
        output = self.root / "restored"
        archive.restore(self.container, output)
        for name, data in self.data.items():
            self.assertEqual(data, (output / name).read_bytes())
            self.assertEqual(data, (self.source / name).read_bytes())

    def test_policy_rejections(self):
        for field, value in [("compression_level", True), ("window_log", 28),
                             ("threads", -1), ("retain_source_files", False),
                             ("max_members", 0), ("schema_version", True), ("unknown", 1)]:
            with self.subTest(field=field):
                bad = copy.deepcopy(self.policy)
                bad[field] = value
                with self.assertRaises(archive.ArchiveError):
                    archive.validate_policy(bad)

    def test_limits_before_output(self):
        for field, value in [("max_members", 1), ("max_total_bytes", 1)]:
            bad = dict(self.policy, **{field: value})
            with self.assertRaises(archive.ArchiveError):
                archive.create(self.source, self.container, bad)
            self.assertFalse(self.container.exists())

    def test_output_inside_source_and_existing_output_rejected(self):
        with self.assertRaises(archive.ArchiveError):
            archive.create(self.source, self.source / "archive", self.policy)
        self.make()
        before = archive.digest(self.container / "evidence.tar.zst")
        with self.assertRaises(FileExistsError):
            self.make()
        with self.assertRaises(FileExistsError):
            archive.restore(self.container, self.source)
        self.assertEqual(before, archive.digest(self.container / "evidence.tar.zst"))

    def test_link_source_rejected(self):
        with mock.patch.object(archive, "_link", return_value=True):
            with self.assertRaises(archive.ArchiveError):
                self.make()

    def test_windows_reparse_attribute_rejected(self):
        path = mock.Mock()
        path.is_symlink.return_value = False
        path.lstat.return_value.st_file_attributes = 0x400
        self.assertTrue(archive._link(path))

    def test_unsafe_names(self):
        for name in ("../escape", "/absolute", "C:/escape", "a\\b", "a//b", "a/./b",
                     "CON", "nul.mat", "a. ", "a:", "a\x00b", "a/../b"):
            with self.subTest(name=name), self.assertRaises(archive.ArchiveError):
                archive.safe_name(name)

    def test_manifest_collisions(self):
        for names in (("x", "X"), ("x", "x/y"), ("x", "x")):
            rows = [{"path": name, "bytes": 0, "sha256": hashlib.sha256(b"").hexdigest()} for name in names]
            with self.assertRaises(archive.ArchiveError):
                archive.validate_records(rows, self.policy)

    def test_corruption_rejected_before_restore_output(self):
        self.make()
        path = self.container / "evidence.tar.zst"
        raw = bytearray(path.read_bytes())
        raw[len(raw)//2] ^= 1
        path.write_bytes(raw)
        output = self.root / "restore"
        with self.assertRaises(archive.ArchiveError):
            archive.restore(self.container, output)
        self.assertFalse(output.exists())

    def test_member_digest_mismatch(self):
        self.make()
        self.change_manifest(lambda m: m["members"][0].update(sha256="0"*64))
        with self.assertRaises(archive.ArchiveError):
            archive.verify(self.container)

    def test_rehashed_truncated_or_appended_frame_rejected(self):
        self.make()
        path = self.container / "evidence.tar.zst"
        original = path.read_bytes()
        for raw in (original[:-1], original + b"trailing"):
            path.write_bytes(raw)
            self.change_manifest(lambda m: m.update(archive_sha256=hashlib.sha256(raw).hexdigest()))
            with self.assertRaises((archive.ArchiveError, zstd.ZstdError)):
                archive.verify(self.container)

    def test_declared_window_limit_enforced(self):
        self.make()
        self.change_manifest(lambda m: m["policy"].update(window_log=10))
        with self.assertRaises(zstd.ZstdError):
            archive.verify(self.container)

    def test_unmanifested_trailing_tar_bytes_rejected(self):
        self.make()
        path = self.container / "evidence.tar.zst"
        with path.open("rb") as source, zstd.ZstdDecompressor().stream_reader(source) as decoder:
            raw = decoder.read()
        encoded = zstd.ZstdCompressor().compress(raw + b"unmanifested payload")
        path.write_bytes(encoded)
        self.change_manifest(lambda m: m.update(archive_sha256=hashlib.sha256(encoded).hexdigest()))
        with self.assertRaises(archive.ArchiveError):
            archive.verify(self.container)

    def test_missing_unexpected_and_forged_qualification(self):
        self.make()
        original = (self.container / "manifest.json").read_text()
        for change in (lambda m: m["members"].pop(),
                       lambda m: m["members"][0].update(path="missing.mat"),
                       lambda m: m.update(detector_qualified=True)):
            (self.container / "manifest.json").write_text(original)
            self.change_manifest(change)
            with self.assertRaises(archive.ArchiveError):
                archive.verify(self.container)

    def test_actual_tar_links_and_duplicate_members_rejected(self):
        self.make()
        for kind in ("link", "duplicate"):
            raw = io.BytesIO()
            with tarfile.open(fileobj=raw, mode="w") as tar:
                member = tarfile.TarInfo("empty.csv")
                if kind == "link":
                    member.type = tarfile.SYMTYPE
                    member.linkname = "../outside"
                    tar.addfile(member)
                else:
                    tar.addfile(member, io.BytesIO(b""))
                    tar.addfile(member, io.BytesIO(b""))
            encoded = zstd.ZstdCompressor().compress(raw.getvalue())
            (self.container / "evidence.tar.zst").write_bytes(encoded)
            self.change_manifest(lambda m: m.update(archive_sha256=hashlib.sha256(encoded).hexdigest()))
            with self.assertRaises(archive.ArchiveError):
                archive.verify(self.container)

    def test_incomplete_and_duplicate_config_keys_rejected(self):
        self.container.mkdir()
        (self.container / "evidence.tar.zst").write_bytes(b"incomplete")
        with self.assertRaises(FileNotFoundError):
            archive.verify(self.container)
        for suffix, text in (("json", '{"x":1,"x":2}'), ("yaml", 'x: 1\nx: 2\n')):
            path = self.root / ("duplicate." + suffix)
            path.write_text(text)
            with self.assertRaises(archive.ArchiveError):
                archive.read_config(path)


if __name__ == "__main__":
    unittest.main(verbosity=2)
