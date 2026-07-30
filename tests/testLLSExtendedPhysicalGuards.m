function ok = testLLSExtendedPhysicalGuards()
%TESTLLSEXTENDEDPHYSICALGUARDS Focused guards for extended LLS audit fixes.

setup6GRSimToolkit("Verbose", false);

testLDPCIterationResolver();
testCQITableInferenceFollowsMCS();
testDynamicPDSCHXOverhead();
testPhaseNoiseMaterializes();
testOFDMWindowingMaterializesInTxPath();
testPUSCHPi2BPSKTransformPrecodingMaterializes();
testPDCCHHighSCSFailsClosed();
testTimingCorrectionBoundedByCP();
testIQImageRejectionMeasurementFloor();
testReferenceSINRDynamicRangeLimit();
testSchedulerDefaultDLAvoidsCORESET();

ok = true;
end

function testLDPCIterationResolver()
cfg = sixgr.config.defaultConfig();
cfg = sixgr.config.normalizeConfig(cfg);
cfg = localRemoveNested(cfg, "phy.ldpc.maxIterations");
assert(sixgr.phy.phycode.resolveLDPCMaxIterations(cfg, "Direction", "DL") >= 50, ...
    "LDPC decoder default must use a conformance-style iteration budget, not 8.");
cfg = sixgr.util.structSet(cfg, "phy.pdsch.targetBLER", 1e-5);
assert(sixgr.phy.phycode.resolveLDPCMaxIterations(cfg, "Direction", "DL") >= 200, ...
    "High-reliability BLER targets must raise LDPC max iterations.");
cfgFading = sixgr.config.defaultConfig();
cfgFading = sixgr.util.structSet(cfgFading, "channel.model", "CDL-C");
cfgFading = sixgr.util.structSet(cfgFading, "channel.cdlProfile", "CDL-C");
cfgFading = sixgr.util.structSet(cfgFading, "phy.ldpc.maxIterations", 50);
assert(sixgr.phy.phycode.resolveLDPCMaxIterations(cfgFading, "Direction", "DL") == 50, ...
    "Explicit LDPC iteration budgets must remain scenario-authoritative.");
cfgFading = localRemoveNested(cfgFading, "phy.ldpc.maxIterations");
cfgFading = sixgr.util.structSet(cfgFading, "phy.ldpc.fadingMinIterations", 100);
assert(sixgr.phy.phycode.resolveLDPCMaxIterations(cfgFading, "Direction", "DL") >= 100, ...
    "Concrete CDL/TDL fading channels may lift the default budget only through an explicit floor policy.");
end

function testCQITableInferenceFollowsMCS()
cfg = sixgr.config.defaultConfig();
cfg = localRemoveNested(cfg, "phy.csi.cqiTable");
cfg = localRemoveNested(cfg, "phy.csi.dlCQITable");
cfg = localRemoveNested(cfg, "phy.pdsch.cqiTable");
cfg = sixgr.util.structSet(cfg, "phy.pdsch.maxModulation", "256QAM");
cfg = sixgr.config.normalizeConfig(cfg);
assert(strcmpi(char(string(cfg.phy.pdsch.cqiTable)), "table2"), ...
    "DL CQI table must infer table2 from 256QAM-capable PDSCH config.");
assert(strcmpi(char(sixgr.link.resolveConfiguredCQITable(cfg, "DL")), "table2"), ...
    "Runtime CQI resolution must not hardcode table1 when MCS/maxModulation implies table2.");
end

function testDynamicPDSCHXOverhead()
cfg = sixgr.config.defaultConfig();
cfg = sixgr.util.structSet(cfg, "phy.pdsch.xOverhead", []);
cfg = sixgr.util.structSet(cfg, "phy.ssb.enable", true);
cfg = sixgr.util.structSet(cfg, "phy.ssb.symbolLocations", [0 1 2 3]);
cfg = sixgr.util.structSet(cfg, "phy.csirs.enable", true);
cfg = sixgr.util.structSet(cfg, "phy.csirs.symbolLocations", 5);
xOverhead = sixgr.phy.dl.resolvePDSCHXOverhead(cfg, [0 14]);
assert(double(xOverhead) == 18, ...
    "PDSCH N_oh must reflect three or more overlapping SSB/CSI-RS symbols.");

