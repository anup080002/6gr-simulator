function ok=testSLSCommonChannelCalendar()
% Exact common-RS ownership is shared by the scheduler and its denominator.
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_rank2_shared_awgn_20db.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
cfg.phy.pdcch.enable=false; cfg.phy.pucch.enable=false; cfg.phy.srs.enable=false;
c=sixgr.system.buildSLSCommonChannelCalendar(cfg,58);
assert(~c.PhysicalTransmissionProven && ~isempty(c.Allocations));
assert(any(c.Allocations.channel=="SSB_PBCH") && any(c.Allocations.channel=="CSI_RS"));
total=0;
for slot0=0:57
    partition=sixgr.util.resolveTDDSlotPartition(cfg,slot0);
    sym=double(partition.DLSymbolAllocation);
    if sym(2)==0, continue; end
    budget=struct('NPRB',cfg.phy.carrier.NSizeGrid, ...
        'PRBSet',0:cfg.phy.carrier.NSizeGrid-1,'SymbolAllocation',sym);
    context=struct('CellID',1,'AsOfAbsoluteSlot0',slot0, ...
        'PUCCHObligationsComplete',false,'CommonChannelAllocations',c.Allocations);
    r=sixgr.system.resolveSLSResourceReservations(cfg,slot0+1,"DL",budget,context);
    total=total+height(r.Evidence);
    assert(all(~r.Evidence.PhysicalTransmissionProven));
    assert(~any(r.SchedulerAvailablePRBSymbolMask & r.ReservedPRBSymbolMask,'all'));
end
assert(total>0); ok=true; fprintf('SLS_COMMON_CHANNEL_CALENDAR_PASS reservation_rows=%d\n',total);
end
