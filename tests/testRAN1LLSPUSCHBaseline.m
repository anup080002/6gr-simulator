function ok = testRAN1LLSPUSCHBaseline()
%TESTRAN1LLSPUSCHBASELINE Dedicated waveform-only PUSCH LLS qualification.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
required = ["nrPUSCH","nrPUSCHDecode","nrLDPCEncode","nrLDPCDecode"];
for idx = 1:numel(required)
    assert(exist(required(idx), "file") == 2, "Required 5G Toolbox API missing: %s", required(idx));
end

[cfg, provenance] = sixgr.lls.loadConfig("configs/lls/pusch_reference_smoke.yaml");
localAssertQPSKTheory();
assert(string(cfg.simulation.mode) == "LLS" && string(cfg.simulation.link) == "PUSCH");
assert(string(cfg.channel.model) == "AWGN");
assert(~isfield(cfg, "geometry") && ~isfield(cfg, "scheduler") && ~isfield(cfg, "traffic"));
assert(strlength(provenance.ConfigSHA256) == 64);

bad = cfg;
bad.geometry = struct("cellRadius", 100);
localAssertError(@() sixgr.lls.validateConfig(bad), "sixgr:lls:ForbiddenSystemLevelInput");
bad = cfg;
bad.channel.model = "TDL";
localAssertError(@() sixgr.lls.validateConfig(bad), "sixgr:lls:UnsupportedChannel");

[lower, upper] = sixgr.lls.stats.wilsonInterval(0, 100, 0.95);
assert(lower <= 1e-12 && upper > 0 && upper < 0.05, ...
    "Zero-error BLER must retain a finite statistical upper bound.");
crossing = sixgr.lls.stats.interpolateRequiredSNR([-2 0 2], [0.5 0.1 0.01], 0.1);
assert(crossing.Valid && abs(crossing.RequiredSNR_dB) < 1e-12);
noCrossing = sixgr.lls.stats.interpolateRequiredSNR([0 2], [0.01 0.001], 0.1);
assert(~noCrossing.Valid && isnan(noCrossing.RequiredSNR_dB));

tmp = string(tempname);
mkdir(tmp);
cleanup = onCleanup(@() localCleanup(tmp)); %#ok<NASGU>
first = sixgr.lls.runLLS("configs/lls/pusch_reference_smoke.yaml", ...
    "OutputRoot", tmp, "RunTag", "repro_a", "GeneratePlots", true);
second = sixgr.lls.runLLS("configs/lls/pusch_reference_smoke.yaml", ...
    "OutputRoot", tmp, "RunTag", "repro_b", "GeneratePlots", false);

assert(first.Status == "complete_valid" && height(first.SummaryTable) == 3);
assert(height(first.TrialTable) >= 9, "Each SNR point must execute its configured minimum TB count.");
assert(all(first.TrialTable.CRCSource == "decoded_transport_block_crc"));
assert(all(first.TrialTable.LLRSource == "nrPUSCHDecode_soft_llr"));
assert(all(first.TrialTable.ChannelRealizationSource == "explicit_unit_flat_channel"));
assert(all(first.TrialTable.MCSTable == ...
    string(first.AssumptionsTable.MCSTable)) && ...
    all(first.TrialTable.MCSTable == "explicit_modulation_and_target_code_rate"), ...
    "Fixed-MCS PUSCH trials must report the PUSCH MCS authority, not the disabled AMC table.");
assert(all(first.TrialTable.DMRSResidualPostEqSINRBoundEnabled == ...
    logical(first.Config.receiver.postEqualizationSINR.dmrsResidualBoundEnabled)));
assert(all(first.TrialTable.DecisionDirectedPostEqSINRBoundEnabled == ...
    logical(first.Config.receiver.postEqualizationSINR.decisionDirectedResidualBoundEnabled)));
assert(all(isfinite(first.TrialTable.DecoderNoiseVariance) & ...
    first.TrialTable.DecoderNoiseVariance > 0));
assert(all(first.TrialTable.DecoderNoiseVarianceConfiguredMode == ...
    string(first.Config.receiver.decoderNoiseVariance.mode)));
assert(~any(contains(string(first.TrialTable.DecoderNoiseVarianceSource), ...
    "fallback","IgnoreCase",true)));
assert(all(abs(first.TrialTable.MeasuredSNRdB-first.TrialTable.TargetSNRdB) < 0.5), ...
    "Measured grid-domain SNR must agree with configured occupied-RE Es/N0.");
assert(all(diff(first.SummaryTable.BLER) <= 0), ...
    "Coded AWGN QPSK BLER must be non-increasing over the diagnostic SNR ladder.");
assert(any(first.SummaryTable.NumBlockErrors == 0) && ...
    all(first.SummaryTable.BLERUpperCI(first.SummaryTable.NumBlockErrors == 0) > 0), ...
    "Zero-error points must report a positive Wilson upper bound.");
