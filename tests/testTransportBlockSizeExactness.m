function ok = testTransportBlockSizeExactness()
%TESTTRANSPORTBLOCKSIZEEXACTNESS Guard faithful DL/UL grants against rough TBS drift.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
if exist("nrTBS", "file") ~= 2
    ok = true;
    return;
end

localAssertDefaultPolicy();
localAssertDirection("DL");
localAssertDirection("UL");
localAssertOverrideCannotSelfCertify("DL");
localAssertOverrideCannotSelfCertify("UL");

ok = true;
end

function localAssertDefaultPolicy()
cfg = sixgr.config.normalizeConfig(sixgr.config.defaultConfig());
assert(strcmpi(char(string(sixgr.util.structGet(cfg, "mac.scheduler.tbsMode", ""))), "faithful"), ...
    "Default scheduler TBS mode must be faithful.");
assert(~logical(sixgr.util.structGet(cfg, "mac.scheduler.fastNREApprox", true)), ...
    "Default scheduler must not enable fast NRE approximation.");
end

function localAssertDirection(direction)
for idx = 1:12
    cfg = localCfg(direction, idx);
    grant = sixgr.link.resolveWaveformGrant(cfg, direction, idx - 1);
    assert(logical(grant.Valid), "%s grant %d must resolve as valid.", direction, idx);
    assert(~logical(sixgr.util.structGet(grant, "ExactTBSUsedFastNREApprox", true)), ...
        "%s grant %d must not use fast NRE approximation.", direction, idx);
    assert(~logical(sixgr.util.structGet(grant, "PlanningOnlyApproximation", true)), ...
        "%s grant %d must not carry planning-only approximate status.", direction, idx);

    exactTBS = localExactNrTBS(grant);
    assert(double(grant.TBSBits) == double(exactTBS), ...
        "%s grant %d TBSBits=%d must equal exact nrTBS=%d.", ...
        direction, idx, double(grant.TBSBits), double(exactTBS));
    assert(double(grant.PHYGrant.CodingLayout.TBSBits) == double(exactTBS), ...
        "%s frozen PHYGrant %d must carry exact CodingLayout.TBSBits.", direction, idx);
end
end

function localAssertOverrideCannotSelfCertify(direction)
cfg = localCfg(direction, 3);
grant = sixgr.link.resolveWaveformGrant(cfg, direction, 0);
badGrant = grant.PHYGrant;
badTBS = double(grant.TBSBits) + 8;
badGrant.CodingLayout.TBSBits = badTBS;
if strcmpi(direction, "DL")
    badGrant.CodingLayout.TBSBitsPerCodeword = badTBS;
    expectedId = "sixgr:phy:dl:PDSCHGrantTBSMismatch";
    runner = @() sixgr.phy.dl.PDSCH_Tx(cfg, ...
        "PHYGrant", badGrant, ...
        "TransportBlockSizeOverride", badTBS, ...
        "CompactOutput", true);
else
    expectedId = "sixgr:phy:ul:PUSCHGrantTBSMismatch";
    runner = @() sixgr.phy.ul.PUSCH_Tx(cfg, ...
        "PHYGrant", badGrant, ...
        "TransportBlockSizeOverride", badTBS, ...
        "CompactOutput", true);
end

threw = false;
try
    runner();
catch ME
    threw = strcmp(string(ME.identifier), expectedId);
end
assert(threw, ...
    "%s TX must reject a frozen-grant TBS mismatch even when TransportBlockSizeOverride echoes the bad grant.", ...
    direction);
end

function cfg = localCfg(direction, idx)
direction = upper(string(direction));
mods = ["QPSK", "16QAM", "64QAM", "256QAM"];
layers = [1 1 2 1 2 1 1 2 1 2 1 1];
prbCounts = [4 6 8 10 12 5 7 9 11 13 14 15];
symStarts = [0 2 2 1 2 0 2 1 2 0 2 1];
symLens = [14 10 9 11 8 12 10 9 11 13 8 10];
rates = [0.25 0.31 0.38 0.45 0.52 0.29 0.34 0.41 0.48 0.55 0.36 0.43];

cfg = sixgr.config.defaultConfig();
cfg.run.useMex = false;
cfg.run.shortRun = true;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.mac.scheduler.fastNREApprox = false;
cfg.mac.scheduler.tbsMode = "faithful";
cfg.channel.model = "AWGN";
cfg.channel.awgnOnly = true;
cfg.phy.carrier.NSizeGrid = 52;
cfg.phy.carrier.SubcarrierSpacing = 30;

prbStart = mod(2 * idx, 20);
prbSet = prbStart:(prbStart + prbCounts(idx) - 1);
symAlloc = [symStarts(idx), symLens(idx)];
modulation = char(mods(1 + mod(idx - 1, numel(mods))));
numLayers = layers(idx);
codeRate = rates(idx);

if direction == "DL"
    cfg.phy.pdsch.prbSet = prbSet;
    cfg.phy.pdsch.symbolAllocation = symAlloc;
    cfg.phy.pdsch.mappingType = "A";
    cfg.phy.pdsch.modulation = modulation;
    cfg.phy.pdsch.numLayers = numLayers;
    cfg.phy.pdsch.nLayers = numLayers;
    cfg.phy.pdsch.numPorts = numLayers;
    cfg.phy.pdsch.nPorts = numLayers;
    cfg.phy.pdsch.codeRate = codeRate;
    cfg.phy.pdsch.xOverhead = 0;
    cfg.phy.pdsch.mcsIndex = 4 + mod(idx, 10);
    cfg.phy.pdsch.enablePTRS = false;
else
    cfg.phy.pusch.prbSet = prbSet;
    cfg.phy.pusch.symbolAllocation = symAlloc;
    cfg.phy.pusch.mappingType = "A";
    cfg.phy.pusch.modulation = modulation;
    cfg.phy.pusch.numLayers = numLayers;
    cfg.phy.pusch.nLayers = numLayers;
    cfg.phy.pusch.numPorts = numLayers;
    cfg.phy.pusch.nPorts = numLayers;
    cfg.phy.pusch.numAntennaPorts = numLayers;
    cfg.phy.pusch.codeRate = codeRate;
    cfg.phy.pusch.xOverhead = 0;
    cfg.phy.pusch.mcsIndex = 4 + mod(idx, 10);
    cfg.phy.pusch.transformPrecoding = false;
    cfg.phy.pusch.transmissionScheme = "nonCodebook";
    cfg.phy.pusch.enablePTRS = false;
end
cfg = sixgr.config.normalizeConfig(cfg);
end

function tbs = localExactNrTBS(grant)
tbs = round(double(nrTBS(char(string(grant.Modulation)), ...
    double(grant.NumLayers), ...
    numel(grant.PRBSet), ...
    double(grant.NREPerPRB), ...
    double(grant.TargetCodeRate), ...
    double(sixgr.util.structGet(grant, "XOverhead", 0)))));
end
