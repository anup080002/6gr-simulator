# Physical precoder projection and TDRA regression follow-up

## Cause and repair

`CoupledWaveformStream.queueData` applies an actual waveform-column to
physical-element matrix after data preparation. The applied-weight exporter
previously used the prepared matrix and required its row count to equal the
physical element count. This rejected the one-logical-port UE fixtures when
the actual shared transmitter projected that port onto multiple elements.

The owner now retains the exact projection used for its enqueued samples in
the private-set transmission ledger, published only after an active sample
has executed. The exporter composes that retained projection with the
prepared data matrix. It does not reconstruct a beam from PMI, pad weights,
change transmitted samples, or relax physical-domain checks. DL bundle
digests are still checked before composition. Exported matrix digests and
directivity samples refer to the composed physical-element matrix.

The shared PUSCH fixture now independently compares the composed matrix
against its actual mapped data symbols and reconstructs the decimal exported
weights exactly. This covers the existing one-port late-UCI/CSI paths and
the two-port variants whenever those fixtures execute.

`testGeometryMasterRuntimeAuthority` previously assumed that an unavailable
preferred allocation implied no resources, despite leaving other legal YAML
TDRA rows installed. It now checks selection of the first legal authored row
with unchanged PRBs and K0, then installs a catalog with no fitting row and
retains the zero-resource and explicit failure-reason assertions. No runtime
TDRA policy or gate was changed.

## Validation at this checkpoint

Follow-up: the complete five-test focused batch subsequently passed with
exit 0. See `projected_data_output_review_20260913.md` for final timings,
retained CSV/PNG evidence, independent checks and an open SINR plot-provenance
defect. The bullets below retain the earlier checkpoint chronology.

- `git diff --check`: passed.
- Beam CSV/provenance/rendering Python tests: 14 passed. These use previously
  retained captures; they do not qualify the new MATLAB projection path.
- New focused MATLAB batch is running in this development worktree:
  `%TEMP%/sixgr_physical_precoder_tdra_20260913_01.log`.
  Geometry runtime authority (50.76 s), baseline TDRA budget (21.18 s) and
  late-UCI delivery (226.32 s) have passed. Late CSI and executed DL matrix
  evidence are pending. The late-UCI test includes the new matrix-to-symbol
  and exact decimal-weight checks, then actual slot-10 reception delivered
  in slot 11. Its retained run is
  `%TEMP%/tpb7845fe8_6795_4560_8db8_48d441283e02`.
- A sequential validation job was launched on MATLAB source revision
  `ff00f0c1`: LLS/config, strict-mode, export/grant and both E2E guards first,
  followed by `testAll` even if the guard process fails. Logs are
  `%TEMP%/sixgr_projection_revision_guards_20260913.log` and
  `%TEMP%/sixgr_projection_revision_full_20260913.log`. At this update the
  guard process is live and the full suite is queued, not yet started.
  Results remain pending; no full-simulator or conformance PASS is claimed.
- The preceding development revision's six configuration/LLS guards passed
  (exit 0). The receiver revision's twelve guards, including both E2E tests,
  passed (exit 0). Neither substitutes for validation of this patch.

The original main and receiver full suites remain on unchanged source in
their own worktrees. Merge into main and removal of those worktrees are
deferred while they are in use. Their known old-revision failures remain in
the logs; those logs must not be rewritten or called passes.

The NR-validation, result-integrity and config-driven skills guided the
physical source-of-truth checks and separation of legal configured
alternatives from genuinely unavailable resources. Broader Type-2 receiver
integration, independent phase evidence, detector qualification, full output
audit and long impairment-enabled campaigns remain open.
