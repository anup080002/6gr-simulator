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

cfgHybridDL = cfgDL;
cfgHybridDL.phy.beamManagement.hybridBeamformingEnabled = true;
cfgHybridDL.mimo.strict = true;
cfgHybridDL.phy.pdsch.normalizePrecodingMatrix = false;
cfgHybridDL.antenna.bs.numRFChains = 2;
cfgHybridDL.rf.bs.numRFChains = 2;
dlArch = sixgr.rf.AntennaArrayFactory.resolvePortArchitecture(cfgHybridDL, "bs", ...
    "Signal", "PDSCH", "NumElements", 64, "NumPorts", 2, "MinimumPorts", 2);
dlHybridGrant = dlGrant;
dlLogicalW = 0.5 * [1 1; 1 -1];
dlHybridGrant.PrecodingMatrixLogicalPorts = dlLogicalW;
dlHybridGrant.PrecodingMatrix = dlArch.HybridElementToPortMatrix * dlLogicalW;
dlHybridPHYGrant = sixgr.phy.grant.freezePHYGrant(cfgHybridDL, "DL", dlHybridGrant, ...
    "SNR_dB", 30, "Frame", 1, "Slot", 1);
assert(dlHybridPHYGrant.AntennaArchitecture.NumLogicalPorts == 2, ...
    "Hybrid DL must keep two logical NR ports.");
assert(dlHybridPHYGrant.AntennaArchitecture.NumWaveformColumns == 64, ...
    "Hybrid DL must emit all 64 configured gNB element-domain columns.");
assert(dlHybridPHYGrant.PrecodingState.HybridElementDomainApplied, ...
    "Hybrid DL element-domain state must be explicit in the frozen grant.");
assert(isequal(size(dlHybridPHYGrant.PrecodingState.MatrixLogicalPorts), [2 2]), ...
    "Hybrid DL logical precoder must remain 2x2.");
assert(isequal(size(dlHybridPHYGrant.PrecodingState.Matrix), [64 2]), ...
    "Hybrid DL physical precoder must be 64x2.");
assert(isequal(dlHybridPHYGrant.PrecodingState.Matrix, dlHybridGrant.PrecodingMatrix), ...
    "Frozen hybrid DL precoding must not normalize or replace the selected physical beam.");
assert(string(dlHybridPHYGrant.PrecodingState.SelectedMatrixSHA256) == ...
    sixgr.phy.mimo.MatrixContract.digest(dlHybridGrant.PrecodingMatrix), ...
    "Frozen hybrid DL precoding must carry the exact physical matrix identity.");
[txHybridDL, infoHybridDL] = sixgr.phy.dl.PDSCH_Tx(cfgHybridDL, "PHYGrant", dlHybridPHYGrant);
assert(size(txHybridDL.Waveform, 2) == 64, ...
    "Hybrid DL waveform must exercise all 64 configured gNB elements.");
assert(infoHybridDL.Precoding.NumLogicalPorts == 2 && infoHybridDL.Precoding.NumPorts == 64, ...
    "Hybrid DL runtime must report two logical ports and 64 physical waveform ports.");

% Grant hydration is allowed to resolve an explicit RF-chain partition that
% is not otherwise present in the broader replay config.  Freezing must use
% that exact architecture instead of silently rebuilding a different F_RF.
cfgHydratedReplay = cfgHybridDL;
cfgHydratedReplay.antenna.bs = rmfield(cfgHydratedReplay.antenna.bs, "numRFChains");
cfgHydratedReplay.rf.bs = rmfield(cfgHydratedReplay.rf.bs, "numRFChains");
hydratedArch = sixgr.rf.AntennaArrayFactory.resolvePortArchitecture(cfgHydratedReplay, "bs", ...
    "Signal", "PDSCH", "NumElements", 64, "NumPorts", 2, ...
    "NumRFChains", 4, "MinimumPorts", 2);
hydratedGrant = dlHybridGrant;
hydratedGrant.NumRFChains = 4;
hydratedGrant.HybridElementToPortMatrix = hydratedArch.HybridElementToPortMatrix;
hydratedGrant.PrecodingMatrix = hydratedArch.HybridElementToPortMatrix * dlLogicalW;
hydratedPHYGrant = sixgr.phy.grant.freezePHYGrant(cfgHydratedReplay, "DL", hydratedGrant, ...
    "SNR_dB", 30, "Frame", 1, "Slot", 1);
assert(hydratedPHYGrant.AntennaArchitecture.NumRFChains == 4, ...
    "Frozen hybrid DL grant must retain the architecture's resolved RF-chain count.");
assert(isequal(hydratedPHYGrant.PrecodingState.HybridElementToPortMatrix, ...
    hydratedArch.HybridElementToPortMatrix), ...
    "Frozen hybrid DL grant must retain the exact authoritative element-to-port matrix.");
assert(isequal(hydratedPHYGrant.PrecodingState.Matrix, hydratedGrant.PrecodingMatrix), ...
    "Frozen hybrid DL grant must retain the exact hydrated physical precoder.");

