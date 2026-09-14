# Lossless evidence archive utility: implementation checkpoint

## Why this is needed

The frozen TDD campaign on `5debd387` completed two bounded invocations:
16 physical cases, two scheduled seeds, zero observed event errors, both
MATLAB exits 0. All 34 files from the first attempt remained hash-identical
after resume. This remains only 2/600 episodes per case, not qualification.

One raw attempt occupies 1,750,349,350 bytes. A diagnostic archive reduced
it to 134,360,257 bytes and verified all 34 restored member hashes. The
corresponding 600-episode extrapolation is about 80.6 GB archived versus
1.05 TB raw, before overhead and seed-dependent variation. This is a storage
measurement, not a waveform speedup or a campaign capacity guarantee.

## Implemented

`scripts/lossless_evidence_archive.py` provides create, verify and restore
operations. Policy lives in
`simulator/configs/validation/lossless_evidence_archive.yaml`.

- SHA-256 inventory before packing, full archive verification, then a second
  source inventory before publishing the completed manifest.
- Per-member byte count and hash verification on restore, plus archive hash
  checks. Existing source or destination files are never overwritten/deleted.
- Explicit rejection of incomplete containers, missing/unexpected members,
  corrupt/truncated frames, trailing data, path traversal, absolute paths,
  links/reparse points, duplicate/case-colliding names and file/directory
  collisions. Limits cover member count, decoded bytes and decoder window.
- Portable relative member names. File bytes are preserved, including MAT
  objects, complex numbers, NaNs, precision and embedded provenance. This is
  not a backup of filesystem ACLs/alternate streams or empty directories.
- Manifest scope is `lossless_container_not_PHY_attestation`; the codec cannot
  assert detector qualification or authenticate the scientific origin of input
  files. A source provenance audit is still required independently.

No receiver, waveform, power, channel, decoder or statistical setting changed.
The registered campaign checkout remains pinned at `5debd387`. The integration
branch now uses the previously idle PUCCH checkout; all older branch tips,
stopped-run logs and frozen evidence remain preserved.

## Verification evidence

- Sixteen Python tests pass, including declared byte fixtures and malformed
  containers; these are not RF observations.
- Initial MATLAB-launched focused run:
  `logs/testall_20260914T175309509Z_45fa68fd/` in the integration checkout.
  `testLosslessEvidenceArchive` passed (2.23 s),
  `testLosslessEvidenceArchiveMATLABRoundtrip` passed (11.35 s), and
  `testPUCCHDetectorCampaignAccounting` passed (3.15 s). This diagnostic
  dirty-tree run preceded the additional Windows reparse-attribute guard;
  all sixteen Python checks passed after that guard was added.
- The new utility created and restored all 34 files of the actual retained
  first episode, totaling 1,750,349,350 bytes. Native PowerShell independently
  matched every original and restored SHA-256 to the pre-resume snapshot.
  Local container/restored copies: `logs/evidence_archive_integration_01/`.
  Original files were not removed or modified.
- Both new MATLAB tests are registered in `testAll`. Final-source full
  regression and applicable explicit guards remain required; existing running
  older-revision suites cannot qualify this new utility.

## Usage

The optional utility and its full-suite tests require PyYAML and Zstandard.
Use the Python executable selected/reported by the simulator YAML preflight,
not an unrelated Python installation:

```powershell
& $pythonExe -m pip install -r scripts/requirements-evidence-archive.txt
```

Example create job (`job.json`; relative paths use the repository cwd):

```json
{
  "operation": "create",
  "input": "logs/example_completed_episode",
  "policy_path": "simulator/configs/validation/lossless_evidence_archive.yaml"
}
```

```powershell
& $pythonExe scripts/lossless_evidence_archive.py --config job.json --output logs/example_archive
```

To restore, use a job with `operation="restore"`, `input` pointing to the
container directory and `policy_path=null`. Supply a **new** output directory.
Restoration uses the archive's frozen policy, never caller overrides. Keep the
archive together with `manifest.json`; a partial container without its verified
manifest is deliberately unusable. Failed diagnostic outputs are preserved,
not silently retried or promoted.

## Still pending

This is an additive utility, not completed campaign-storage integration.
Campaign consumers still read raw MAT paths. Archive-aware resolution, bounded
restore caching, new-episode retention policy, portable CSV artifact bindings
and crash/restart integration must be implemented and verified before raw
storage can be replaced in that workflow. No automatic retention/deletion has
been enabled. Independent detector qualification, all-measurement closure,
integrated 12 dB acceptance and qualified-main promotion remain open.
