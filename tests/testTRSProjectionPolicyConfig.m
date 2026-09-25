function ok=testTRSProjectionPolicyConfig()
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig('simulator/configs/validation/trs_4tx2rx_white_noise_candidate.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
p=sixgr.link.prepareTRSTransmission(cfg,cfg.channel.snr_dB, ...
    'RuntimeSlot',double(cfg.phy.trs.slotNumbers(1))+1);
assert(p.StrictConfig.StrictValidation.StrictValid && p.StrictConfig.DetectionPolicy=="white_noise_projection_v1");
for alpha=[NaN -1 0 1 Inf]
    bad=p.StrictConfig; bad.TargetFalseAlarmProbability=alpha;
    result=sixgr.phy.trs.validateTRSConfigStrict(bad);
    assert(~result.StrictValid && any(result.FailureReasons=="projection_detector_requires_explicit_false_alarm_probability"));
end
bad=p.StrictConfig; bad.DetectionPolicy="uninstalled_policy";
result=sixgr.phy.trs.validateTRSConfigStrict(bad);
assert(~result.StrictValid && any(result.FailureReasons=="invalid_detection_policy"));
bad=p.StrictConfig; bad.ChannelModel="TDL-C";
result=sixgr.phy.trs.validateTRSConfigStrict(bad);
assert(~result.StrictValid && any(result.FailureReasons=="projection_detector_candidate_requires_awgn_channel"));
ok=true; disp('TRS_PROJECTION_POLICY_CONFIG_PASS');
end
