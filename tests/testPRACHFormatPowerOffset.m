function ok=testPRACHFormatPowerOffset()
setup6GRSimToolkit('Verbose',false);
formats=["0","1","2","3","A1","A2","A3","B1","B2","B3","B4","C0","C2"];
base=[0 -3 -6 0 8 5 3 8 5 3 0 11 5];
for k=1:4
    assert(sixgr.phy.ia.RAPowerController.deltaPreamble(formats(k),1.25)==base(k));
end
for k=5:numel(formats)
    for mu=0:6
        assert(sixgr.phy.ia.RAPowerController.deltaPreamble(formats(k),15*2^mu)==base(k)+3*mu);
    end
end
try
    sixgr.phy.ia.RAPowerController.deltaPreamble(["A1","B4"],30);
    error('TEST:ExpectedFormatRejection','An array is not an executed preamble format.');
catch e
    assert(string(e.identifier)=="sixgr:phy:ia:UnknownPRACHPowerFormat");
end
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_causal_access_to_data_wiring_tdd.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
[p,k]=sixgr.phy.ra.runFourStepRA(cfg,'WriteArtifacts',false,'StageAction','prepare_next_stage');
assert(k.RAConfig.ResolvedPRACHFormat=="B4" && p.PreambleDelta_dB==3 && ...
    p.PreambleTargetReceivedPower_dBm==p.PreambleReceivedTargetPower_dBm+3);
assert(p.PreambleTxPower_dBm==min(p.Pcmax_dBm,p.PreambleTargetReceivedPower_dBm+p.PowerPathloss_dB));
assert(isfinite(p.PreambleTxAmplitudeScale) && isempty(p.RuntimeStageRows));
cfg.random_access.delta_preamble_db=0;
try
    [~,~]=sixgr.phy.ra.runFourStepRA(cfg,'WriteArtifacts',false,'StageAction','prepare_next_stage');
    error('TEST:ExpectedPowerOffsetRejection','A conflicting legacy zero must not override the standard.');
catch e
    assert(string(e.identifier)=="sixgr:phy:ra:ConflictingPRACHFormatPowerOffset");
end
disp('PRACH_FORMAT_POWER_OFFSET_PASS: standard long/short tables, PRACH numerology and real B4 producer.');
ok=true;
end
