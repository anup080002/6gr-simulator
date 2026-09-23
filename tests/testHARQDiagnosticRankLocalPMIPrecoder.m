function ok = testHARQDiagnosticRankLocalPMIPrecoder()
%TESTHARQDIAGNOSTICRANKLOCALPMIPRECODER Rebuild a rank-local PMI matrix.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
tmp = tempname;
mkdir(tmp);
cleanup = onCleanup(@() localCleanup(tmp)); %#ok<NASGU>

cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.run.strictMode = true;
cfg.run.pdschExecutionProfile = "phy_calibration";
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.channel.model = "AWGN";
cfg.channel.awgnOnly = true;
cfg.channel.snr_dB = 30;
cfg.mimo.strict = true;
cfg.phy.mimo.profileID = "fr1_typeI_single_panel_strict";
cfg.phy.mimo.panels = 1;
cfg.phy.mimo.N1 = 1;
cfg.phy.mimo.N2 = 1;
cfg.phy.mimo.O1 = 1;
cfg.phy.mimo.O2 = 1;
cfg.phy.carrier.NSizeGrid = 24;
cfg.channel.bandwidth_Hz = 10e6;
cfg.phy.ssb.enable = false;
cfg.phy.carrier.SubcarrierSpacing = 30;
cfg.phy.pdsch.enable = true;
cfg.phy.pdsch.prbSet = 0:5;
cfg.phy.pdsch.symbolAllocation = [0 10];
cfg.phy.pdsch.SymbolAllocation = [0 10];
cfg.phy.pdsch.mappingType = "A";
cfg.phy.pdsch.MappingType = "A";
cfg.phy.pdsch.modulation = "QPSK";
cfg.phy.pdsch.codeRate = 0.30;
cfg.phy.pdsch.executionProfile = "phy_calibration";
cfg.phy.pdsch.mcsTable = "calibration_explicit";
cfg.phy.pdsch.mcsIndex = 0;
cfg.phy.pdsch.nLayers = 1;
cfg.phy.pdsch.numLayers = 1;
cfg.phy.pdsch.nPorts = 2;
cfg.phy.pdsch.numPorts = 2;
cfg.phy.pdsch.precoding.matrix = eye(2);
cfg.phy.pdsch.precodingMatrix = [];
cfg.phy.pdsch.W = [];
cfg.phy.pdsch.tpmi = [];
cfg.phy.pdsch.TPMI = [];
cfg.phy.pdsch.pmi = 0;
cfg.phy.pdsch.PMI = 0;
cfg.phy.pdsch.normalizePrecodingMatrix = false;
cfg.phy.csi.codebookType = "type1";
cfg.phy.csi.pmiCodebookMode = "type1_su_mimo";
cfg.phy.harq.enable = true;
cfg.phy.harq.validationMode = "observation";

opt = struct( ...
    "LinkSNR_dB", 30, ...
    "LinkSNRGrid_dB", 30, ...
    "LinkSweepFrames", 1, ...
    "LinkSweepMaxPoints", 1, ...
    "HARQLivePreview", true, ...
    "HARQProbeDirections", "DL", ...
    "HARQProbePackets", 1);
artifacts = sixgr.truth.exportLLSHARQDiagnostics( ...
    cfg, fullfile(tmp, "run", "air_interface"), opt);

assert(istable(artifacts.PacketTable) && ~isempty(artifacts.PacketTable), ...
    "Rank-local PMI HARQ probe emitted no real waveform packet evidence.");
assert(all(string(artifacts.PacketTable.Direction) == "DL"), ...
    "Rank-local PMI HARQ probe emitted an unexpected direction.");
disp(artifacts.PacketTable(:,["SNR_dB","MeasuredSINR_dB","CurrentDecodeOK"]));
T = artifacts.PacketTable;
assert(all(T.CurrentDecodeOK) && all(isfinite(T.MeasuredSINR_dB)), ...
    "High-SNR probe must decode and export actual post-EQ SINR.");
assert(all(abs(T.AppliedNoiseSNR_dB-T.SNR_dB)<1e-10));
assert(all(abs(10*log10(T.MeasuredInjectedGridNoiseVariance./T.GridNoiseVariance))<0.8), ...
    "Demodulated injected-noise variance must agree with the fixed reference.");
assert(all(T.NoiseCalibrationSource == "sixgr.phy.waveform.addOccupiedREAWGN"));
assert(all(abs(T.GridNoiseVariance-T.SampleNoiseVariance.* ...
    T.SampleToGridNoiseVarianceGain)<1e-12));
ok = true;
end

function localCleanup(pathText)
if isfolder(pathText)
    rmdir(pathText, "s");
end
end
