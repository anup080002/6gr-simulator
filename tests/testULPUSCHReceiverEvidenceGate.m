function ok = testULPUSCHReceiverEvidenceGate()
%TESTULPUSCHRECEIVEREVIDENCEGATE Validate strict UL PUSCH evidence gating.

setup6GRSimToolkit("Verbose", false);

if ~localHaveRequired5G()
    ok = true;
    return;
end

cfg = localBasicStrictPUSCHCfg();
res = sixgr.link.runULPUSCHThroughput(cfg, "NumFrames", 2, "SNR_dB", 30);
assert(istable(res.TrialTable) && height(res.TrialTable) == 2, ...
    "Strict UL PUSCH helper must export row-level receiver evidence.");

T = res.TrialTable;
required = ["StrictReceiverEvidenceOk","StrictOk","TruthStatus", ...
    "ChannelEstimateAttempted","ChannelEstimateAvailable", ...
    "ResourceExtractionAttempted","ResourceExtractionAvailable", ...
    "EqualizationAttempted","EqualizationAvailable", ...
    "ULSCHDecodeAttempted","ULSCHDecodeAvailable", ...
    "LLRAvailable","LLRFinite", ...
    "PostEqSINRWidebanddB","PostEqSINRAvailable","PostEqSINRReceiverDerived", ...
    "SINRValidationStatus","SINRValidationReason","SINRComputationMethod", ...
    "ConfiguredSNRLikeSourceRejected","CRCApplicable", ...
    "ReceiverHestSINRApplicable"];
assert(all(ismember(required, string(T.Properties.VariableNames))), ...
    "UL PUSCH trial table must expose the strict receiver evidence contract.");

assert(all(logical(T.StrictReceiverEvidenceOk)), ...
    "High-SNR strict AWGN PUSCH rows must have complete receiver evidence.");
assert(all(logical(T.ChannelEstimateAttempted) & logical(T.ChannelEstimateAvailable)), ...
    "Passing strict PUSCH rows must include DM-RS channel-estimation evidence.");
assert(all(logical(T.ResourceExtractionAttempted) & logical(T.ResourceExtractionAvailable)), ...
    "Passing strict PUSCH rows must include PUSCH resource extraction evidence.");
assert(all(logical(T.EqualizationAttempted) & logical(T.EqualizationAvailable)), ...
    "Passing strict PUSCH rows must include equalization evidence.");
assert(all(logical(T.ULSCHDecodeAttempted) & logical(T.ULSCHDecodeAvailable)), ...
    "Passing strict PUSCH rows must include UL-SCH decoder evidence.");
assert(all(logical(T.CRCApplicable)), ...
    "Real UL-SCH decoder outcomes must mark transport-block CRC as applicable.");
assert(all(logical(T.ReceiverHestSINRApplicable)), ...
    "Finite PUSCH DM-RS receiver measurements must be marked applicable.");
assert(all(logical(T.LLRAvailable) & logical(T.LLRFinite)), ...
    "Passing strict PUSCH rows must include finite LLR evidence.");
assert(all(isfinite(double(T.PostEqSINRWidebanddB))) && all(logical(T.PostEqSINRReceiverDerived)), ...
    "Passing strict PUSCH rows must include finite receiver-derived post-eq SINR.");
assert(all(strcmpi(string(T.SINRValidationStatus), "pass")), ...
    "Strict PUSCH post-eq SINR validation must pass for high-SNR real receiver rows.");
assert(~any(contains(lower(string(T.PostEqSINRSource)), ["configured","fallback","proxy","oracle","cqi","mcs"])), ...
    "Post-eq SINR source must not be configured/proxy/oracle-backed.");

fake = localMinimalEvidenceRx();
fake.PostEqSINRSource = "configured_snr_shortcut";
fake.SINRComputationMethod = "configured_snr";
bad = sixgr.phy.ul.validatePUSCHReceiverEvidence(fake, "StrictMode", true);
assert(~logical(bad.StrictReceiverEvidenceOk) && logical(bad.ConfiguredSNRLikeSourceRejected), ...
    "Configured-SNR-looking post-eq SINR must be rejected by the strict evidence gate.");

fake = localMinimalEvidenceRx();
fake.PostEqSINRSource = "evm_proxy_not_true_post_equalization_sinr";
fake.PostEqSINRValueRole = "diagnostic_evm_proxy_not_scheduling_input";
bad = sixgr.phy.ul.validatePUSCHReceiverEvidence(fake, "StrictMode", true);
assert(~logical(bad.StrictReceiverEvidenceOk), ...
    "Diagnostic/proxy SINR must not satisfy strict UL PUSCH receiver evidence.");

ok = true;
end

function cfg = localBasicStrictPUSCHCfg()
cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.run.strictMode = true;
cfg.run.noProxyTruthContract = true;
cfg.run.strictNoiseVarianceRequired = true;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.phy.pusch.enable = true;
cfg.phy.nTxAnt = 1;
cfg.phy.nRxAnt = 1;
cfg.channel.nTxAnt = 1;
cfg.channel.nRxAnt = 1;
cfg.channel.model = "AWGN";
cfg.channel.awgnOnly = true;
cfg.channel.snr_dB = 30;
cfg.phy.carrier.NSizeGrid = 12;
cfg.phy.carrier.SubcarrierSpacing = 30;
cfg.phy.pusch.prbSet = 0:5;
cfg.phy.pusch.symbolAllocation = [0 10];
cfg.phy.pusch.modulation = "QPSK";
% defaultConfig selects the TS 38.214 256-QAM MCS table; index 4 is
% QPSK with R=602/1024 in that table.
cfg.phy.pusch.codeRate = 602 / 1024;
cfg.phy.pusch.mcsIndex = 4;
cfg.phy.pusch.nLayers = 1;
cfg.phy.pusch.numLayers = 1;
cfg.phy.pusch.transformPrecoding = true;
cfg.phy.pusch.powerControl.enabled = false;
cfg.phy.pusch.equalizer = "MMSE";
cfg.phy.channelEstimation.method = "LS";
end

function rx = localMinimalEvidenceRx()
rx = struct();
rx.Ok = true;
rx.CRCError = false;
rx.ChannelEstimateAttempted = true;
rx.ChannelEstimateAvailable = true;
rx.ChannelEstimateSource = "pusch_dmrs_channel_estimate";
rx.ChannelEstimate = ones(8, 1, 1);
rx.ResourceExtractionAttempted = true;
rx.PUSCHRxSymbolsForEvidence = ones(8, 1);
rx.EqualizationAttempted = true;
rx.EqualizedSymbolsForEvidence = ones(8, 1);
rx.ULSCHDecodeAttempted = true;
rx.DecodeAttempted = true;
rx.TransportBlock = int8([1;0;1;0]);
rx.ULSCHCodewordLLR = [4; -4; 3; -3];
rx.LLRAvailable = true;
rx.LLRFinite = true;
rx.PostEqSINR_dB = 18;
rx.PostEqSINRSource = "post_equalization_sinr_from_equalizer_channel_estimate";
rx.PostEqSINRValueRole = "measured_post_equalization_scheduling_input";
rx.PostEqSINRValueStatus = "OK";
rx.SINRComputationMethod = "mmse";
end

function tf = localHaveRequired5G()
tf = exist("nrPUSCH", "file") == 2 ...
    && exist("nrPUSCHDecode", "file") == 2 ...
    && exist("nrChannelEstimate", "file") == 2 ...
    && exist("nrOFDMDemodulate", "file") == 2;
end