% A per-user codebook beam is an authoritative combined element-to-port
% mapping.  It must remain physical while the NR precoder stays 2x2.
selectedElementBeam = exp(1j * 2*pi*(0:63).' * [0 1] / 64) / sqrt(128);
cfgSelectedBeam = cfgHybridDL;
cfgSelectedBeam.antenna.bs = rmfield(cfgSelectedBeam.antenna.bs, "numRFChains");
cfgSelectedBeam.rf.bs = rmfield(cfgSelectedBeam.rf.bs, "numRFChains");
cfgSelectedBeam.phy.pdsch.hybridElementToPortMatrix = selectedElementBeam;
cfgSelectedBeam.phy.pdsch.numRFChains = 2;
cfgSelectedBeam.phy.pdsch.precoding.matrix = eye(2);
cfgSelectedBeam.phy.pdsch.NumAntennaPorts = 2;
cfgSelectedBeam.phy.pdsch.numAntennaPorts = 2;
cfgSelectedBeam.phy.pdsch.selectedPrecoderSHA256 = char( ...
    sixgr.phy.mimo.MatrixContract.digest(selectedElementBeam));
genericSelectedArch = sixgr.rf.AntennaArrayFactory.resolvePortArchitecture( ...
    cfgSelectedBeam, "bs", "NumElements", 64);
pdschSelectedArch = sixgr.rf.AntennaArrayFactory.resolvePortArchitecture( ...
    cfgSelectedBeam, "bs", "Signal", "PDSCH", "NumElements", 64, ...
    "MinimumPorts", 2);
assert(genericSelectedArch.NumLogicalPorts == 64 && genericSelectedArch.NumRFChains == 64, ...
    "Generic 64-element array construction must not inherit PDSCH-only RF-chain limits.");
assert(pdschSelectedArch.NumLogicalPorts == 2 && pdschSelectedArch.NumRFChains == 2, ...
    "PDSCH signal view must keep two logical ports and two signal-specific RF chains.");
selectedBeamGrant = dlGrant;
selectedBeamGrant.PrecodingMatrixLogicalPorts = eye(2);
selectedBeamPHYGrant = sixgr.phy.grant.freezePHYGrant(cfgSelectedBeam, "DL", ...
    selectedBeamGrant, "SNR_dB", 30, "Frame", 1, "Slot", 1);
assert(isequal(selectedBeamPHYGrant.PrecodingState.Matrix, selectedElementBeam), ...
    "Frozen hybrid grant must apply the selected combined element-domain beam exactly once.");
assert(isequal(selectedBeamPHYGrant.PrecodingState.MatrixLogicalPorts, eye(2)), ...
    "Selected element-domain beam must not replace the 2x2 logical NR precoder.");
[txSelectedBeam, infoSelectedBeam] = sixgr.phy.dl.PDSCH_Tx( ...
    cfgSelectedBeam, "PHYGrant", selectedBeamPHYGrant);
assert(size(txSelectedBeam.Waveform, 2) == 64 && ...
    all(sum(abs(txSelectedBeam.Waveform).^2, 1) > 0) && ...
    all(double(infoSelectedBeam.CodewordLayerMapping.LayerColumnEnergy) > 0), ...
    "Selected hybrid user beam must execute all 64 waveform columns and both layers.");

cfgJob = sixgr.config.normalizeConfig(cfgDL);
cfgJob = withCanonicalSchedulerTiming(cfgJob);
resolvedDLGrant = sixgr.link.resolveWaveformGrant(cfgJob, "DL", 1, "Slot", 1);
ctx = struct("GrantSnapshot", resolvedDLGrant);
job = sixgr.truth.buildGrantPHYJob(cfgJob, "DL", 30, 1, struct(), ctx);
localAssertSamePhysicalGrant(resolvedDLGrant.PHYGrant, job.PHYGrant, "buildGrantPHYJob");

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

cfgHybridUL = cfgUL;
cfgHybridUL.phy.pusch.numLayers = 2;
cfgHybridUL.phy.pusch.nLayers = 2;
cfgHybridUL.phy.pusch.NumAntennaPorts = 2;
cfgHybridUL.phy.pusch.numPorts = 2;
cfgHybridUL.phy.pusch.nPorts = 2;
cfgHybridUL.phy.pusch.transmissionScheme = "nonCodebook";
cfgHybridUL.phy.pusch.transformPrecoding = false;
cfgHybridUL.phy.beamManagement.hybridBeamformingEnabled = true;
cfgHybridUL.antenna.ue.numRFChains = 2;
cfgHybridUL.rf.ue.numRFChains = 2;
ulHybridGrant = localGrant("UL", 202, 2);
ulHybridGrant.NumLogicalPorts = 2;
ulHybridGrant.PrecodingMatrixLogicalPorts = eye(2);
ulHybridPHYGrant = sixgr.phy.grant.freezePHYGrant(cfgHybridUL, "UL", ulHybridGrant, ...
    "SNR_dB", 30, "Frame", 1, "Slot", 1);
assert(ulHybridPHYGrant.AntennaArchitecture.NumLogicalPorts == 2, ...
    "Hybrid UL must keep two logical NR ports.");
assert(ulHybridPHYGrant.AntennaArchitecture.NumWaveformColumns == 4, ...
    "Hybrid UL must emit all four configured UE element-domain columns.");
assert(isequal(size(ulHybridPHYGrant.PrecodingState.MatrixLogicalPorts), [2 2]), ...
    "Hybrid UL logical precoder must remain 2x2.");
assert(isequal(size(ulHybridPHYGrant.PrecodingState.Matrix), [4 2]), ...
    "Hybrid UL physical precoder must be 4x2.");
[txHybridUL, infoHybridUL] = sixgr.phy.ul.PUSCH_Tx(cfgHybridUL, "PHYGrant", ulHybridPHYGrant);
assert(size(txHybridUL.Waveform, 2) == 4, ...
    "Hybrid UL waveform must exercise all four configured UE elements.");
assert(infoHybridUL.Precoding.NumLogicalPorts == 2 && infoHybridUL.Precoding.NumPorts == 4, ...
    "Hybrid UL runtime must report two logical ports and four physical waveform ports.");

% Replayed non-codebook grants can retain NumAntennaPorts=NumLayers while
% the configured UE has four logical RF ports.  Freeze and transmit in the
% same 4-port-by-2-layer domain used by the production coupled runtime.
cfgHybridUL4 = cfgHybridUL;
cfgHybridUL4.antenna.ue.numRFChains = 4;
cfgHybridUL4.rf.ue.numRFChains = 4;
cfgHybridUL4.phy.pusch.NumAntennaPorts = 4;
cfgHybridUL4.phy.pusch.numAntennaPorts = 4;
cfgHybridUL4.phy.pusch.numPorts = 4;
cfgHybridUL4.phy.pusch.nPorts = 4;
ulHybrid4Grant = localGrant("UL",203,2);
ulHybrid4PHYGrant = sixgr.phy.grant.freezePHYGrant( ...
    cfgHybridUL4,"UL",ulHybrid4Grant, ...
    "SNR_dB",30,"Frame",1,"Slot",1);
[txHybridUL4,infoHybridUL4] = sixgr.phy.ul.PUSCH_Tx( ...
    cfgHybridUL4,"PHYGrant",ulHybrid4PHYGrant);
assert(size(txHybridUL4.PUSCHPortSymbols,2) == 4 && ...
        size(txHybridUL4.Waveform,2) == 4, ...
    sprintf(['Four-RF-chain hybrid UL replay must execute four logical ports and ' ...
     'four element waveforms; observed logical=%d waveform=%d.'], ...
    size(txHybridUL4.PUSCHPortSymbols,2),size(txHybridUL4.Waveform,2)));
assert(infoHybridUL4.Precoding.NumLogicalPorts == 4 && ...
        infoHybridUL4.Precoding.NumLayers == 2, ...
    "Four-RF-chain hybrid UL replay must preserve the 4-port-by-2-layer runtime contract.");

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
cfg.channel.fading.enable = false;
cfg.channel.bandwidth_Hz = 10e6;
cfg.channel.snr_dB = 30;
cfg.phy.channelBandwidth_MHz = 10;
cfg.phy.carrier.NSizeGrid = 24;
cfg = sixgr.util.structSet(cfg, "phy.numerology.activeGridNumRBs", 24);
cfg = sixgr.util.structSet(cfg, "phy.numerology.configuredGridNumRBs", 24);
cfg.phy.pdsch.enable = true;
cfg.phy.pdsch.executionProfile = "phy_calibration";
cfg.phy.pdsch.mcsContext = struct( ...
    "UECapability1024QAM", false, ...
    "RRCEnabled1024QAM", false, ...
    "DCIEnabled1024QAM", false, ...
    "DeploymentAllows1024QAM", false, ...
    "FrequencyRangeAllows1024QAM", false, ...
    "BandAllows1024QAM", false, ...
    "FrequencyRange", "FR1", ...
    "OperatingBand", "n78", ...
    "DeploymentClass", "controlled_test");
cfg.phy.pdsch.prbSet = 0:5;
cfg.phy.pdsch.symbolAllocation = [2 10];
cfg.phy.pdsch.modulation = "QPSK";
cfg.phy.pdsch.codeRate = 0.587890625;
cfg.phy.pdsch.enablePTRS = false;
cfg.phy.csirs.enable = false;
cfg.phy.pusch.enable = true;
cfg.phy.pusch.prbSet = 0:5;
cfg.phy.pusch.symbolAllocation = [2 10];
cfg.phy.pusch.modulation = "QPSK";
cfg.phy.pusch.codeRate = 0.587890625;
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
grant.SymbolAllocation = [2 10];
grant.Modulation = "QPSK";
grant.NumLayers = double(nLayers);
grant.Layers = double(nLayers);
grant.TargetCodeRate = 0.587890625;
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
