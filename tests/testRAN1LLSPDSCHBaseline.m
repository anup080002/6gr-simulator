function ok = testRAN1LLSPDSCHBaseline()
%TESTRAN1LLSPDSCHBASELINE Dedicated production PDSCH waveform LLS gate.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
[cfg, provenance] = sixgr.lls.loadConfig("configs/lls/pdsch_reference_smoke.yaml");
assert(string(cfg.simulation.mode) == "LLS" && string(cfg.simulation.link) == "PDSCH");
assert(string(cfg.channel.model) == "AWGN");
assert(string(cfg.receiver.channelEstimation) == "practical");
assert(strlength(provenance.ConfigSHA256) == 64);

bad = cfg;
bad.scheduler = struct("policy", "round_robin");
localAssertError(@() sixgr.lls.validateConfig(bad), ...
    "sixgr:lls:ForbiddenSystemLevelInput");
bad = cfg;
bad.receiver.channelEstimation = "perfect";
localAssertError(@() sixgr.lls.validateConfig(bad), ...
    "sixgr:lls:PDSCHPerfectCSIUnavailable");

tmp = string(tempname);
mkdir(tmp);
cleanup = onCleanup(@() localCleanup(tmp)); %#ok<NASGU>
result = sixgr.lls.runLLS("configs/lls/pdsch_reference_smoke.yaml", ...
    "OutputRoot", tmp, "RunTag", "pdsch_waveform_gate", "GeneratePlots", true);

assert(result.Status == "complete_valid");
assert(height(result.SummaryTable) == 3 && height(result.TrialTable) >= 9);
assert(all(result.TrialTable.LLRSource == "nrPDSCHDecode_soft_llr"));
assert(all(result.TrialTable.CRCSource == "decoded_transport_block_crc"));
assert(all(result.TrialTable.ChannelEstimationMode == "practical"));
assert(all(result.TrialTable.ChannelEstimateEngine == ...
    "explicit_awgn_scalar_per_physical_port_ls"));
assert(all(abs(result.TrialTable.MeasuredSNRdB-result.TrialTable.TargetSNRdB) < 0.5));
assert(all(diff(result.SummaryTable.BLER) <= 0));
assert(result.SummaryTable.NumBlockErrors(1) > 0, ...
    "Low-SNR PDSCH point must exercise decoder failure/CRC authority.");
assert(result.SummaryTable.NumBlockErrors(end) == 0, ...
    "High-SNR PDSCH smoke point must decode without observed errors.");
assert(all(result.ValidityTable.Pass));
truth = result.TruthContractTable;
assert(all(truth{1,["WaveformGenerated","ActualLDPC","ActualRateMatching", ...
    "ActualDMRS","ActualChannel","ActualNoise","ActualEqualization", ...
    "ActualSoftDemapping","ActualLDPCDecode","ActualCRC"]}));
assert(~truth.PublicationEligible && truth.StatisticalClass == "diagnostic_only");

expected = ["bler_vs_snr.csv","transport_block_trials.csv", ...
    "simulation_assumptions.csv","truth_contract.csv", ...
    "required_snr_at_target_bler.csv","result_validity.csv", ...
    "resolved_config.json","run_provenance.json","artifact_manifest.csv", ...
    "bler_vs_snr.png","throughput_vs_snr.png","pdsch_resource_grid.png"];
for idx = 1:numel(expected)
    assert(exist(fullfile(result.RunFolder,expected(idx)),"file") == 2, ...
        "Missing required PDSCH LLS artifact: %s", expected(idx));
end
listing = dir(fullfile(result.RunFolder,"*"));
assert(~any(endsWith(string({listing.name}),".svg","IgnoreCase",true)));

fprintf("RAN1LLSPDSCHBaseline: %d SNR points, %d actual TBs, hash %s.\n", ...
    height(result.SummaryTable),height(result.TrialTable), ...
    result.ScientificSemanticSHA256);
ok = true;
end

function localAssertError(fcn, identifier)
try
    fcn();
catch ME
    assert(strcmp(ME.identifier,identifier), ...
        "Expected %s, received %s: %s",identifier,ME.identifier,ME.message);
    return;
end
error("testRAN1LLSPDSCHBaseline:MissingError", ...
    "Expected typed error %s.",identifier);
end

function localCleanup(path)
if exist(path,"dir") == 7
    rmdir(path,"s");
end
end
