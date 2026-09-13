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

- `git diff --check`: passed.
- Beam CSV/provenance/rendering Python tests: 14 passed. These use previously
  retained captures; they do not qualify the new MATLAB projection path.
- New focused MATLAB batch is running in this development worktree:
  `%TEMP%/sixgr_physical_precoder_tdra_20260913_01.log`.
  Geometry runtime authority and baseline TDRA budget have passed; late UCI,
  late CSI and executed DL matrix evidence are pending.
- Required full-suite, LLS/config, export/grant and E2E runs on this changed
  revision remain pending. No full-simulator or conformance PASS is claimed.
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