cfgExplicit = sixgr.util.structSet(cfg, "phy.pdsch.xOverhead", 0);
assert(double(sixgr.phy.dl.resolvePDSCHXOverhead(cfgExplicit, [0 14])) == 0, ...
    "Explicit PDSCH xOverhead config must remain authoritative.");
end

function testPhaseNoiseMaterializes()
cfg = sixgr.config.defaultConfig();
cfg.rf.phaseNoise.enable = true;
cfg.phy.fc_Hz = 28e9;
[y, replay] = sixgr.link.applyWaveformImpairments(complex(ones(4096,1)), cfg, 30.72e6);
assert(logical(replay.PhaseNoiseConfigured) && logical(replay.PhaseNoiseApplied), ...
    "Configured phase noise must be materialized in the active waveform path.");
assert(strcmpi(char(string(replay.PhaseNoiseExecutionStatus)), "applied_sample_domain_phase_noise"), ...
    "Phase-noise replay status must report sample-domain application.");
assert(any(abs(y - y(1)) > 0), ...
    "Applied phase noise must vary across samples, not a constant phase label.");
end

function testOFDMWindowingMaterializesInTxPath()
cfg = sixgr.config.defaultConfig();
cfg = sixgr.config.normalizeConfig(cfg);
cfg = sixgr.util.structSet(cfg, "phy.ofdm.windowingPercent", 0.025);
cfg = sixgr.util.structSet(cfg, "phy.carrier.NSizeGrid", 24);
cfg = sixgr.util.structSet(cfg, "phy.pdsch.executionProfile", "phy_calibration");
cfg = sixgr.util.structSet(cfg, "phy.pdsch.prbSet", 0:11);
cfg = sixgr.util.structSet(cfg, "phy.pusch.prbSet", 0:11);

[txDL, infoDL] = sixgr.phy.dl.PDSCH_Tx(cfg, "CompactOutput", true);
assert(logical(txDL.OFDMWindowingEnabled) && double(txDL.OFDMWindowingSamples) > 0 && ...
    isfield(infoDL, "OFDMWindowing"), ...
    "PDSCH_Tx must pass configured OFDM windowing into the physical OFDM waveform path.");

[txUL, infoUL] = sixgr.phy.ul.PUSCH_Tx(cfg, "CompactOutput", true);
assert(logical(txUL.OFDMWindowingEnabled) && double(txUL.OFDMWindowingSamples) == double(txDL.OFDMWindowingSamples) && ...
    isfield(infoUL, "OFDMWindowing"), ...
    "PUSCH_Tx must pass the same configured OFDM windowing into the UL waveform path.");
end

function testPUSCHPi2BPSKTransformPrecodingMaterializes()
cfg = sixgr.config.defaultConfig();
cfg = sixgr.config.normalizeConfig(cfg);
cfg = sixgr.util.structSet(cfg, "phy.carrier.NSizeGrid", 24);
cfg = sixgr.util.structSet(cfg, "phy.pusch.prbSet", 0:5);
cfg = sixgr.util.structSet(cfg, "phy.pusch.modulation", "pi/2-BPSK");
cfg = sixgr.util.structSet(cfg, "phy.pusch.transformPrecoding", false);

[txUL, infoUL] = sixgr.phy.ul.PUSCH_Tx(cfg, "CompactOutput", true);
assert(strcmpi(char(string(txUL.PUSCH.Modulation)), "pi/2-BPSK"), ...
    "PUSCH_Tx must preserve configured pi/2-BPSK modulation semantics.");
assert(logical(txUL.PUSCH.TransformPrecoding) && ~isempty(txUL.Waveform), ...
    "pi/2-BPSK PUSCH must materialize a transform-precoded DFT-s-OFDM waveform.");
assert(strcmpi(char(string(infoUL.TransformPrecodingAppliedBy)), "nrPUSCH_native_transform_precoding"), ...
    "pi/2-BPSK transform-precoding evidence must come from the native nrPUSCH runtime path.");
end

function testPDCCHHighSCSFailsClosed()
cfg120 = localBasePDCCHCfg();
cfg120.phy.numerology.mu = 3;
cfg120.phy.carrier.SubcarrierSpacing = 120;
cfg120.ctrl6gr.CORESET.DurationSymbols = 2;
localAssertError(@() sixgr.ctrl.ControlChannelConfig(cfg120), ...
    "sixgr:ctrl:CORESETConfig:InvalidDurationForSCS");

