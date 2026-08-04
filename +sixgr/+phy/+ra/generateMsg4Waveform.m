function [tx, sched] = generateMsg4Waveform(cfg, raCfg, msg4)
%GENERATEMSG4WAVEFORM Carry contention resolution on temp C-RNTI PDSCH.
cfgTx = sixgr.phy.ra.localizeCarrierConfig(cfg, raCfg);
[carrier, ~] = sixgr.phy.grid.makeCarrier(cfgTx);
sched = localMsg4Schedule(raCfg);
cfgTx = sixgr.phy.ra.localizeRAPDSCHConfig(cfgTx, sched.PDSCH);
cfgTx.phy.pdcch.rnti = double(raCfg.TempCRNTI);
cfgTx.phy.pdcch.KBits = double(raCfg.DCIPayloadBits);
cfgTx.phy.pdcch.dciPayloadBits = double(raCfg.DCIPayloadBits);
cfgTx.phy.pdcch.blindSearch = logical(sixgr.util.structGet(cfg, ...
    "phy.pdcch.blindSearch", false));
sixgr.config.assertRuntimeFeatureUse(cfgTx, "pdcch_blind_search", ...
    cfgTx.phy.pdcch.blindSearch, "generateMsg4Waveform");
cfgTx.phy.pdcch.allowBlindCandidateTimingEstimate = false;
cfgTx.phy.pdcch.aggregationLevel = 4;
cfgTx.phy.pdcch.searchSpace.numCandidates = [0 0 1 0 0];
cfgTx = sixgr.phy.ra.localizeRAPDCCHConfig(cfgTx, carrier);

[pdcchTx, pdcchInfo] = sixgr.phy.dl.PDCCH_Tx(cfgTx, "Carrier", carrier, ...
    "DCIBits", sched.DCIBits, "K", double(raCfg.DCIPayloadBits), ...
    "RNTI", double(raCfg.TempCRNTI), "NCellID", double(raCfg.NCellID), ...
    "OFDMModulate", true);
sched.PDCCH = pdcchTx.PDCCH;
[controlRx, controlInfo] = sixgr.phy.dl.PDCCH_Rx( ...
    pdcchTx.Waveform, cfgTx, "Carrier", carrier, ...
    "PDCCH", pdcchTx.PDCCH, "K", double(raCfg.DCIPayloadBits), ...
    "RNTI", double(raCfg.TempCRNTI), ...
    "ExpectedDCIBits", int8(sched.DCIBits(:)));
controlEvent = sixgr.pdsch.RASIPDSCHContext.decodedControlEvent( ...
    controlRx, controlInfo, "msg4_contention_resolution", ...
    double(raCfg.TempCRNTI), "1_0", sched.DCIBits, ...
    "PDCCHAbsoluteSlot", double(raCfg.Msg4Slot), ...
    "PDCCHDataIndicesOneBased", pdcchTx.PDCCHInd, ...
    "PDCCHDMRSIndicesOneBased", pdcchTx.DMRSInd, ...
    "EvidenceRole", "transmit_loopback_decode");
strict = sixgr.pdsch.RASIPDSCHContext.materialize( ...
    carrier, sched.PDSCH, controlEvent, ...
    localProcedureContext(cfgTx, raCfg, sched), ...
    "ChannelModel", "AWGN");
tbBits = localPadBits(msg4.PayloadBits, strict.TransportBlockSize);
[pdschTx, pdschInfo] = sixgr.phy.dl.PDSCH_Tx(cfgTx, ...
    "Carrier", carrier, ...
    "TransportBlockBits", tbBits, ...
    "Assignment", strict.Assignment, ...
    "ResourcePlan", strict.ResourcePlan, ...
    "ReferenceSignalConfig", strict.ReferenceSignalConfig, ...
    "PrecoderBundle", strict.PrecoderBundle, ...
    "IntegrationContext", strict.IntegrationContext, ...
    "ExecutionProfile", "ra_si_strict");
