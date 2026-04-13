function ok = testSLS_WaveformBackend()
%TESTSLS_WAVEFORMBACKEND Small-system smoke test for waveform-backed SLS PHY.

setup6GRSimToolkit("Verbose", false);

cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.run.strictMode = false;
cfg.run.useMex = false;
cfg.system.phyBackend = "waveform";
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.outputs.saveFIG = false;

cfg.scenario.layout.nSites = 1;
cfg.scenario.layout.nSectorsPerSite = 1;
cfg.scenario.layout.wrapAround = false;
cfg.scenario.ue.nUE = 4;
cfg.scenario.nUE = 4;
cfg.scenario.bs.nTxAnt = 1;
cfg.scenario.bs.nRxAnt = 1;
cfg.scenario.ue.nTxAnt = 1;
cfg.scenario.ue.nRxAnt = 1;

cfg.channel.awgnOnly = true;
cfg.channel.model = "AWGN";
cfg.channel.fading.enable = false;

cfg.phy.pdsch.modulation = "QPSK";
cfg.phy.pdsch.codeRate = 0.35;
cfg.phy.pdsch.numLayers = 1;
cfg.phy.pdsch.nLayers = 1;
cfg.phy.pusch.modulation = "QPSK";
cfg.phy.pusch.codeRate = 0.35;
cfg.phy.pusch.numLayers = 1;
cfg.phy.pusch.nLayers = 1;
cfg.mac.scheduler.type = "rr";
cfg = sixgr.config.normalizeConfig(cfg);
sixgr.config.validateConfig(cfg);

phy = sixgr.system.PhyFactory.create(cfg, struct("PHYBackend", "waveform"));
assert(isa(phy, "sixgr.system.WaveformPHY"), "PhyFactory should build the waveform backend when requested.");

ctx = sixgr.core.SimContext(cfg);
numTTI = 8;
nUE = 4;
res = sixgr.system.SystemLevelRunner.run(ctx, struct( ...
    "NumTTI", numTTI, ...
    "OfferedBitsDL", repmat(4000, numTTI, nUE), ...
    "OfferedBitsUL", zeros(numTTI, nUE), ...
    "PHYBackend", "waveform"));

assert(res.Ok, "Waveform-backed system run reported failure.");
assert(istable(res.KPITable) && height(res.KPITable) >= 1, "Missing system KPI table.");
assert(isfield(res, "Details") && isstruct(res.Details), "Missing system details.");
assert(logical(res.Details.WaveformBacked), "System details must record waveform-backed execution.");
assert(logical(res.Details.WaveformPHYActive), "System details must record active waveform PHY execution.");
assert(~logical(res.Details.ProxyPHYActive), "System details must record that proxy PHY is inactive.");
assert(~logical(res.Details.FallbackUsed), "System details must record that no fallback PHY was used.");
assert(sum(double(res.Details.GrantCountDL + res.Details.GrantCountUL)) > 0, ...
    "Waveform-backed system run should issue at least one grant.");
assert(double(res.Details.DecodeOK) + double(res.Details.DecodeFail) > 0, ...
    "Waveform-backed system run should attempt at least one decode.");
assert(istable(res.Details.InterferenceDetail) && height(res.Details.InterferenceDetail) >= nUE, ...
    "Waveform-backed system run must export per-UE interference detail.");

intrf = res.Details.InterferenceDetail;
requiredCols = ["DesiredPowerDL_dBm","InterferencePowerDL_dBm","NoiseDL_dBm", ...
    "DesiredPowerUL_dBm","InterferencePowerUL_dBm","NoiseUL_dBm","ActiveInterfererCountDL"];
for i = 1:numel(requiredCols)
    assert(ismember(requiredCols(i), string(intrf.Properties.VariableNames)), ...
        "Interference detail is missing required column '%s'.", requiredCols(i));
end
assert(all(double(intrf.ActiveInterfererCountDL) == 0), ...
    "Single-cell waveform backend run should not report non-serving DL interferers.");
assert(all(isfinite(double(intrf.DesiredPowerDL_dBm))), ...
    "Desired DL power trace must be finite for the waveform backend run.");
dlRows = isfinite(double(intrf.SINR_DL_dB));
assert(any(dlRows), "Waveform backend run must include at least one DL-active slot.");
assert(all(isfinite(double(intrf.NoiseDL_dBm(dlRows)))), ...
    "Noise DL trace must be finite on DL-active waveform-backend slots.");

k = res.KPITable(1,:);
assert(ismember("ExecutionBackend", string(k.Properties.VariableNames)), "KPI table must expose ExecutionBackend.");
assert(ismember("PHYMode", string(k.Properties.VariableNames)), "KPI table must expose PHYMode.");
assert(ismember("WaveformBacked", string(k.Properties.VariableNames)), "KPI table must expose WaveformBacked.");
assert(ismember("WaveformPHYActive", string(k.Properties.VariableNames)), "KPI table must expose WaveformPHYActive.");
assert(ismember("ProxyPHYActive", string(k.Properties.VariableNames)), "KPI table must expose ProxyPHYActive.");
assert(ismember("FallbackUsed", string(k.Properties.VariableNames)), "KPI table must expose FallbackUsed.");
assert(strcmpi(char(string(k.ExecutionBackend)), "WAVEFORM_SYSTEM_PHY"), ...
    "KPI table should report the waveform system backend.");
assert(contains(upper(char(string(k.PHYMode))), "WAVEFORM_REPLAY"), ...
    "KPI table should report waveform replay mode.");
assert(logical(k.WaveformBacked), "KPI table must mark the waveform backend as waveform-backed.");
assert(logical(k.WaveformPHYActive), "KPI table must mark waveform PHY active.");
assert(~logical(k.ProxyPHYActive), "KPI table must mark proxy PHY inactive.");
assert(~logical(k.FallbackUsed), "KPI table must mark fallback inactive.");
ok = true;
end
