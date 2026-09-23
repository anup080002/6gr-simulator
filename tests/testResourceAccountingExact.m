function ok = testResourceAccountingExact()
%TESTRESOURCEACCOUNTINGEXACT Exact RE/G/TBS accounting for PDSCH and PUSCH.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
if ~localHaveRequired5G()
    error("sixgr:test:Required5GToolboxUnavailable", ...
        ["testResourceAccountingExact requires the 5G Toolbox APIs " ...
        "checked by localHaveRequired5G; unavailable tests cannot pass."]);
end

savedRNG = rng;
rngCleanup = onCleanup(@() rng(savedRNG)); %#ok<NASGU>
rng(4202, "twister");
carrier = nrCarrierConfig;
carrier.NSizeGrid = 52;
carrier.SubcarrierSpacing = 30;
targetRates = [120 193 449 616 772] / 1024;

pdschTBSDelta = zeros(200, 1);
puschTBSDelta = zeros(200, 1);
pdschPTRSSeen = false;
puschPTRSSeen = false;
reservedSeen = false;
codebookPortSeen = false;
modulations = ["QPSK", "16QAM", "64QAM", "256QAM"];
dlCoverage = zeros(4,4);
ulCoverage = zeros(4,4);

for k = 1:200
    pdsch = localPDSCHConfig(k);
    dlCoverage(pdsch.NumLayers,modulations==string(pdsch.Modulation)) = ...
        dlCoverage(pdsch.NumLayers,modulations==string(pdsch.Modulation)) + 1;
    [pdschInd, pdschInfo] = sixgr.phy.grid.allocREsPDSCH(carrier, pdsch);
    acct = pdschInfo.ResourceAccounting;
    % The reference must not consume the DUT's ResourceAccounting or echoed
    % IndicesInfo. Independently resolve the requested allocation in MATLAB.
    [referenceIndices, referenceInfo] = nrPDSCHIndices(carrier, pdsch);
    assert(isequal(double(pdschInd),double(referenceIndices)), ...
        'PDSCH mapped RE indices differ from direct nrPDSCHIndices.');
    localAssertAccounting(acct, referenceInfo);
    rate = targetRates(mod(k - 1, numel(targetRates)) + 1);
    refTBS = double(nrTBS(pdsch.Modulation, pdsch.NumLayers, numel(pdsch.PRBSet), referenceInfo.NREPerPRB, rate, 0));
    dutTBS = double(nrTBS(pdsch.Modulation, pdsch.NumLayers, numel(pdsch.PRBSet), pdschInfo.NREPerPRB, rate, 0));
    pdschTBSDelta(k) = dutTBS - refTBS;

    cw = int8(randi([0 1], round(acct.CodedBitCountG), 1));
    sym = nrPDSCH(carrier, pdsch, {cw});
    llr = nrPDSCHDecode(carrier, pdsch, sym, 1e-3);
    assert(numel(cw) == round(acct.CodedBitCountG), "PDSCH TX codeword length must equal G.");
    assert(localLLRLength(llr) == round(acct.CodedBitCountG), "PDSCH demapper LLR length must equal G.");
    pdschPTRSSeen = pdschPTRSSeen || acct.PTRSRE > 0;
    reservedSeen = reservedSeen || acct.ReservedRE > 0;

    pusch = localPUSCHConfig(k);
    ulCoverage(pusch.NumLayers,modulations==string(pusch.Modulation)) = ...
        ulCoverage(pusch.NumLayers,modulations==string(pusch.Modulation)) + 1;
    [puschInd, puschInfo] = sixgr.phy.grid.allocREsPUSCH(carrier, pusch);
    acct = puschInfo.ResourceAccounting;
    [referenceIndices, referenceInfo] = nrPUSCHIndices(carrier, pusch);
    assert(isequal(double(puschInd),double(referenceIndices)), ...
        'PUSCH mapped RE indices differ from direct nrPUSCHIndices.');
    localAssertAccounting(acct, referenceInfo);
    rate = targetRates(mod(k, numel(targetRates)) + 1);
    refTBS = double(nrTBS(pusch.Modulation, pusch.NumLayers, numel(pusch.PRBSet), referenceInfo.NREPerPRB, rate, 0));
    dutTBS = double(nrTBS(pusch.Modulation, pusch.NumLayers, numel(pusch.PRBSet), puschInfo.NREPerPRB, rate, 0));
    puschTBSDelta(k) = dutTBS - refTBS;

    cw = int8(randi([0 1], round(acct.CodedBitCountG), 1));
    sym = nrPUSCH(carrier, pusch, cw);
    llr = nrPUSCHDecode(carrier, pusch, sym, 1e-3);
    assert(numel(cw) == round(acct.CodedBitCountG), "PUSCH TX codeword length must equal G.");
    assert(localLLRLength(llr) == round(acct.CodedBitCountG), "PUSCH demapper LLR length must equal G.");
    puschPTRSSeen = puschPTRSSeen || acct.PTRSRE > 0;
    codebookPortSeen = codebookPortSeen || acct.PortMappedRE > acct.ModulationSymbolCount;
