function ok = testMeasuredRSSchedulerCQIProvenanceFDDTDD()
%TESTMEASUREDRSSCHEDULERCQIPROVENANCEFDDTDD Guard measured RS scheduling input.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
scenarioDir = fullfile("simulator", "configs", "scenarios");
paths = [fullfile(scenarioDir, "lls_causal_access_to_data_wiring.yaml"), ...
    fullfile(scenarioDir, "lls_causal_access_to_data_wiring_tdd.yaml")];
expectedDuplex = ["FDD", "TDD"];

for idx = 1:numel(paths)
    scenario = sixgr.lls6g.config.loadScenarioConfig(paths(idx));
    cfg = sixgr.lls6g.buildInternalConfig(scenario, string(tempname));
    assert(upper(string(cfg.phy.duplex.mode)) == expectedDuplex(idx));

    ulInput = struct( ...
        "WidebandSINR_dB", 12, ...
        "SINRSource", "measured_ul_srs_wideband_after_srs_to_pusch_scheduler_margin", ...
        "SINRValueRole", "measured_data_channel_scheduling_input_after_srs_to_pusch_margin", ...
        "SINRValueStatus", "PASS", ...
        "RankIndicator", 1);
    ul = sixgr.link.resolveWidebandCQI(ulInput, cfg, "UL");
    assert(logical(ul.SINRInputAccepted) && isfinite(double(ul.WidebandCQI)), ...
        "Measured UL SRS scheduling evidence must be accepted for %s.", expectedDuplex(idx));

    dlInput = struct( ...
        "WidebandSINR_dB", 12, ...
        "SINRSource", "measured_dl_srs_reciprocity_after_scheduler_margin", ...
        "SINRValueRole", "measured_data_channel_scheduling_input_after_srs_reciprocity_margin", ...
        "SINRValueStatus", "PASS", ...
        "RankIndicator", 1);
    dl = sixgr.link.resolveWidebandCQI(dlInput, cfg, "DL");
    assert(~dl.SINRInputAccepted && isnan(dl.WidebandCQI), ...
        "UL SRS with only a DL reciprocity label must be rejected for %s.", expectedDuplex(idx));
    crossed=sixgr.link.resolveWidebandCQI(ulInput,cfg,"DL");
    assert(~crossed.SINRInputAccepted && isnan(crossed.WidebandCQI));
    dlInput.SINRSource="receiver_post_equalization_sinr";
    dlInput.SINRValueRole="measured_post_equalization_scheduling_input";
    dl=sixgr.link.resolveWidebandCQI(dlInput,cfg,"DL");
    assert(dl.SINRInputAccepted && isfinite(dl.WidebandCQI), ...
        'Direction-appropriate receiver quality must remain available to DL CQI.');

    configuredOnly = ulInput;
    configuredOnly.SINRSource = "configured_operating_point_metadata";
    configuredOnly.SINRValueRole = "configured_operating_point_metadata";
    rejected = sixgr.link.resolveWidebandCQI(configuredOnly, cfg, "UL");
    assert(~logical(rejected.SINRInputAccepted) && ~isfinite(double(rejected.WidebandCQI)), ...
        "Configured SNR metadata must remain rejected for scheduler CQI in %s.", expectedDuplex(idx));
end

runtimeSource = fileread(fullfile("+sixgr", "+truth", "CoupledTruthRuntime.m"));
assert(~contains(runtimeSource, "raw_cqi_fallback_after_scheduler_adjustment_failed"), ...
    "The coupled runtime must not silently fall back to raw reference-signal CQI.");

ok = true;
fprintf("[PASS] testMeasuredRSSchedulerCQIProvenanceFDDTDD measured CQI authority retained.\n");
end
