function ok=testPathlossReferenceLifetimePolicy()
% Configuration/dispatch only, not PHY or standards-performance qualification.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml');
s=s.toStruct();
assert(string(s.rf_frontend.ul_power_control.pathloss_reference_lifetime)=="retained_filtered_reference");
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
assert(sixgr.phy.refsig.pathlossReferenceLifetime(cfg)=="retained_filtered_reference");
legacy=s; legacy.rf_frontend.ul_power_control.pathloss_reference_lifetime='configured_age_limit';
cfgLegacy=sixgr.lls6g.buildInternalConfig(legacy,tempname);
assert(sixgr.phy.refsig.pathlossReferenceLifetime(cfgLegacy)=="configured_age_limit");
assert(sixgr.phy.refsig.pathlossReferenceLifetime(struct())=="configured_age_limit");
for value={NaN,Inf,true,{},struct(),["retained_filtered_reference","configured_age_limit"],"ignore_reference"}
    bad=cfg; bad.rf.frontend.ul_power_control.pathloss_reference_lifetime=value{1};
    reject(@()sixgr.phy.refsig.pathlossReferenceLifetime(bad),'sixgr:refsig:InvalidPathlossReferenceLifetime');
end
for value={NaN,-1,-Inf,true,'20',"20",[],[1 2],1+1i}
    bad=s; bad.rf_frontend.ul_power_control.max_pathloss_measurement_age_slots=value{1};
    reject(@()sixgr.lls6g.buildInternalConfig(bad,tempname),'sixgr:lls6g:config:InvalidULPowerControlPathlossAge');
end
% No power, reference identity, waveform schedule or decoder threshold change.
assert(isequal(cfg.phy.pusch.powerControl.pathlossReference,cfgLegacy.phy.pusch.powerControl.pathlossReference));
assert(isequal(cfg.validation.pucch_resources,cfgLegacy.validation.pucch_resources));
fprintf('PATHLOSS_REFERENCE_LIFETIME_POLICY_PASS YAML_binding=1 malformed_values_rejected=1 PHY_executions=0\n');
ok=true;
end
function reject(f,id)
try
    f();
catch e
    assert(strcmp(e.identifier,id),'Expected %s, got %s.',id,e.identifier); return;
end
error('test:ExpectedRejection','Expected %s.',id);
end