grid = localAddGrids(pdcchTx.Grid, pdschTx.Grid);
tx = struct();
tx.Carrier = carrier;
tx.Grid = grid;
tx.Waveform = sixgr.phy.waveform.ofdmModulate(carrier, grid);
tx.PDCCH = pdcchTx;
tx.PDSCH = pdschTx;
tx.Msg4 = msg4;
tx.Msg4BitLength = double(numel(msg4.PayloadBits));
tx.TransportBlockSize = double(pdschTx.TransportBlockSize);
tx.PDCCHInfo = pdcchInfo;
tx.PDSCHInfo = pdschInfo;
tx.PDSCHControlEvent = strict.ControlEvent;
tx.PDSCHAssignment = strict.Assignment;
tx.PDSCHResourcePlan = strict.ResourcePlan;
tx.PDSCHReferenceSignalConfig = strict.ReferenceSignalConfig;
tx.PDSCHPrecoderBundle = strict.PrecoderBundle;
tx.PDSCHIntegrationContext = strict.IntegrationContext;
tx.PDSCHExecutionProfile = "ra_si_strict";
tx.RAPDSCHConfig = localPDSCHEvidence( ...
    cfgTx, sched.PDSCH, pdschInfo, strict);
sched.PDSCHExecutionProfile = "ra_si_strict";
sched.PDSCHControlEventId = strict.ControlEvent.Id;
end

function sched = localMsg4Schedule(raCfg)
pdsch = nrPDSCHConfig;
s = raCfg.Msg4PDSCH;
pdsch.PRBSet = double(s.PRBStart):(double(s.PRBStart) + double(s.NumPRB) - 1);
pdsch.SymbolAllocation = [double(s.SymbolStart) double(s.NumSymbols)];
pdsch.Modulation = char(string(s.Modulation));
pdsch.NumLayers = double(s.NLayers);
pdsch.RNTI = double(raCfg.TempCRNTI);
pdsch.NID = double(raCfg.NCellID);
pdsch.MappingType = "A";
pdsch.DMRS.DMRSConfigurationType = 1;
pdsch.DMRS.DMRSTypeAPosition = 2;
pdsch.DMRS.DMRSAdditionalPosition = 0;
pdsch.DMRS.DMRSLength = 1;
pdsch.DMRS.NumCDMGroupsWithoutData = 1;
pdsch.DMRS.NIDNSCID = double(raCfg.NCellID);
pdsch.DMRS.NSCID = 0;
pdsch.DMRS.DMRSPortSet = 0;
pdsch.EnablePTRS = logical(sixgr.util.structGet(s, "EnablePTRS", false));
if pdsch.EnablePTRS
    pdsch.PTRS.PTRSPortSet = double(sixgr.util.structGet(s, "PTRSPortSet", 0));
    pdsch.PTRS.TimeDensity = double(sixgr.util.structGet(s, "PTRSTimeDensity", 1));
    pdsch.PTRS.FrequencyDensity = double(sixgr.util.structGet(s, "PTRSFrequencyDensity", 2));
    pdsch.PTRS.REOffset = char(string(sixgr.util.structGet(s, "PTRSREOffset", "00")));
end
sched = struct();
sched.RNTI = double(raCfg.TempCRNTI);
sched.DCIFormat = "1_0";
sched.DCIBits = int8([localIntToBits(s.PRBStart, 8); localIntToBits(s.NumPRB, 8); ...
    localIntToBits(s.SymbolStart, 4); localIntToBits(s.NumSymbols, 4); ...
    localIntToBits(s.MCS, 5); localIntToBits(s.RV, 2); 1]);
sched.PDSCH = pdsch;
sched.TargetCodeRate = double(s.TargetCodeRate);
sched.RV = double(s.RV);
end

function bits = localIntToBits(value, nBits)
value = uint32(max(0, round(double(value))));
bits = zeros(nBits, 1, "int8");
for ii = 1:nBits
    bits(ii) = int8(bitand(bitshift(value, -(nBits - ii)), 1));
