function ok = testPHYGrantCanonicalDimensions()
%TESTPHYGRANTCANONICALDIMENSIONS Frozen grant dimension contract anchors.

setup6GRSimToolkit("Verbose", false);
if ~localHaveRequired5G()
    ok = true;
    return;
end

cfgDL = localBaseCfg();
cfgDL.scenario.bs.nTxAnt = 64;
cfgDL.scenario.ue.nRxAnt = 4;
cfgDL.antenna.bs.numElements = 64;
cfgDL.antenna.ue.numElements = 4;
cfgDL.phy.nTxAnt = 64;
cfgDL.channel.nTxAnt = 64;
cfgDL.phy.nRxAnt = 4;
cfgDL.channel.nRxAnt = 4;
cfgDL.phy.pdsch.numLayers = 2;
cfgDL.phy.pdsch.nLayers = 2;
cfgDL.phy.pdsch.numPorts = 2;
cfgDL.phy.pdsch.nPorts = 2;
cfgDL.phy.pdsch.precoding.matrix = eye(2);
cfgDL.phy.pdsch.precodingMatrix = eye(2);
cfgDL.phy.pdsch.W = eye(2);

dlGrant = localGrant("DL", 101, 2);
dlGrant.NumLogicalPorts = 2;
dlGrant.PrecodingMatrix = eye(2);
dlGrant.PrecodingActive = true;
dlPHYGrant = sixgr.phy.grant.freezePHYGrant(cfgDL, "DL", dlGrant, "SNR_dB", 30, "Frame", 1, "Slot", 1);
assert(dlPHYGrant.AntennaArchitecture.NumElements == 64, "DL NumElements must keep the gNB array size.");
assert(dlPHYGrant.AntennaArchitecture.NumLogicalPorts == 2, "DL logical ports must be 2.");
assert(dlPHYGrant.AntennaArchitecture.NumLayers == 2, "DL layers must be 2.");
assert(dlPHYGrant.AntennaArchitecture.NumWaveformColumns == 2, "DL waveform columns must follow logical ports, not elements.");
assert(dlPHYGrant.AntennaArchitecture.NumRxAntennas == 4, "DL receiver antennas must follow UE Rx.");
assert(isequal(size(dlPHYGrant.PrecodingState.Matrix), [2 2]), "DL frozen W must be 2x2.");

[txDL, infoDL] = sixgr.phy.dl.PDSCH_Tx(cfgDL, "PHYGrant", dlPHYGrant);
assert(size(txDL.Waveform, 2) == 2, "DL waveform must have exactly two columns.");
assert(size(txDL.Grid, 3) == 2, "DL grid must have exactly two primary pages for this anchor.");
assert(infoDL.Precoding.NumPorts == 2 && infoDL.Precoding.NumLayers == 2, ...
    "DL runtime precoding must preserve the frozen 2-port/2-layer contract.");

ctx = struct("GrantSnapshot", dlGrant);
job = sixgr.truth.buildGrantPHYJob(cfgDL, "DL", 30, 1, struct(), ctx);
localAssertSamePhysicalGrant(dlPHYGrant, job.PHYGrant, "buildGrantPHYJob");
exec = sixgr.truth.executeGrantPHYJob(job);
localAssertSamePhysicalGrant(job.PHYGrant, exec.PHYGrant, "executeGrantPHYJob");
execGrant = sixgr.util.structGet(sixgr.util.structGet(exec.Result, "HARQ", struct()), "GrantSnapshot", struct());
execPHYGrant = sixgr.util.structGet(execGrant, "PHYGrant", struct());
localAssertSamePhysicalGrant(job.PHYGrant, execPHYGrant, "throughput_harq_snapshot");

cfgUL = localBaseCfg();
cfgUL.scenario.ue.nTxAnt = 4;
cfgUL.scenario.bs.nRxAnt = 64;
cfgUL.antenna.ue.numElements = 4;
cfgUL.antenna.bs.numElements = 64;
cfgUL.phy.pusch.numLayers = 1;
cfgUL.phy.pusch.nLayers = 1;
cfgUL.phy.pusch.NumAntennaPorts = 4;
cfgUL.phy.pusch.numPorts = 4;
cfgUL.phy.pusch.nPorts = 4;
cfgUL.channel.ul.nTxAnt = 4;
cfgUL.channel.ul.nRxAnt = 64;

ulGrant = localGrant("UL", 201, 1);
ulGrant.NumLogicalPorts = 4;
ulGrant.NumTxAnt = 4;
ulPHYGrant = sixgr.phy.grant.freezePHYGrant(cfgUL, "UL", ulGrant, "SNR_dB", 30, "Frame", 1, "Slot", 1);
assert(ulPHYGrant.AntennaArchitecture.NumElements == 4, "UL Tx elements must be UE Tx elements.");
assert(ulPHYGrant.AntennaArchitecture.NumLogicalPorts == 4, "UL logical ports must be UE ports.");
assert(ulPHYGrant.AntennaArchitecture.NumWaveformColumns == 4, "UL waveform columns must be UE Tx ports.");
assert(ulPHYGrant.AntennaArchitecture.NumRxAntennas == 64, "UL receiver antennas must be gNB Rx antennas.");