end

localAssertAuditedULPortMapping();
localAssertRepresentativeFullTX(carrier);

assert(all(pdschTBSDelta == 0), "Every PDSCH TBS input vector must match nrTBS exactly.");
assert(all(puschTBSDelta == 0), "Every PUSCH TBS input vector must match nrTBS exactly.");
assert(pdschPTRSSeen && puschPTRSSeen, "PDSCH and PUSCH allocation sweep must include PTRS resources.");
assert(reservedSeen, "PDSCH allocation sweep must include reserved RE resources.");
assert(codebookPortSeen, "PUSCH allocation sweep must include a port-mapped codebook case.");
assert(all(dlCoverage(:)>0) && all(ulCoverage(:)>0), ...
    'Independent resource checks must cover every rank 1:4/modulation pairing in both directions.');

fprintf("ResourceAccountingExact: PDSCH=%d PUSCH=%d maxTBSDelta=%g auditedULG=%d\n", ...
    numel(pdschTBSDelta), numel(puschTBSDelta), ...
    max(abs([pdschTBSDelta(:); puschTBSDelta(:)])), 83532);
fprintf('ResourceAccountingExact: independent rank/modulation pairs DL=%d UL=%d\n', ...
    nnz(dlCoverage),nnz(ulCoverage));
ok = true;
end

function pdsch = localPDSCHConfig(k)
mods = ["QPSK", "16QAM", "64QAM", "256QAM"];
layers = mod(k - 1, 4) + 1;
nPRB = 6 + mod(7 * k, 31);
startPRB = mod(3 * k, 52 - nPRB);
pdsch = nrPDSCHConfig;
pdsch.PRBSet = startPRB:(startPRB + nPRB - 1);
pdsch.Modulation = char(mods(mod(floor((k - 1)/4), numel(mods)) + 1));
pdsch.NumLayers = layers;
pdsch.RNTI = 100 + k;
pdsch.NID = mod(k, 1008);
if mod(k, 2) == 0
    pdsch.MappingType = 'B';
    pdsch.SymbolAllocation = [2 + mod(k, 3), 8 + mod(k, 3)];
else
    pdsch.MappingType = 'A';
    pdsch.SymbolAllocation = [0 14];
end
pdsch.DMRS.DMRSPortSet = 0:(layers - 1);
pdsch.DMRS.DMRSAdditionalPosition = mod(k, 4);
if mod(k, 11) == 0
    res = nrPDSCHReservedConfig;
    res.PRBSet = pdsch.PRBSet(1:min(2, numel(pdsch.PRBSet)));
    res.SymbolSet = 6;
    pdsch.ReservedPRB = {res};
end
if mod(k, 5) == 0
    pdsch.EnablePTRS = true;
    pdsch.PTRS.TimeDensity = 2;
    pdsch.PTRS.FrequencyDensity = 2;
    pdsch.PTRS.REOffset = '00';
    pdsch.PTRS.PTRSPortSet = 0;
end
end

function pusch = localPUSCHConfig(k)
mods = ["QPSK", "16QAM", "64QAM", "256QAM"];
layers = mod(k - 1, 4) + 1;
nPRB = 6 + mod(5 * k, 33);
startPRB = mod(2 * k, 52 - nPRB);
pusch = nrPUSCHConfig;
pusch.PRBSet = startPRB:(startPRB + nPRB - 1);
pusch.Modulation = char(mods(mod(floor((k - 1)/4) + 1, numel(mods)) + 1));
pusch.NumLayers = layers;
pusch.RNTI = 200 + k;
pusch.NID = mod(k + 11, 1008);
pusch.TransformPrecoding = false;
if mod(k, 2) == 0
    pusch.MappingType = 'B';
    pusch.SymbolAllocation = [2 + mod(k, 3), 8 + mod(k, 3)];
else
    pusch.MappingType = 'A';
    pusch.SymbolAllocation = [0 14];
end
pusch.DMRS.DMRSAdditionalPosition = mod(k, 4);
if layers == 1 && mod(k, 7) == 0
    pusch.TransmissionScheme = 'codebook';
    pusch.NumAntennaPorts = 2;
    pusch.TPMI = 0;
