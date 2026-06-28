function ok = testPhysicalRuntimeCoverageMatrix()
%TESTPHYSICALRUNTIMECOVERAGEMATRIX Gate enabled block runtime contracts.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

blocks = ["DL_PDSCH", "PDCCH", "PUCCH", "PRACH", "PBCH", ...
    "CSI_RS", "SRS", "TRS", "HARQ", "RA", "MU_MIMO", "MULTI_TRP"];
T = sixgr.validation.buildPhysicalRuntimeCoverageMatrix(struct(), ...
    "EnabledBlocks", blocks, ...
    "FailOnGap", true);

assert(height(T) == numel(blocks), ...
    "Physical runtime matrix must expose one row for every required block.");
assert(numel(unique(string(T.CanonicalBlock))) == height(T), ...
    "Physical runtime matrix must not duplicate canonical blocks.");
assert(all(logical(T.Enabled)), ...
    "The focused audit must force every required block into the enabled state.");
assert(all(logical(T.CoveragePass)), ...
    "Every enabled block must either execute in shared runtime or fail closed with evidence anchors.");
assert(~any(ismember(string(T.ExecutionEvidencePolicy), ["report_only", "synthetic", "fallback", "proxy_only"])), ...
    "Physical runtime coverage must not rely on report-only, synthetic, fallback, or proxy-only policy.");
assert(all(logical(T.ProducerPresent) & logical(T.ConsumerPresent) & logical(T.TestAnchorPresent)), ...
    "Runtime producer, consumer, and focused test anchors must exist for each enabled block.");

localAssertRow(T, "PUCCH", true, "shared_runtime", "testLLSPUCCHWaveformFeedback");
localAssertRow(T, "PRACH", true, "shared_runtime", "testFourStepRARuntimeStageComposer");
localAssertRow(T, "RA", true, "shared_runtime", "testFourStepRARuntimeStageComposer");
localAssertRow(T, "PBCH", false, "fail_closed_contract", "testLLSControlAccessGating");
localAssertRow(T, "CSI_RS", true, "shared_runtime", "testCSIRSOracleValidationCampaign");
localAssertRow(T, "SRS", true, "shared_runtime", "testSRSMultiUECollision");
localAssertRow(T, "TRS", true, "shared_runtime", "testSynchronizationStateSignConventions");
localAssertRow(T, "MU_MIMO", true, "shared_runtime", "testMIMOExecutionContracts");
localAssertRow(T, "MULTI_TRP", true, "shared_runtime", "testMIMOExecutionContracts");

ra = localRow(T, "RA");
assert(string(ra.FailClosedErrorId) == "sixgr:phy:ra:MissingRuntimeStageWaveform", ...
    "RA must fail closed when strict runtime stage waveforms are absent.");
pdcch = localRow(T, "PDCCH");
assert(contains(string(pdcch.RequiredEvidence), "decoded_dci_matches_finalized_grant"), ...
    "PDCCH coverage must require decoded DCI to reconstruct the finalized grant.");

threw = false;
try
    sixgr.validation.buildPhysicalRuntimeCoverageMatrix(struct(), "EnabledBlocks", "report_only_demo");
catch ME
    threw = strcmp(ME.identifier, "sixgr:validation:UnknownPhysicalRuntimeBlock");
end
assert(threw, "Unknown physical blocks must fail closed instead of creating permissive rows.");

ok = true;
end

function localAssertRow(T, block, sharedExpected, statusExpected, requiredTest)
row = localRow(T, block);
assert(logical(row.SharedPhysicalRuntime) == logical(sharedExpected), ...
    "%s shared-runtime flag mismatch.", block);
assert(string(row.RuntimeStatus) == string(statusExpected), ...
    "%s runtime status mismatch.", block);
assert(contains(string(row.RequiredTests), string(requiredTest)), ...
    "%s row must retain focused test anchor %s.", block, requiredTest);
end

function row = localRow(T, block)
key = upper(regexprep(string(block), "[^A-Za-z0-9]", ""));
mask = string(T.CanonicalBlock) == key;
assert(nnz(mask) == 1, "Expected exactly one row for block %s.", block);
row = T(mask, :);
end
