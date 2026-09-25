function ok=testSRSPUCCHSameUESymbolPriority()
% Allocation mathematics only, not proof of physical SRS suppression.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_rank2_4tx2rx_awgn_m10db.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
% First verify the target uses the legal, nonoverlapping resource plan.
target=struct('ScheduledAbsoluteSlot',35,'UEIndex',1,'RNTI',1, ...
    'PUCCHResourceId',"0",'UCIType',"harq_ack");
assert(cfg.phy.srs.SymbolStart==11);
safe=sixgr.phy.frame.resolveSRSPUCCHCollision(cfg,target,35,1);
assert(~safe.Collision && safe.OverlapSymbolCount==0);
% Deliberately restore the old overlap in this allocation-only negative case.
cfg.phy.srs.SymbolStart=13;
resources=cfg.validation.pucch_resources.resources;
index=find(arrayfun(@(r)double(r.id)==0,resources)); assert(isscalar(index));
resources(index).starting_prb=24; % SRS occupies RB 0..23, same symbol 13.
cfg.validation.pucch_resources.resources=resources;
row=struct('ScheduledAbsoluteSlot',5,'UEIndex',1,'RNTI',1, ...
    'PUCCHResourceId',"0",'UCIType',"harq_ack");
same=sixgr.phy.frame.resolveSRSPUCCHCollision(cfg,row,5,1);
assert(same.OverlapRECount==0 && same.SameUESymbolCollision && same.Collision && ...
    same.OverlapSymbolCount==1 && same.DroppedSRSSymbols0Based=="13" && ...
    same.RetainedSRSSymbols0Based=="[]");
other=sixgr.phy.frame.resolveSRSPUCCHCollision(cfg,row,5,2);
assert(~other.SameUE && other.OverlapRECount==0 && ~other.Collision);
resources(index).starting_symbol=11;
cfg.validation.pucch_resources.resources=resources;
disjoint=sixgr.phy.frame.resolveSRSPUCCHCollision(cfg,row,5,1);
assert(~disjoint.Collision && disjoint.OverlapSymbolCount==0);
cfg.phy.srs.SymbolStart=12; cfg.phy.srs.NumSRSSymbols=2;
partial=sixgr.phy.frame.resolveSRSPUCCHCollision(cfg,row,5,1);
assert(partial.Collision && partial.DroppedSRSSymbols0Based=="12" && ...
    partial.RetainedSRSSymbols0Based=="13" && ...
    partial.Action=="drop_overlapping_srs_symbols_preserve_pucch");
fprintf('SRS_PUCCH_SYMBOL_PRIORITY_PASS disjoint_PRBs_same_UE=1 cross_UE=1 partial_symbols_preserved_in_plan=1 physical_suppression_verified=0\n');
ok=true;
end
