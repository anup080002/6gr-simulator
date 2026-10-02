function ok=testSLSExecutingULReservations()
% Future K2 grants must remain legal against execution-time control ownership.
cfg=sixgr.config.defaultConfig();
cfg.phy.pdcch.enable=false; cfg.phy.srs.enable=false; cfg.phy.pucch.enable=false;
budget=struct('NPRB',6,'PRBSet',0:5,'SymbolAllocation',[0 14]);
slot0=NaN;
for s=2:39
    partition=sixgr.util.resolveTDDSlotPartition(cfg,s);
    if isequal(double(partition.ULSymbolAllocation),[0 14]), slot0=s; break; end
end
assert(isfinite(slot0),'Fixture needs a full UL slot after the issuance occasion.');
context=struct('CellID',1,'AsOfAbsoluteSlot0',0,'PUCCHObligationsComplete',true);
early=sixgr.system.resolveSLSResourceReservations(cfg,slot0+1,"UL",budget,context);
grant=struct('PRBSet',1,'SymbolAllocation',[0 14],'ScheduledAbsoluteSlot',slot0, ...
    'ControlAbsoluteSlot',0,'TBSBits',1000);
sixgr.system.assertSLSGrantsRespectReservations(grant,early);
context.AsOfAbsoluteSlot0=slot0;
current=sixgr.system.resolveSLSResourceReservations(cfg,slot0+1,"UL",budget,context);
sixgr.system.assertSLSExecutingULReservations(grant,1,{current},slot0);
context.Obligations=struct('ResourceID',"late_control",'CellID',1,'UEIndex',1, ...
    'Direction',"UL",'AbsoluteSlot0',slot0,'KnownAtAbsoluteSlot0',1,'Channel',"PUCCH", ...
    'Coordinates0Based',[12 11 0],'EvidenceKind',"scheduled_receive_obligation", ...
    'Source',"explicit_test_obligation_not_physical_reception",'Transport',"PUCCH");
late=sixgr.system.resolveSLSResourceReservations(cfg,slot0+1,"UL",budget,context);
frozen=grant;
reject(@()sixgr.system.assertSLSExecutingULReservations(grant,1,{late},slot0), ...
    'sixgr:system:ReservedResourceCollision');
assert(isequaln(grant,frozen),'A failed reservation check must not rewrite a frozen grant or TBS.');
reject(@()sixgr.system.assertSLSExecutingULReservations(grant,1,{early},slot0), ...
    'sixgr:system:ReservationExecutionClock');
reject(@()sixgr.system.assertSLSExecutingULReservations(grant,2,{current},slot0), ...
    'sixgr:system:ReservationGrantOwnership');
reject(@()sixgr.system.assertSLSExecutingULReservations(grant,1,{current},slot0+1), ...
    'sixgr:system:ReservationExecutionClock');
sixgr.system.assertSLSExecutingULReservations(struct([]),[],{current},slot0);
ok=true; fprintf('SLS_EXECUTING_UL_RESERVATIONS_PASS\n');
end
function reject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Expected %s got %s: %s',id,ME.identifier,ME.message); return; end
error('test:MissingRejection','Expected %s',id);
end
