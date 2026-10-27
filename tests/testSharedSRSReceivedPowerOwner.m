function ok=testSharedSRSReceivedPowerOwner()
% Preparation ownership only; no received TPC or RF outcome is invented.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
assert(string(cfg.rf.frontend.ul_power_control.srs.adjustment_state)=="same_as_pusch");
randomState=rng;
[state,bound]=sixgr.truth.bindSharedSRSReceivedPowerOwner(struct(),cfg,1);
owner=state.SharedUEULPowerControlStates{1};
assert(isa(owner,'sixgr.link.ReceivedULPowerControlState') && ...
    isempty(owner.Entries) && isempty(owner.History) && ...
    isequaln(owner,bound.phy.srs.receivedPowerControlState));
[again,rebound]=sixgr.truth.bindSharedSRSReceivedPowerOwner(state,bound,1);
assert(isequaln(again,state) && isequaln(rebound,bound));
% The live per-UE owner is authoritative over a stale preparation copy.
stale=bound; stale.phy.srs.receivedPowerControlState=struct('Stale',true);
[again,rebound]=sixgr.truth.bindSharedSRSReceivedPowerOwner(state,stale,1);
assert(isequaln(again,state) && isequaln(rebound,bound));
wrong=cfg; wrong.phy.pusch.RNTI=double(owner.RNTI)+1;
wrong.phy.pdsch.RNTI=wrong.phy.pusch.RNTI;
rejects(@()sixgr.truth.bindSharedSRSReceivedPowerOwner(state,wrong,1), ...
    'sixgr:power:WrongEndpoint');
invalid=state; invalid.SharedUEULPowerControlStates{1}=struct('Invalid',true);
rejects(@()sixgr.truth.bindSharedSRSReceivedPowerOwner(invalid,cfg,1), ...
    'sixgr:srs:MissingReceivedPowerState');
invalid.SharedUEULPowerControlStates=struct();
rejects(@()sixgr.truth.bindSharedSRSReceivedPowerOwner(invalid,cfg,1), ...
    'sixgr:srs:InvalidReceivedPowerOwners');
open=cfg; open.rf.frontend.ul_power_control.srs.adjustment_state='open_loop_only';
[unchanged,unchangedCfg]=sixgr.truth.bindSharedSRSReceivedPowerOwner(state,open,1);
assert(isequaln(unchanged,state) && isequaln(unchangedCfg,open) && isequal(rng,randomState));
ok=true;
end

function rejects(fn,id)
try
    fn();
catch cause
    assert(strcmp(cause.identifier,id),'%s',getReport(cause));
    return;
end
error('test:ExpectedRejection','Missing rejection %s.',id);
end