cfg480 = localBasePDCCHCfg();
cfg480.phy.numerology.mu = 5;
cfg480.phy.carrier.SubcarrierSpacing = 480;
cfg480.ctrl6gr.CORESET.DurationSymbols = 1;
ctrl = sixgr.ctrl.ControlChannelConfig(cfg480);
localAssertError(@() sixgr.ctrl.PDCCHBlindDetector(complex(zeros(1,1,1,1)), ctrl, ctrl.SearchSpaces, table(), table(), table(), struct("BaseSlot", 0)), ...
    "sixgr:ctrl:PDCCH:Undefined6GNumerologyCandidateLimit");
end

function testTimingCorrectionBoundedByCP()
timing = sixgr.phy.sync.resolveTimingApplication(11125, ...
    "EstimateUsed", true, ...
    "MaxCorrectionSamples", 144);
assert(double(timing.AppliedCorrection_samples) == 144 && logical(timing.WasClipped), ...
    "Timing correction must be bounded to the CP/window instead of applying an impossible full raw estimate.");
assert(strcmpi(char(string(timing.Status)), "available_applied_clipped_to_cp_window"), ...
    "Clipped timing correction must disclose the bounded application status.");
end

function testIQImageRejectionMeasurementFloor()
cfg = sixgr.config.defaultConfig();
cfg.phy.impairments.iqImbalanceEnabled = false;
rng(42, "twister");
x = complex(randn(4096,1), randn(4096,1));
[~, replay] = sixgr.link.applyWaveformImpairments(x, cfg, 30.72e6);
assert(isfinite(double(replay.IQImbalanceImageRejection_dB)) && ...
    double(replay.IQImbalanceImageRejection_dB) <= 100, ...
    "Ideal-IQ measurement must report a bounded measurement floor, not an impossible image rejection.");
assert(strcmpi(char(string(replay.IQImbalanceMeasurementStatus)), "disabled"), ...
    "Disabled IQ impairment must keep the configured disabled status even while exposing bounded measurement metrics.");
end

function testReferenceSINRDynamicRangeLimit()
cfg = sixgr.config.defaultConfig();
cfg = sixgr.config.normalizeConfig(cfg);
cfg = sixgr.util.structSet(cfg, "phy.csi.maxTrustedReferenceSINR_dB", 42);
rxGrid = complex(zeros(12, 14, 1));
refInd = (1:12).';
refSym = complex(ones(12, 1));
rxGrid(refInd) = refSym;
Hest = complex(ones(12, 14, 1, 1));

csi = sixgr.phy.dl.CSI_Feedback(Hest, 1e-20, cfg, ...
    "ReceivedGrid", rxGrid, ...
    "ReferenceIndices", refInd, ...
    "ReferenceSymbols", refSym);
assert(abs(double(csi.SINR_dB) - 42) < 1e-9 && ...
    strcmpi(char(string(csi.ReferenceSINRValueStatus)), "OK_dynamic_range_limited"), ...
    "DL CSI feedback must cap receiver-reference SINR at the configured trusted dynamic range.");

ul = sixgr.phy.ul.measureULLinkState(Hest, 1e-20, cfg, ...
    "ReceivedGrid", rxGrid, ...
    "ReferenceIndices", refInd, ...
    "ReferenceSymbols", refSym);
assert(abs(double(ul.SINR_dB) - 42) < 1e-9 && ...
    strcmpi(char(string(ul.SINRValueStatus)), "OK_dynamic_range_limited"), ...
    "UL link-state feedback must use the same configured trusted dynamic range for measured SINR.");
end

function testSchedulerDefaultDLAvoidsCORESET()
cfg = sixgr.config.defaultConfig();
cfg = sixgr.config.normalizeConfig(cfg);
cfg = sixgr.util.structSet(cfg, "phy.pdcch.coreset.duration", 2);
cfg = sixgr.util.structSet(cfg, "phy.carrier.NSizeGrid", 24);
scheduler = sixgr.l2.mac.SchedulerPF(cfg, "Direction", "DL");
[~, symAlloc] = scheduler.defaultBudget(struct());
assert(isequal(double(symAlloc), [2 12]), ...
    "DL default scheduler budget must start after the configured CORESET duration.");