end
end

function bits = localPadBits(src, nBits)
src = int8(src(:) ~= 0);
nBits = round(double(nBits));
if numel(src) > nBits
    error("sixgr:phy:ra:Msg4PayloadTooLarge", "Msg4 payload has %d bits but TBS is %d.", numel(src), nBits);
end
bits = zeros(nBits, 1, "int8");
bits(1:numel(src)) = src;
end

function grid = localAddGrids(a, b)
sa = localGridSize(a);
sb = localGridSize(b);
sz = max([sa; sb], [], 1);
a2 = complex(zeros(sz, "like", a));
b2 = complex(zeros(sz, "like", b));
a2(1:sa(1), 1:sa(2), 1:sa(3)) = reshape(a, sa);
b2(1:sb(1), 1:sb(2), 1:sb(3)) = reshape(b, sb);
grid = a2 + b2;
end

function sz = localGridSize(x)
sz = [size(x, 1), size(x, 2), max(1, size(x, 3))];
end

function ev = localPDSCHEvidence(cfgTx, pdsch, info, strict)
prec = strict.PrecoderBundle;
ev = struct();
ev.NumLayers = double(pdsch.NumLayers);
ev.ConfiguredNumPorts = double(sixgr.util.structGet(cfgTx, "phy.pdsch.numPorts", NaN));
ev.ConfiguredNPorts = double(sixgr.util.structGet(cfgTx, "phy.pdsch.nPorts", NaN));
ev.ExplicitMatrixPresent = ~isempty(sixgr.util.structGet(cfgTx, "phy.pdsch.precoding.matrix", []));
ev.ResolvedNumPorts = double(prec.NPhysicalTxAntennas);
ev.ResolvedNumLayers = double(prec.NLayerPorts);
ev.PrecodingActive = true;
ev.PrecodingMode = string(prec.Mode);
ev.PrecodingSource = string(prec.MatrixSource);
ev.AssignmentId = strict.Assignment.AssignmentId;
ev.ExecutionProfile = "ra_si_strict";
ev.CanonicalDelegation = logical(sixgr.util.structGet( ...
    info, "CanonicalDelegation", false));
end

function context = localProcedureContext(cfg, raCfg, sched)
context = struct( ...
    "Procedure", "msg4_contention_resolution", ...
    "RNTI", double(raCfg.TempCRNTI), ...
    "RNTIType", "TC-RNTI", ...
    "UEId", double(raCfg.UEId), ...
    "ServingCellId", double(raCfg.NCellID), ...
    "SchedulingCellId", double(raCfg.NCellID), ...
    "CCId", 0, "BWPId", 0, "ConfigurationEpoch", 0, ...
    "PDCCHAbsoluteSlot", double(raCfg.Msg4Slot), ...
    "PDSCHAbsoluteSlot", double(raCfg.Msg4Slot), ...
    "K0", 0, "MCSTable", "qam64", ...
    "MCSIndex", double(raCfg.Msg4PDSCH.MCS), ...
    "TargetCodeRate", double(sched.TargetCodeRate), ...
    "XOverhead", sixgr.phy.dl.resolvePDSCHXOverhead( ...
        cfg, sched.PDSCH.SymbolAllocation), ...
    "RV", double(sched.RV), "NDI", 1, ...
    "HARQProcessId", 0, "TCIStateId", 0, ...
    "ActiveBWPContextPresent", true, "EpochCurrent", true, ...
    "ServingCellActive", true, "MCSContextSupported", true, ...
    "TCIStateActive", true, "UECapability1024QAM", false, ...
    "RRCEnabled1024QAM", false, "DeploymentAllows1024QAM", false, ...
    "FrequencyRange", string(cfg.frequency.range_name), ...
    "OperatingBand", string(cfg.frequency.band_name), ...
    "DeploymentClass", "common_search_space_ra_si", ...
    "FrequencyRangeAllows1024QAM", false, ...
    "BandAllows1024QAM", false);
end
