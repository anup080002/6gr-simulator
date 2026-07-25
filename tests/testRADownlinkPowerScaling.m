function ok = testRADownlinkPowerScaling()
%TESTRADOWNLINKPOWERSCALING Msg2/Msg4 RA DL control uses gNB amplitude units.
tmp = tempname;
mkdir(tmp);
c = onCleanup(@() localCleanupTempFolder(tmp)); %#ok<NASGU>

scenarioPath = fullfile("simulator", "configs", "scenarios", "master_geometry_based.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tmp, "run"));

res = sixgr.phy.ra.runFourStepRA(cfg, ...
    "RunFolder", fullfile(tmp, "ra"), ...
    "RunId", "ra_dl_power_scaling_probe", ...
    "WriteArtifacts", true);
assert(logical(res.StrictOk), "Four-step RA must complete in the downlink power scaling probe.");
assert(isfinite(double(res.DownlinkTxPower_dBm)) && double(res.DownlinkTxPower_dBm) > 0, ...
    "RA downlink gNB transmit power must resolve from scenario config.");
assert(isfinite(double(res.Msg2TxAmplitudeScale)) && double(res.Msg2TxAmplitudeScale) > 1, ...
    "Msg2 RAR waveform must be amplitude-scaled before propagation.");
assert(isfinite(double(res.Msg4TxAmplitudeScale)) && double(res.Msg4TxAmplitudeScale) > 1, ...
    "Msg4 contention-resolution waveform must be amplitude-scaled before propagation.");

csvDir = fullfile(tmp, "ra", "control", "csv");
attempts = readtable(fullfile(csvDir, "ra_attempts.csv"), "TextType", "string");
msg2 = readtable(fullfile(csvDir, "msg2_rar_trials.csv"), "TextType", "string");
msg4 = readtable(fullfile(csvDir, "msg4_contention_resolution.csv"), "TextType", "string");
assert(isfinite(double(attempts.DownlinkTxPower_dBm(1))) && ...
    isfinite(double(attempts.Msg2TxAmplitudeScale(1))) && ...
    isfinite(double(attempts.Msg4TxAmplitudeScale(1))), ...
    "RA attempt artifact must publish Msg2/Msg4 downlink power scaling.");
assert(isfinite(double(msg2.Msg2TxPower_dBm(1))) && ...
    isfinite(double(msg2.Msg2TxAmplitudeScale(1))) && double(msg2.Msg2TxAmplitudeScale(1)) > 1, ...
    "Msg2 artifact must publish gNB downlink power scaling.");
assert(isfinite(double(msg4.Msg4TxPower_dBm(1))) && ...
    isfinite(double(msg4.Msg4TxAmplitudeScale(1))) && double(msg4.Msg4TxAmplitudeScale(1)) > 1, ...
    "Msg4 artifact must publish gNB downlink power scaling.");

ok = true;
end

function localCleanupTempFolder(pathIn)
if exist(pathIn, "dir") == 7
    try
        rmdir(pathIn, "s");
    catch
    end
end
end
