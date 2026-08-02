function cfg = selectWaveformBundleTrialConfig(scenarioCfg, perUserCfg, coupledTruth)
%SELECTWAVEFORMBUNDLETRIALCONFIG Select configuration authority for trials.
% Coupled slot execution schedules all users from the shared scenario and
% therefore must retain the complete cell-side RF architecture. A prepared
% per-user configuration is authoritative only for an uncoupled trial.

if ~(isstruct(scenarioCfg) && isscalar(scenarioCfg))
    error("sixgr:truth:InvalidScenarioTrialConfig", ...
        "The shared scenario trial configuration must be a scalar struct.");
end
if ~(isstruct(perUserCfg) && isscalar(perUserCfg))
    error("sixgr:truth:InvalidPerUserTrialConfig", ...
        "The prepared per-user trial configuration must be a scalar struct.");
end
if ~(islogical(coupledTruth) && isscalar(coupledTruth))
    error("sixgr:truth:InvalidCoupledTruthSelector", ...
        "coupledTruth must be a scalar logical value.");
end

if coupledTruth
    cfg = scenarioCfg;
else
    cfg = perUserCfg;
end
sixgr.config.assertRuntimeFeatureAuthority(cfg);
end