end
if mod(k, 5) == 0
    pusch.EnablePTRS = true;
    pusch.PTRS.TimeDensity = 2;
    pusch.PTRS.FrequencyDensity = 2;
    pusch.PTRS.REOffset = '00';
    pusch.PTRS.PTRSPortSet = 0;
end
end

function localAssertAccounting(acct, idxInfo)
assert(logical(acct.DisjointMasks), "%s masks must be disjoint with no duplicate mapped indices.", acct.Channel);
assert(double(acct.DuplicateDataIndices) == 0, "%s data indices must not contain duplicate mapped cells.", acct.Channel);
assert(double(acct.OverlapCount) == 0, "%s data/reference/reserved masks must not overlap.", acct.Channel);
assert(abs(double(acct.LayerDataRE) - double(idxInfo.Gd)) <= 1e-9, ...
    "%s LayerDataRE must equal nr%sIndices Gd.", acct.Channel, acct.Channel);
assert(abs(double(acct.CodedBitCountG) - double(idxInfo.G)) <= 1e-9, ...
    "%s CodedBitCountG must equal nr%sIndices G.", acct.Channel, acct.Channel);
assert(abs(double(acct.CodedBitCountG) - double(acct.LayerDataRE) * double(acct.Qm) * double(acct.NumLayers)) <= 1e-9, ...
    "%s G must equal LayerDataRE*Qm*NumLayers.", acct.Channel);
assert(abs(double(acct.NREPerPRBForTBS) - double(idxInfo.NREPerPRB)) <= 1e-9, ...
    "%s NREPerPRBForTBS must equal toolbox NREPerPRB.", acct.Channel);
end

function localAssertAuditedULPortMapping()
carrier = nrCarrierConfig;
carrier.NSizeGrid = 273;
pusch = struct( ...
    "Modulation", "QPSK", ...
    "NumLayers", 1, ...
    "PRBSet", 0:267, ...
    "SymbolAllocation", [0 14]);
idxInfo = struct("Gd", 41766, "G", 83532, "NREPerPRB", 156);
info = struct("Channel", "PUSCH", "PUSCHIndicesInfo", idxInfo);
idx = reshape(1:83532, 41766, 2);
acct = sixgr.phy.resource.computeResourceAccounting("PUSCH", carrier, pusch, ...
    "ChannelIndices", idx, ...
    "AllocationInfo", info, ...
    "IndexBase", "1based");
assert(double(acct.LayerDataRE) == 41766, "Audited UL layer-domain data RE must be 41766.");
assert(double(acct.PortMappedRE) == 83532, "Audited UL port-mapped cells must be 83532.");
assert(double(acct.CodedBitCountG) == 83532, "Audited UL QPSK one-layer G must be 83532.");
end

function localAssertRepresentativeFullTX(carrier)
cfg = sixgr.config.defaultConfig();
cfg = sixgr.util.structSet(cfg, "run.pdschExecutionProfile", "phy_calibration");
cfg = sixgr.util.structSet(cfg, "phy.carrier.NSizeGrid", carrier.NSizeGrid);
cfg = sixgr.util.structSet(cfg, "phy.carrier.SubcarrierSpacing", carrier.SubcarrierSpacing);
cfg = sixgr.util.structSet(cfg, "phy.pdsch.prbSet", 0:23);
cfg = sixgr.util.structSet(cfg, "phy.pdsch.symbolAllocation", [0 14]);
cfg = sixgr.util.structSet(cfg, "phy.pdsch.mappingType", "A");
cfg = sixgr.util.structSet(cfg, "phy.pdsch.modulation", "64QAM");
cfg = sixgr.util.structSet(cfg, "phy.pdsch.numLayers", 2);
cfg = sixgr.util.structSet(cfg, "phy.pdsch.enablePTRS", true);
cfg = sixgr.util.structSet(cfg, "phy.pdsch.ptrs.timeDensity", 2);
cfg = sixgr.util.structSet(cfg, "phy.pdsch.ptrs.frequencyDensity", 2);
cfg = sixgr.util.structSet(cfg, "phy.pdsch.ptrs.reOffset", "00");
cfg = sixgr.util.structSet(cfg, "phy.pdsch.ptrs.portSet", 0);
cfg = sixgr.util.structSet(cfg, "phy.pdsch.codeRate", 449/1024);
cfg = sixgr.util.structSet(cfg, "phy.pdsch.executionProfile", "phy_calibration");
cfg = sixgr.util.structSet(cfg, "phy.pdsch.mcsTable", "calibration_explicit");
cfg = sixgr.util.structSet(cfg, "phy.pdsch.mcsIndex", 0);
cfg = sixgr.util.structSet(cfg, "phy.pdsch.mcsContext", localCalibrationMCSContext());
cfg = sixgr.util.structSet(cfg, "phy.csirs.enable", false);
[txDL, ~] = sixgr.phy.dl.PDSCH_Tx(cfg, "CompactOutput", false);
[~, independentDL] = nrPDSCHIndices(carrier,txDL.PDSCH);
localAssertFullTXAccounting(txDL.ResourceAccounting,independentDL,'PDSCH');
assert(numel(txDL.Codeword) == double(txDL.ResourceAccounting.CodedBitCountG), ...
    "PDSCH_Tx codeword length must equal ResourceAccounting G.");