[txUL, infoUL] = sixgr.phy.ul.PUSCH_Tx(cfgUL, "PHYGrant", ulPHYGrant);
assert(size(txUL.Waveform, 2) == 4, "UL waveform must have four UE Tx columns.");
assert(size(txUL.Grid, 3) == 4, "UL grid must have four UE Tx pages.");
assert(double(txUL.PUSCH.NumAntennaPorts) == 4, "UL PUSCH NumAntennaPorts must stay 4.");
assert(infoUL.Precoding.NumPorts == 4, "UL runtime precoding port count must stay 4.");

badPHYGrant = dlPHYGrant;
badPHYGrant.PrecodingState.Matrix = ones(3, 2);
badPHYGrant.PrecodingState.MatrixRows = 3;
try
    sixgr.phy.dl.PDSCH_Tx(cfgDL, "PHYGrant", badPHYGrant);
    error("testPHYGrantCanonicalDimensions:MissingNegativeGuard", ...
        "Expected frozen grant shape validation to fail before waveform generation.");
catch ME
    assert(strcmp(ME.identifier, "sixgr:phy:grant:PrecodingMatrixShapeMismatch"), ...
        "Unexpected negative guard identifier: %s", ME.identifier);
end

ok = true;
end

function cfg = localBaseCfg()
cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.run.numFrames = 1;
cfg.run.strictMode = false;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.channel.model = "AWGN";
cfg.channel.awgnOnly = true;
cfg.channel.snr_dB = 30;
cfg.phy.carrier.NSizeGrid = 12;
cfg.phy.pdsch.enable = true;
cfg.phy.pdsch.prbSet = 0:5;
cfg.phy.pdsch.symbolAllocation = [0 10];
cfg.phy.pdsch.modulation = "QPSK";
cfg.phy.pdsch.codeRate = 0.35;
cfg.phy.pdsch.enablePTRS = false;
cfg.phy.csirs.enable = false;
cfg.phy.pusch.enable = true;
cfg.phy.pusch.prbSet = 0:5;
cfg.phy.pusch.symbolAllocation = [0 10];
cfg.phy.pusch.modulation = "QPSK";
cfg.phy.pusch.codeRate = 0.35;
cfg.phy.pusch.enablePTRS = false;
end

function grant = localGrant(direction, rnti, nLayers)
grant = struct();
grant.Direction = char(direction);
grant.Frame = 1;
grant.Slot = 1;
grant.RNTI = double(rnti);
grant.UEIndex = 1;
grant.ServingCell = 1;
grant.PRBSet = 0:5;
grant.SymbolAllocation = [0 10];
grant.Modulation = "QPSK";
grant.NumLayers = double(nLayers);
grant.Layers = double(nLayers);
grant.TargetCodeRate = 0.35;
grant.MCSIndex = 4;
grant.MCS = 4;
grant.GrantContextId = sprintf('%s|cell=1|ue=1|rnti=%d|frame=1|slot=1', char(direction), rnti);
grant.HARQ = struct("HarqID", 0, "NDI", true, "RV", 0, "IsRetransmission", false);
end

function localAssertSamePhysicalGrant(expected, actual, label)
assert(isstruct(actual) && ~isempty(fieldnames(actual)), "%s did not carry a PHYGrant.", label);
assert(strcmp(char(expected.Direction), char(actual.Direction)), "%s direction changed.", label);
assert(isequal(expected.ResourceAllocation.PRBSet, actual.ResourceAllocation.PRBSet), "%s PRBSet changed.", label);
assert(isequal(expected.ResourceAllocation.SymbolAllocation, actual.ResourceAllocation.SymbolAllocation), "%s SymbolAllocation changed.", label);
fields = ["NumElements","NumLogicalPorts","NumLayers","NumCodewords","NumWaveformColumns","NumRxAntennas"];
for i = 1:numel(fields)
    f = char(fields(i));
    assert(double(expected.AntennaArchitecture.(f)) == double(actual.AntennaArchitecture.(f)), ...
        "%s AntennaArchitecture.%s changed.", label, f);
end
assert(isequal(expected.PrecodingState.Matrix, actual.PrecodingState.Matrix), "%s PrecodingState.Matrix changed.", label);
end

function tf = localHaveRequired5G()
tf = exist("nrPDSCH", "file") == 2 && ...
    exist("nrPDSCHDecode", "file") == 2 && ...
    exist("nrPUSCH", "file") == 2 && ...
    exist("nrPUSCHDecode", "file") == 2 && ...
    exist("nrPDSCHPrecode", "file") == 2;
end