end

function cfg = localBasePDCCHCfg()
cfg = struct();
cfg.run = struct("seed", 77, "totalSlots", 1);
cfg.phy = struct();
cfg.phy.carrier = struct("NCellID", 1, "NSizeGrid", 52, "SubcarrierSpacing", 30);
cfg.phy.numerology = struct("mu", 1);
cfg.phy.fc_Hz = 4e9;
cfg.phy.pdcch = struct("rnti", 4660, "dciPayloadBits", 64);
cfg.channel = struct("model", "AWGN", "fc_Hz", 4e9, "nRxAnt", 1, ...
    "fading", struct("delaySpread_s", 100e-9), "doppler_Hz", 0, "snr_dB", 20);
cfg.ctrl6gr = struct( ...
    "enable", true, "RNTI", 4660, "NumSlots", 1, "NTx", 1, "NRx", 1, ...
    "ChannelModel", "AWGN", "DelaySpread", 100e-9, "DopplerHz", 0, "SNRdB", 20, ...
    "NoiseVarianceMode", "from_snr_db", "ChannelEstimationMode", "realistic", ...
    "EqualizerType", "MMSE", "BlindDetectionEnabled", true, "MonitoringPeriodicitySlots", 1, ...
    "EnableCSS", true, "EnableUSS", true, "EnableMRSS", false, "EnableRepetition", false, ...
    "RepetitionMode", "none", "RepetitionCount", 1, "EnableTransmitDiversity", false, ...
    "DiversityMode", "single_port_baseline", "PrecoderGranularity", "none", "Seed", 77, ...
    "PayloadLengthBits", 64, "Modulation", "QPSK", "CRCPolynomial", "24C", ...
    "CRCScramblingEnabled", true, "PayloadScramblingEnabled", true, ...
    "PayloadSequenceInit", 1, "WaveformMode", "grid_mode", ...
    "RepetitionCombiningMode", "coherent", ...
    "CORESET", struct("CORESETID", 0, "DurationSymbols", 1, "StartSymbol", 0, ...
        "FrequencyAllocationMode", "contiguous", "NumRB", 24, "RBStart", 0, "RBSetList", [], ...
        "REGSizeRE", 12, "REGBundleSize", 2, "InterleavingEnabled", false, "InterleaverSize", 2, ...
        "ShiftIndex", 1, "NumREGPerCCE", 6, "REGIndexingMode", "sequential_reg_groups", ...
        "MappingType", "noninterleaved", "DMRSPortSet", 0, "DMRSAdditionalPositions", 0, ...
        "DMRSConfigType", "single_port_density_3_per_rb", "AssociatedSearchSpaceIDs", [1 2]), ...
    "SearchSpaces", struct("SearchSpaceID", 1, "SearchSpaceType", "USS", ...
        "AssociatedCORESETID", 0, "MonitoringSymbolsWithinSlot", 0, ...
        "MonitoringSlotsPeriodicity", 1, "MonitoringSlotOffset", 0, ...
        "CandidateCountPerAL", struct("AL1", 0, "AL2", 0, "AL4", 1, "AL8", 0, "AL16", 0), ...
        "AggregationLevels", 4, "HashFunctionMode", "baseline_hash", ...
        "EnableSlotLevelMonitoring", true, "EnableNonSlotMonitoringStudy", false, ...
        "UETransparentToMRSS", true));
end

function localAssertError(fcn, expectedId)
try
    fcn();
catch ME
    assert(strcmp(ME.identifier, expectedId), ...
        "Expected error '%s' but got '%s'.", expectedId, ME.identifier);
    return;
end
error("testLLSExtendedPhysicalGuards:ExpectedError", ...
    "Expected error '%s' was not thrown.", expectedId);
end

function s = localRemoveNested(s, path)
parts = split(string(path), ".");
s = localRemoveNestedParts(s, parts);
end

function s = localRemoveNestedParts(s, parts)
if isempty(parts) || ~isstruct(s)
    return;
end
field = char(parts(1));
if ~isfield(s, field)
    return;
end
if numel(parts) == 1
    s = rmfield(s, field);
    return;
end
child = s.(field);
child = localRemoveNestedParts(child, parts(2:end));
s.(field) = child;
end
