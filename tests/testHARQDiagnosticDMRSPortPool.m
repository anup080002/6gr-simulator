function ok = testHARQDiagnosticDMRSPortPool()
%TESTHARQDIAGNOSTICDMRSPORTPOOL Derive active ports after rank changes.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
tmp = tempname;
mkdir(tmp);
cleanup = onCleanup(@() localCleanup(tmp)); %#ok<NASGU>

cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.run.strictMode = false;
cfg.run.pdschExecutionProfile = "phy_calibration";
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.channel.model = "AWGN";
cfg.channel.awgnOnly = true;
cfg.channel.snr_dB = 30;
cfg.phy.carrier.NSizeGrid = 12;
cfg.phy.carrier.SubcarrierSpacing = 30;
cfg.phy.pdsch.enable = true;
cfg.phy.pdsch.prbSet = 0:5;
cfg.phy.pdsch.symbolAllocation = [0 10];
cfg.phy.pdsch.modulation = "QPSK";
cfg.phy.pdsch.codeRate = 0.30;
cfg.phy.pdsch.executionProfile = "phy_calibration";
cfg.phy.pdsch.mcsTable = "calibration_explicit";
cfg.phy.pdsch.mcsIndex = 0;
cfg.phy.pdsch.nLayers = 1;
cfg.phy.pdsch.numLayers = 1;
cfg.phy.pdsch.dmrs.portSet = [0 1];
cfg.phy.pdsch.dmrs.DMRSPortSet = [0 1];
cfg.phy.pdsch.dmrs.nPorts = 2;
cfg.pdsch6gr.DMRSPortSet = [0 1];
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
assert(istable(artifacts.PacketTable) && ...
    ~isempty(artifacts.PacketTable), ...
    "Rank-one HARQ probe with a two-port configured pool emitted no waveform evidence.");
ok = true;
end

function localCleanup(pathText)
if isfolder(pathText)
    rmdir(pathText, "s");
end
end
