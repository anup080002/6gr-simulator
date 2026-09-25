function ok = testMeasuredPHYEvidenceCellAggregation()
%TESTMEASUREDPHYEVIDENCECELLAGGREGATION Multi-codeword evidence is conserved.

carrier = struct("NSizeGrid", 1, "SymbolsPerSlot", 14);
plane = 12 * 14;
dmrsInd = [1; 13; 1 + plane; 13 + plane];
dmrsAntInd = [dmrsInd; dmrsInd + 2 * plane];
dmrsSym = complex(ones(4, 1));
dmrsInfo = struct("CDMLengths", [2 1], ...
    "DMRSPortSet", [3 5], ...
    "DMRSPortSetSource", "executed_test_receiver_dmrs_configuration");
rateMatched = {zeros(5, 1), zeros(7, 1)};
rateRecovered = {[1; 2; Inf], [3; 4; 5]};
rateRecoveredBatch = {[1 2; 3 4; 5 6], [7; 8; 9]};
rateInfo = {struct("NrefUsed", 99), struct("NrefUsed", 99)};

rx = sixgr.phy.rx.appendMeasuredPHYEvidence(struct(), carrier, ...
    dmrsInd, dmrsAntInd, dmrsSym, dmrsInfo, rateMatched, ...
    rateRecovered, rateRecoveredBatch, rateInfo, [2 4 6], [0 1 0], ...
    [0 1 0], "Normalized min-sum", false, [0 1]);

assert(rx.MeasuredDMRSRECount == 4);
assert(rx.MeasuredDMRSAntennaRECount == 8);
assert(rx.MeasuredDMRSSymbolCount == 2);
assert(rx.MeasuredDMRSPortCount == 2);
assert(string(rx.MeasuredDMRSPortSet) == "[3 5]" && ...
    string(rx.MeasuredDMRSPortSetSource) == ...
    "executed_test_receiver_dmrs_configuration", ...
    "Measured DM-RS identity must preserve the executed logical ports, not infer them from count.");
assert(rx.MeasuredDMRSAntennaPortCount == 4);
assert(rx.MeasuredDMRSCDMLengthFD == 2 && ...
    rx.MeasuredDMRSCDMLengthTD == 1);
assert(rx.MeasuredRateMatchedCodewordLLRBits == 12);
assert(rx.MeasuredRateRecoveredLLRBits == 6);
assert(rx.MeasuredRateRecoveredFiniteLLRCount == 5);
assert(rx.MeasuredRateRecoverFillerBits == 1);
assert(rx.MeasuredRateRecoveredCodeBlockLength_bits == 3);
assert(rx.MeasuredRateRecoveredCodeBlockCount == 3);
assert(rx.MeasuredRateRecoverNrefBits == 99);
assert(rx.MeasuredLDPCDecoderMeanIterations == 4);
assert(rx.MeasuredLDPCParityCheckFailures == 1);
assert(rx.MeasuredCodeBlockDecodeErrorCount == 1);

compact = sixgr.link.deriveMeasuredPHYEvidence(rx);
trial = sixgr.link.appendMeasuredPHYEvidenceColumns(table(1, ...
    'VariableNames', {'TrialId'}), {compact});
assert(string(trial.MeasuredDMRSPortSet(1)) == "[3 5]" && ...
    string(trial.MeasuredDMRSPortSetSource(1)) == ...
    "executed_test_receiver_dmrs_configuration", ...
    "Compact trial-table construction dropped executed DM-RS port identity.");

% A scalar common Nref may only represent complete, agreeing codewords.
for inconsistent = {{struct('NrefUsed',99),struct('NrefUsed',100)}, ...
        {struct('NrefUsed',99),struct()}, {struct('NrefUsed',99),[]}}
    incomplete = sixgr.phy.rx.appendMeasuredPHYEvidence(struct(), carrier, ...
        dmrsInd, dmrsAntInd, dmrsSym, dmrsInfo, rateMatched, ...
        rateRecovered, rateRecoveredBatch, inconsistent{1});
    assert(isnan(incomplete.MeasuredRateRecoverNrefBits), ...
        'Different or missing codeword limits cannot be exported as one measured Nref.');
end

badDMRSInfo = dmrsInfo;
badDMRSInfo.DMRSPortSet = 3;
try
    sixgr.phy.rx.appendMeasuredPHYEvidence(struct(), carrier, ...
        dmrsInd, dmrsAntInd, dmrsSym, badDMRSInfo);
    error("test:MissingDMRSPortCountMismatch", ...
        "Inconsistent measured DM-RS identity/count evidence must fail closed.");
catch ME
    assert(string(ME.identifier) == ...
        "sixgr:phy:rx:MeasuredDMRSPortCountMismatch", ...
        "Unexpected inconsistent DM-RS evidence failure: %s", ...
        ME.message);
end

ok = true;
fprintf("testMeasuredPHYEvidenceCellAggregation: PASS.\n");
end
