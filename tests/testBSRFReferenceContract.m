function ok=testBSRFReferenceContract()
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
r=cfg.rf.bsPowerReference;
assert(r.RFType=="1-O"&&r.RequirementBoundary=="RIB"&&r.PhysicalTXChains==64&&r.PhysicalRXChains==64);
assert(~r.HardwareConformanceVerified && ~r.InternalChainPowerIsTRP && ...
    ~r.InternalChainPowerIsDirectionalEIRP);
assert(r.BudgetPlane=="internal_pre_rf_total"&&r.AntennaGainOwner=="physical_array_channel");
context=sixgr.rf.PowerContext(cfg,'DL');
assert(context.TotalTxPower_dBm==30,'Selecting RF type must not multiply the power budget.');
badCfg=cfg; badCfg.scenario.bs.txGain_dBi=3;
reject(@()sixgr.rf.PowerContext(badCfg,'DL'),'RF:DuplicateBSArrayGain');
badCfg=cfg; badCfg.scenario.bs.rxGain_dBi=3;
reject(@()sixgr.rf.PowerContext(badCfg,'UL'),'RF:DuplicateBSArrayGain');
raw=s.toStruct(); d=raw.power_and_rf_frontend.bs_reference;
bad=d; bad.budget_plane='TRP'; reject(@()sixgr.rf.resolveBSRFReference(bad,64,64),'RF:BSReferenceContract');
bad=d; bad.requirement_boundary='TAB'; reject(@()sixgr.rf.resolveBSRFReference(bad,64,64),'RF:BSReferenceContract');
bad=d; bad.antenna_gain_owner='extra_link_budget_gain'; reject(@()sixgr.rf.resolveBSRFReference(bad,64,64),'RF:BSReferenceContract');
reject(@()sixgr.rf.resolveBSRFReference(d,64,4),'RF:BSReferenceChains');
raw.antenna_and_array.bs_num_rxrus=4;
reject(@()sixgr.lls6g.config.validateScenarioConfig(raw),'RF:BSReferenceChains');
ok=true; disp('BS_RF_REFERENCE_CONTRACT_PASS type_1O=1 RIB=1 no_power_relabeling=1');
end
function reject(action,id)
try, action(); catch cause
    assert(string(cause.identifier)==id,'Expected %s, got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingGuard','Expected %s.',id);
end
