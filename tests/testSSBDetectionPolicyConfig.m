function ok=testSSBDetectionPolicyConfig()
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
scfg=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_tdd_5mhz_rank2_shared_awgn_20db_saturated.yaml'));
s=scfg.toStruct();
s.synchronization.ssb_detector_target_false_alarm_probability=.002;
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
assert(cfg.phy.synchronization.ssbDetectorTargetFalseAlarmProbability==.002);
assert(cfg.phy.synchronization.pssDetectionThreshold==s.synchronization.pss_detection_threshold);
assert(cfg.phy.synchronization.sssHypothesisTestThreshold==s.synchronization.sss_hypothesis_test_threshold);
for alpha=[0 1]
    bad=s; bad.synchronization.ssb_detector_target_false_alarm_probability=alpha;
    expected="sixgr:lls6g:config:ValueTooSmall";
    if alpha==1, expected="sixgr:lls6g:config:ValueTooLarge"; end
    reject(@()sixgr.lls6g.config.validateScenarioConfig(bad,'Kind','scenario', ...
        'AllowPartial',false,'Context','SSB detector policy regression'),expected);
    badCfg=cfg; badCfg.phy.synchronization.ssbDetectorTargetFalseAlarmProbability=alpha;
    reject(@()sixgr.config.validateConfig(badCfg),"sixgr:config:BadRange");
end
fprintf('SSB_DETECTION_POLICY_CONFIG_PASS YAML_binding=1 boundary_rejections=4\n');
ok=true;
end

function reject(action,expected)
try
    action();
catch cause
    assert(string(cause.identifier)==expected,'Expected %s, got %s: %s', ...
        expected,cause.identifier,cause.message);
    assert(contains(cause.message,'ssb_detector_target_false_alarm_probability') || ...
        contains(cause.message,'ssbDetectorTargetFalseAlarmProbability'));
    return;
end
error('test:MissingSSBPolicyRejection','Invalid SSB false-alarm policy was accepted.');
end
