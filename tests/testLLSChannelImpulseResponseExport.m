function ok = testLLSChannelImpulseResponseExport()
%TESTLLSCHANNELIMPULSERESPONSEEXPORT Verify real fading tap export.

setup6GRSimToolkit("Verbose", false);

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", ...
    "lls_3gpp_rel20_anchor_30ghz_400mhz_waveform_honest_2site_6sector_150ue_50slot.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tmp, "run"));

T = sixgr.truth.buildChannelImpulseResponseTable(cfg);
assert(istable(T) && ~isempty(T), ...
    "CDL/TDL channel configurations must export explicit tap delay/power rows.");
assert(all(ismember(["Direction","ResponseType","TapDelay_s","TapPower_dB", ...
    "NormalizedTapPower","ChannelModel","DelayProfile","Source"], string(T.Properties.VariableNames))), ...
    "Channel impulse export must expose the contract fields consumed by the web materializer.");
assert(all(isfinite(double(T.TapDelay_s))) && all(isfinite(double(T.TapPower_dB))), ...
    "Channel impulse taps must contain finite delays and powers from the channel object.");
assert(all(strcmpi(string(T.Status), "available")), ...
    "Rows with actual tap metadata must be marked available.");
assert(all(contains(string(T.Source), "ChannelFactory.info")), ...
    "Channel impulse rows must disclose the ChannelFactory/info provenance.");
dirs = unique(string(T.Direction), "stable");
assert(all(ismember(["DL","UL"], dirs)), ...
    "The export must include both DL and UL configured channel profiles.");
for i = 1:numel(dirs)
    mask = string(T.Direction) == dirs(i);
    p = double(T.NormalizedTapPower(mask));
    p = p(isfinite(p));
    assert(~isempty(p) && abs(sum(p) - 1) < 1e-9, ...
        "Normalized tap powers must sum to one per direction.");
end

runFolder = fullfile(tmp, "live");
liveArtifacts = sixgr.truth.exportLLSLiveDerivedTables(cfg, runFolder, struct(), struct(), struct(), struct());
assert(isfield(liveArtifacts, "ChannelImpulseResponsePath") && ...
    exist(liveArtifacts.ChannelImpulseResponsePath, "file") == 2, ...
    "Live derived exports must publish channel_impulse_response.csv for running web views.");
liveT = readtable(liveArtifacts.ChannelImpulseResponsePath, "TextType", "string");
assert(~isempty(liveT) && all(ismember(["TapDelay_s","TapPower_dB"], string(liveT.Properties.VariableNames))), ...
    "Live channel impulse CSV must carry explicit tap delay/power rows.");

cfgAwgn = cfg;
cfgAwgn.channel.model = "AWGN";
cfgAwgn.channel.awgnOnly = true;
emptyT = sixgr.truth.buildChannelImpulseResponseTable(cfgAwgn);
assert(istable(emptyT) && isempty(emptyT), ...
    "AWGN paths must not receive synthetic channel impulse rows.");

ok = true;
end
