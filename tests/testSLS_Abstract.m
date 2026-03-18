function ok = testSLS_Abstract()
%TESTSLS_ABSTRACT Regression checks for context-aware SLS PHY/scheduling.

setup6GRSimToolkit("Verbose", false);
cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.run.strictMode = true;
cfg.mac.scheduler.type = "pf";
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;

numTTI = 24;
nUE = 8;
cfg.scenario.nUE = nUE;
cfg.scenario.ue.nUE = nUE;
ctx = sixgr.core.SimContext(cfg);

offeredDL = repmat(6000, numTTI, nUE);
offeredUL = repmat(3500, numTTI, nUE);
snrAxis = [-6 -2 2 6 10];
dirAxis = ["DL","UL"];
mcsAxis = [6 12];
prbAxis = [10 20];
layAxis = [1];
scsAxis = [30];
doppAxis = [0 70];
chAxis = ["AWGN","TDL-C"];
B = zeros(numel(dirAxis), numel(mcsAxis), numel(prbAxis), numel(layAxis), ...
    numel(scsAxis), numel(doppAxis), numel(chAxis), numel(snrAxis));
for iDir = 1:numel(dirAxis)
    for iM = 1:numel(mcsAxis)
        for iP = 1:numel(prbAxis)
            for iD = 1:numel(doppAxis)
                for iC = 1:numel(chAxis)
                    thr = -1 + 0.55*iM + 0.20*iP + 0.12*iD + 0.18*iC + 0.25*(iDir-1);
                    bl = 1 ./ (1 + exp((snrAxis(:) - thr)/1.9));
                    B(iDir,iM,iP,1,1,iD,iC,:) = reshape(min(max(bl,1e-4),0.9999), 1,1,1,1,1,1,1,[]);
                end
            end
        end
    end
end
db = sixgr.system.BLER_DB( ...
    "SNR_dB", snrAxis, ...
    "Direction", dirAxis, ...
    "MCS", mcsAxis, ...
    "PRB", prbAxis, ...
    "Layers", layAxis, ...
    "SCS", scsAxis, ...
    "DopplerHz", doppAxis, ...
    "ChannelModel", chAxis, ...
    "BLER", B, ...
    "Source", "test_db");

res = sixgr.system.SystemLevelRunner.run(ctx, struct( ...
    "NumTTI", numTTI, ...
    "NumUE", nUE, ...
    "BLERDB", db, ...
    "OfferedBitsDL", offeredDL, ...
    "OfferedBitsUL", offeredUL));

assert(res.Ok, "SystemLevelRunner reported failure");
assert(istable(res.KPITable) && height(res.KPITable) >= 1, "System KPI table missing");
assert(isfield(res, "Details") && isstruct(res.Details), "Missing system details");
assert(isfield(res.Details, "GrantCountDL") && isfield(res.Details, "GrantCountUL"), "Missing grant counters");
assert(sum(double(res.Details.GrantCountDL + res.Details.GrantCountUL)) > 0, "No grants were issued.");
assert(any(double(res.Details.ScheduledUE_DL) > 1) || any(double(res.Details.ScheduledUE_UL) > 1), ...
    "Expected at least one slot with multi-UE scheduling.");
assert(isfield(res.Details, "DecodeOK") && isfield(res.Details, "DecodeFail"), "Missing decode counters");
assert(double(res.Details.DecodeOK) + double(res.Details.DecodeFail) > 0, "No decode events were recorded.");

k = res.KPITable(1,:);
assert(isfinite(double(k.Throughput_Mbps)) && double(k.Throughput_Mbps) >= 0, "Invalid throughput KPI.");
assert(isfinite(double(k.PacketLoss)) && double(k.PacketLoss) >= 0 && double(k.PacketLoss) <= 1, "Invalid packet-loss KPI.");
assert(isfinite(double(k.JainFairness)) && double(k.JainFairness) > 0 && double(k.JainFairness) <= 1, "Invalid fairness KPI.");
ok = true;
end