assert(double(txDL.ScheduledTransportBlockSize) == double(nrTBS(txDL.PDSCH.Modulation, txDL.PDSCH.NumLayers, ...
    numel(txDL.PDSCH.PRBSet), independentDL.NREPerPRB, txDL.TargetCodeRate, txDL.XOverhead)), ...
    "PDSCH_Tx scheduled TBS must match independently resolved nrPDSCHIndices/nrTBS.");

cfg = sixgr.util.structSet(cfg, "phy.pusch.prbSet", 0:23);
cfg = sixgr.util.structSet(cfg, "phy.pusch.symbolAllocation", [0 14]);
cfg = sixgr.util.structSet(cfg, "phy.pusch.modulation", "64QAM");
cfg = sixgr.util.structSet(cfg, "phy.pusch.numLayers", 1);
cfg = sixgr.util.structSet(cfg, "phy.pusch.transmissionScheme", "codebook");
cfg = sixgr.util.structSet(cfg, "phy.pusch.numAntennaPorts", 2);
cfg = sixgr.util.structSet(cfg, "phy.pusch.TPMI", 0);
cfg = sixgr.util.structSet(cfg, "phy.pusch.enablePTRS", false);
cfg = sixgr.util.structSet(cfg, "phy.pusch.codeRate", 449/1024);
[txUL, ~] = sixgr.phy.ul.PUSCH_Tx(cfg, "CompactOutput", false);
[~, independentUL] = nrPUSCHIndices(carrier,txUL.PUSCH);
localAssertFullTXAccounting(txUL.ResourceAccounting,independentUL,'PUSCH');
assert(numel(txUL.Codeword) == double(txUL.ResourceAccounting.CodedBitCountG), ...
    "PUSCH_Tx codeword length must equal ResourceAccounting G.");
assert(double(txUL.ResourceAccounting.LayerDataRE) < double(txUL.ResourceAccounting.PortMappedRE), ...
    "Representative PUSCH codebook case must expose port-mapped RE separately from layer data RE.");
assert(double(txUL.ScheduledTransportBlockSize) == double(nrTBS(txUL.PUSCH.Modulation, txUL.PUSCH.NumLayers, ...
    numel(txUL.PUSCH.PRBSet), independentUL.NREPerPRB, txUL.TargetCodeRate, txUL.XOverhead)), ...
    "PUSCH_Tx scheduled TBS must match independently resolved nrPUSCHIndices/nrTBS.");
end

function localAssertFullTXAccounting(accounting,reference,channel)
% The canonical transmitter plan has a distinct schema from allocation
% helpers. Compare its physical quantities, not optional diagnostic labels.
assert(accounting.DisjointMasks && ...
    double(accounting.LayerDataRE)==double(reference.Gd) && ...
    double(accounting.CodedBitCountG)==sum(double(reference.G)) && ...
    double(accounting.NREPerPRBForTBS)==double(reference.NREPerPRB), ...
    '%s full transmitter resource accounting differs from independent MATLAB indices.',channel);
end

function context = localCalibrationMCSContext()
context = struct( ...
    "UECapability1024QAM", false, ...
    "RRCEnabled1024QAM", false, ...
    "DCIEnabled1024QAM", false, ...
    "DeploymentAllows1024QAM", false, ...
    "FrequencyRangeAllows1024QAM", false, ...
    "BandAllows1024QAM", false, ...
    "FrequencyRange", "FR1", ...
    "OperatingBand", "n78", ...
    "DeploymentClass", "controlled_test");
end

function n = localLLRLength(llr)
if iscell(llr)
    n = numel(llr{1});
else
    n = numel(llr);
end
end

function tf = localHaveRequired5G()
tf = exist("nrCarrierConfig", "file") == 2 && ...
    exist("nrPDSCHConfig", "file") == 2 && ...
    exist("nrPUSCHConfig", "file") == 2 && ...
    exist("nrPDSCHIndices", "file") == 2 && ...
    exist("nrPUSCHIndices", "file") == 2 && ...
    exist("nrTBS", "file") == 2;
end
