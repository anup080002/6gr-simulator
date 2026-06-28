function ok = testFourStepRARequireRuntimeWaveformsFailClosed()
%TESTFOURSTEPRAREREQUIRERUNTIMEWAVEFORMSFAILCLOSED Missing runtime waveforms fail closed.
cfg = raStrictAnchorConfig();
threw = false;
try
    sixgr.phy.ra.runFourStepRA(cfg, ...
        "RunId", "test_ra_missing_runtime_waveforms", ...
        "RuntimeIntegrationMode", "coupled_truth_runtime", ...
        "RequireRuntimeStageWaveforms", true, ...
        "WriteArtifacts", false);
catch ME
    threw = strcmp(string(ME.identifier), "sixgr:phy:ra:MissingRuntimeStageWaveform");
end
assert(threw, "Strict runtime RA must fail when required propagated stage waveforms are absent.");
ok = true;
end