assert(first.ScientificSemanticSHA256 == second.ScientificSemanticSHA256, ...
    "Identical YAML/seed executions must have identical scientific hashes.");
assert(isequaln(removevars(first.TrialTable, "RuntimeSeconds"), ...
    removevars(second.TrialTable, "RuntimeSeconds")), ...
    "Common deterministic streams must reproduce every scientific trial value.");
truth = first.TruthContractTable;
assert(all(truth{1,["WaveformGenerated","ActualLDPC","ActualRateMatching", ...
    "ActualScrambling","ActualModulation","ActualLayerMapping","ActualPrecoding", ...
    "ActualResourceGrid","ActualOFDM","ActualDMRS","ActualChannel","ActualNoise", ...
    "ActualEqualization","ActualSoftDemapping","ActualLDPCDecode","ActualCRC"]}));
assert(~any(truth{1,["UsesBLERLookupTable","UsesSyntheticBLER", ...
    "UsesRandomPassFailModel","UsesGeometryAsLLS"]}));
assert(~truth.ActualHARQ && truth.HARQEvidenceValid && ...
    ~truth.ActualInterference && truth.InterferenceEvidenceValid && ...
    ~truth.ActualLinkAdaptation && truth.LinkAdaptationEvidenceValid, ...
    "Disabled feature execution flags must remain false while disabled-state evidence passes.");
assert(truth.StatisticalClass == "diagnostic_only" && ~truth.PublicationEligible, ...
    "Short smoke evidence must never be labeled publication-qualified.");
assert(all(first.ValidityTable.Pass), "Every baseline scientific validity check must pass.");
assert(height(first.RequiredSNRTable) == 3 && ~any(first.RequiredSNRTable.Valid), ...
    "Sparse diagnostic points must not extrapolate target-BLER required SNR.");

[publicationCfg,~] = sixgr.lls.loadConfig( ...
    "configs/lls/pusch_awgn_qpsk_publication.yaml");
assert(~publicationCfg.receiver.postEqualizationSINR.dmrsResidualBoundEnabled && ...
    ~publicationCfg.receiver.postEqualizationSINR.decisionDirectedResidualBoundEnabled && ...
    publicationCfg.provenance.requireCleanWorktree && ...
    publicationCfg.provenance.requireStableSourceThroughoutRun, ...
    "Perfect-CSI publication config must disable residual bounds and require stable clean source.");

expected = ["bler_vs_snr.csv","transport_block_trials.csv","simulation_assumptions.csv", ...
    "truth_contract.csv","resolved_config.json","run_provenance.json", ...
    "required_snr_at_target_bler.csv","result_validity.csv", ...
    "artifact_manifest.csv","bler_vs_snr.png","throughput_vs_snr.png","pusch_resource_grid.png"];
for idx = 1:numel(expected)
    assert(exist(fullfile(first.RunFolder, expected(idx)), "file") == 2, ...
        "Missing required LLS artifact: %s", expected(idx));
end
listing = dir(fullfile(first.RunFolder,"*"));
artifactNames = string({listing.name});
assert(~any(endsWith(artifactNames, ".svg", "IgnoreCase", true)), ...
    "LLS output must not contain SVG figures.");

fprintf("RAN1LLSPUSCHBaseline: %d SNR points, %d actual TBs, deterministic hash %s.\n", ...
    height(first.SummaryTable), height(first.TrialTable), first.ScientificSemanticSHA256);
ok = true;
end

function localAssertQPSKTheory()
snrDb = 6;
numBits = 200000;
stream = RandStream("mt19937ar", "Seed", 6606);
bits = int8(randi(stream, [0 1], numBits, 1));
symbols = nrSymbolModulate(bits, "QPSK");
noiseVariance = 10^(-snrDb/10);
noise = sqrt(noiseVariance/2) .* (randn(stream,size(symbols)) + 1i*randn(stream,size(symbols)));
decoded = int8(nrSymbolDemodulate(symbols+noise, "QPSK", "DecisionType", "Hard"));
measuredBER = mean(bits ~= decoded);
theoreticalBER = 0.5 * erfc(sqrt(10^(snrDb/10))/sqrt(2));
assert(abs(measuredBER-theoreticalBER) < 1.5e-3, ...
    "Uncoded QPSK AWGN BER %.5g disagrees with theory %.5g.", measuredBER, theoreticalBER);
end

function localAssertError(fcn, identifier)
try
    fcn();
catch ME
    assert(strcmp(ME.identifier, identifier), ...
        "Expected %s, received %s: %s", identifier, ME.identifier, ME.message);
    return;
end
error("testRAN1LLSPUSCHBaseline:MissingError", "Expected typed error %s.", identifier);
end

function localCleanup(path)
if exist(path, "dir") == 7
    rmdir(path, "s");
end
end
