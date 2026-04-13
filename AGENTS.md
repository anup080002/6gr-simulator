# Repository Guidance

These rules apply to every patch in this repository. If a requested change conflicts with them, resolve the conflict instead of papering over it.

## Core invariants

### Truth vs proxy separation
- Treat `truth` as replay or calibration backed by actual PHY execution.
- Treat `lut`, `logistic`, `fast_proxy`, `synthetic`, and `fallback` paths as approximations.
- Never relabel proxy output as truth in tables, manifests, or `Source`, `ExecutionBackend`, `ApproximationMode`, `E2EAirModel`, or `Notes` fields.
- Keep truth and proxy comparisons explicit. The acceptance references are `tests/testE2E_FastVsTruth.m`, `tests/testE2E_TruthPacketSemanticCampaign.m`, `tests/testStrictProxyGuards.m`, and `tests/testHybrid.m`.

### No fallback rows in primary result tables
- Primary tables must only contain rows backed by the mode that table claims to represent.
- If data is unavailable, leave the table empty, skip the artifact, or fail loudly. Do not inject synthetic or fallback rows just to preserve shape.
- This applies to `KPITable`, `SummaryTable`, `CheckTable`, `PacketIntegrityTable`, `FlowSummaryTable`, `BearerSummaryTable`, grant traces, HARQ tables, and similar primary exports.
- Any fallback-only rescue path must stay in explicitly marked debug or proxy artifacts and never become the primary exported view.

### Strict validation of channel profiles
- Bare `TDL` and `CDL` are model families, not concrete fading profiles. Accepted profiles must be concrete values such as `TDL-C` or `CDL-D`.
- `normalizeConfig` may backfill from a concrete legacy field, but it must not manufacture `channel.tdlProfile='TDL'` or `channel.cdlProfile='CDL'`.
- Keep `channel.model`, `channel.tdlProfile`, `channel.cdlProfile`, and `channel.fading.*` aligned with `+sixgr/+config/normalizeConfig.m` and `+sixgr/+config/validateConfig.m`.

### No scalar full-grid channel estimates on fading channels
- For TDL, CDL, or any small-scale fading path, do not expand a single scalar estimate across the whole resource grid and present it as `Hest`.
- The pattern `ones(size(rxGrid)) .* hScalar` is only acceptable for explicit AWGN or unit-channel shortcuts.
- Fading paths must use per-resource estimates or fall back to `nrChannelEstimate`.
- Review `+sixgr/+phy/+rx/channelEstimate.m`, `+sixgr/+phy/+ul/PUSCH_Rx.m`, `+sixgr/+phy/+ul/PUCCH_Rx.m`, and SRS callers when changing fast paths or MEX wrappers.

### No fake grant-level TBS exports
- Grant-level `TBSBits` and `TBSBytes` must come from real grants, real transport blocks, or directly derived PHY allocations.
- Do not synthesize grant-level TBS from slot aggregates, served-bit counters, or fast-kernel approximations.
- Rows tagged like `synthetic_from_fast_kernel*`, `GrantReason=fast_proxy*`, or similar synthetic reconstructions must never be promoted into primary grant-level exports.
- Preserve the distinction between aggregate proxy metrics and grant-level truth. `tests/testSchedulerGrantConsistency.m` is the minimum guard.

## Required tests after any patch
- Always run:
  `matlab -batch "setup6GRSimToolkit('Verbose',false); testAll"`
- If the patch touches truth/proxy separation, E2E summaries, manifests, exports, or grant traces, also run:
  `matlab -batch "setup6GRSimToolkit('Verbose',false); testE2E_FastVsTruth; testE2E_TruthPacketSemanticCampaign"`
- If the patch touches config normalization, config validation, channel models or profiles, or channel-estimation code, also run:
  `matlab -batch "setup6GRSimToolkit('Verbose',false); testConfig; testLLS_DL; testLLS_UL; testLLS_ReferencePoints"`
- If any required test fails, fix the code or narrow the claim. Do not ship by weakening the assertion or by adding fallback or proxy rows.
