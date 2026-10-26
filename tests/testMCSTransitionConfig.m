function ok=testMCSTransitionConfig()
% Authored policy/configuration checks; no physical adaptation claim.
setup6GRSimToolkit('Verbose',false);
base=sixgr.config.defaultConfig();
assert(~base.phy.linkAdaptation.mcsTransition.enabled);
declared=struct('enabled',true,'max_up_step',1,'max_down_step',2,'increase_ack_count',2);
p=sixgr.lls6g.config.resolveMCSTransitionPolicy(declared);
assert(p.enabled && p.maxUpStep==1 && p.maxDownStep==2 && p.increaseAckCount==2);
for name=["max_up_step","max_down_step","increase_ack_count"]
    for value={0,-1,1.5,NaN,Inf,[],[1 2],true,1+1i,'2'}
        bad=declared; bad.(name)=value{1}; reject(@()sixgr.lls6g.config.resolveMCSTransitionPolicy(bad));
    end
end
for value={1,0,'true',[],[true false]}
    bad=declared; bad.enabled=value{1}; reject(@()sixgr.lls6g.config.resolveMCSTransitionPolicy(bad));
end
bad=declared; bad.max_up_step=32; reject(@()sixgr.lls6g.config.resolveMCSTransitionPolicy(bad));
bad=declared; bad.max_down_step=32; reject(@()sixgr.lls6g.config.resolveMCSTransitionPolicy(bad));
bad=declared; bad.unknown=1; reject(@()sixgr.lls6g.config.resolveMCSTransitionPolicy(bad));
reject(@()sixgr.lls6g.config.resolveMCSTransitionPolicy([]));
bad=struct('link_adaptation',struct('mcs_transition',declared,'operating_point_mode','fixed'));
reject(@()sixgr.lls6g.config.validateScenarioConfig(bad,'AllowPartial',true));
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_integration_gate.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
assert(isequal(cfg.phy.linkAdaptation.mcsTransition,p) && ...
    cfg.phy.linkAdaptation.rankIncreaseConfirmationReports==2);
assert(cfg.run.totalSlots==60,'Adaptation policy must not silently change the requested horizon.');
fprintf('MCS_TRANSITION_CONFIG_PASS YAML_to_runtime=1 strict_invalid_values=1 n40_rank_confirmation=2\n');
ok=true;
end

function reject(f)
try
    f();
catch cause
    assert(string(cause.identifier)=="sixgr:lls6g:config:InvalidMCSTransitionPolicy", ...
        'Unexpected rejection %s: %s',cause.identifier,cause.message);
    return;
end
error('testMCSTransitionConfig:ExpectedRejection','Malformed MCS transition policy was accepted.');
end
