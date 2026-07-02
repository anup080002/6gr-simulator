function [tx, sched] = generateMsg4Waveform(cfg, raCfg, msg4)
%GENERATEMSG4WAVEFORM Carry contention resolution on temp C-RNTI PDSCH.
cfgTx = sixgr.phy.ra.localizeCarrierConfig(cfg, raCfg);
[carrier, ~] = sixgr.phy.grid.makeCarrier(cfgTx);
sched = localMsg4Schedule(raCfg);
cfgTx = sixgr.phy.ra.localizeRAPDSCHConfig(cfgTx, sched.PDSCH);
cfgTx.phy.pdcch.rnti = double(raCfg.TempCRNTI);
cfgTx.phy.pdcch.KBits = double(raCfg.DCIPayloadBits);
cfgTx.phy.pdcch.dciPayloadBits = double(raCfg.DCIPayloadBits);
cfgTx.phy.pdcch.blindSearch = true;
cfgTx.phy.pdcch.allowBlindCandidateTimingEstimate = false;
cfgTx.phy.pdcch.aggregationLevel = 4;
cfgTx.phy.pdcch.searchSpace.numCandidates = [0 0 1 0 0];
cfgTx = sixgr.phy.ra.localizeRAPDCCHConfig(cfgTx, carrier);

[pdcchTx, pdcchInfo] = sixgr.phy.dl.PDCCH_Tx(cfgTx, "Carrier", carrier, ...
    "DCIBits", sched.DCIBits, "K", double(raCfg.DCIPayloadBits), ...
    "RNTI", double(raCfg.TempCRNTI), "NCellID", double(raCfg.NCellID), ...
    "OFDMModulate", false);
sched.PDCCH = pdcchTx.PDCCH;
probe = sixgr.phy.dl.PDSCH_Tx(cfgTx, "Carrier", carrier, "PDSCH", sched.PDSCH, ...
    "TargetCodeRate", double(sched.TargetCodeRate), "RV", double(sched.RV), ...
    "CompactOutput", true);
tbBits = localPadBits(msg4.PayloadBits, probe.TransportBlockSize);
[pdschTx, pdschInfo] = sixgr.phy.dl.PDSCH_Tx(cfgTx, "Carrier", carrier, "PDSCH", sched.PDSCH, ...
    "TransportBlockBits", tbBits, ...
    "TargetCodeRate", double(sched.TargetCodeRate), "RV", double(sched.RV));
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
tx.RAPDSCHConfig = localPDSCHEvidence(cfgTx, sched.PDSCH, pdschInfo);
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
try
    pdsch.DMRS.DMRSAdditionalPosition = 2;
catch
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

function ev = localPDSCHEvidence(cfgTx, pdsch, info)
prec = sixgr.util.structGet(info, "Precoding", struct());
ev = struct();
ev.NumLayers = double(pdsch.NumLayers);
ev.ConfiguredNumPorts = double(sixgr.util.structGet(cfgTx, "phy.pdsch.numPorts", NaN));
ev.ConfiguredNPorts = double(sixgr.util.structGet(cfgTx, "phy.pdsch.nPorts", NaN));
ev.ExplicitMatrixPresent = ~isempty(sixgr.util.structGet(cfgTx, "phy.pdsch.precoding.matrix", []));
ev.ResolvedNumPorts = double(sixgr.util.structGet(prec, "NumPorts", NaN));
ev.ResolvedNumLayers = double(sixgr.util.structGet(prec, "NumLayers", NaN));
ev.PrecodingActive = logical(sixgr.util.structGet(prec, "Active", false));
ev.PrecodingMode = string(sixgr.util.structGet(prec, "Mode", ""));
ev.PrecodingSource = string(sixgr.util.structGet(prec, "Source", ""));
end
