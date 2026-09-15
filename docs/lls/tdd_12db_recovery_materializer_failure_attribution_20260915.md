# Failed 12 dB recovery: preserve the actual publication failure (15 Sep 2026)

## Verified root cause

The retained `recovery_2c45b257_20260915/after_repair_copy` has no `reports/csv/contract_plot_lineage.csv`. Its persisted `published/browser_publication_receipt.json` records:
- Status FAIL; materializer exit code 1.
- Identifier `browser_contract_materialization_failed`.
- Exact cause: a header-only/empty `air_interface/csv/ul_pusch_trials.csv`.

The strict raster-replacement root validator rejects the absent UL authority before deleting any raster. That is valid fail-closed behavior and is unchanged. Because no browser lineage could be generated, repeated terminal publication passes could not establish lineage closure. Recovery nevertheless retried and finally reported a generic `TerminalArtifactFixedPointFailed`, hiding the producer failure as a convergence problem.

## Repair

`recoverLLSRunArtifacts.m` now persists the actual browser failure receipt, then calls `sixgr.artifact.assertBrowserMaterializationSucceeded` before component-view publication and the terminal fixed-point loop. A failed or inconsistent materialization result raises `sixgr:artifact:BrowserMaterializationFailed` with the actual producer identifier and message.

The original convergence guard remains for genuine later status/hash instability. No required table, primary semantic check, lineage hash, detector criterion or scenario verdict is relaxed. Missing rows and missing coverage counts are not manufactured.

A focused test also exposed an existing diagnostic-formatting bug in `writeBrowserPublicationReceipt`: its missing-timestamp error supplied a MATLAB string array instead of a scalar message. That formatting is corrected; missing timestamps still reject with the intended identifier. The new test supplies an explicit fixture timestamp and independently verifies the missing-timestamp rejection.

## Verification

MATLAB R2026a: **4/4 focused PASS**, `logs/recovery_materializer_failfast_verified_20260915.log`:
- testRecoveryBrowserMaterializationFailure — 4.43 s.
- testBrowserPublicationReceipt — 0.15 s.
- testLLSRecoveryErrorMessages — 0.03 s.
- testContractPlotLineageSourceClosure — 7.07 s.

The checks cover exact diagnostic preservation, unchanged failed receipt bytes, rejected inconsistent results, successful result handling, preserved timestamp rejection, and exact chart-source hashing. The recovery caller is checked to save its receipt before the new guard and invoke the guard before retrying convergence.

## Limits

This repairs error attribution and avoids redundant publication retries. It does NOT create a complete browser publication from missing UL evidence, qualify the failed 12 dB run, or claim full recovery closure. A separately audited partial-publication path, if needed, must preserve failed/missing coverage and validate every published source; merely disabling strict checks is not an acceptable fix.

The live 12 dB execution remains frozen at 471334ff. Final-source full testAll and required export/E2E guards are still outstanding; prior queued revisions are not evidence for this patch.
