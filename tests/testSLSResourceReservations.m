function ok=testSLSResourceReservations()
% Causal ownership and scheduler denominator share one exact resource mask.
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_rank2_shared_awgn_20db.yaml');
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
cfg.phy.pdcch.enable=false; cfg.phy.srs.enable=false; cfg.phy.pucch.enable=true;
slot0=NaN;
for candidate=0:39
    partition=sixgr.util.resolveTDDSlotPartition(cfg,candidate);
    if isequal(double(partition.ULSymbolAllocation),[0 14]), slot0=candidate; break; end
end
assert(isfinite(slot0) && slot0>=1);
budget=struct('NPRB',6,'PRBSet',0:5,'SymbolAllocation',[0 14]);
o=struct('ResourceID',"ack_1",'CellID',2,'UEIndex',1,'Direction',"UL", ...
    'AbsoluteSlot0',slot0,'KnownAtAbsoluteSlot0',slot0-1,'Channel',"PUCCH", ...
    'Coordinates0Based',[12 11 0;12 11 1],'EvidenceKind',"scheduled_receive_obligation", ...
    'Source',"gNB_DCI_feedback_clock",'Transport',"PUCCH",'CSIOnly',false);
context=struct('CellID',2,'AsOfAbsoluteSlot0',slot0-1, ...
    'PUCCHObligationsComplete',true,'Obligations',o);
r=sixgr.system.resolveSLSResourceReservations(cfg,slot0+1,"UL",budget,context);
assert(isequal(r.Budget.PRBSet,[0 2 3 4 5]) && r.Budget.NPRB==5);
assert(r.InitialOpportunityCount==84 && r.ExactOpportunityCount==83 && ...
    r.SchedulerOpportunityCount==70 && r.OpportunityConservatismCount==13);
assert(r.Evidence.RECountWithoutPortDuplication==1 && ~r.Evidence.PhysicalTransmissionProven);
merged=context; merged.Obligations.CSIOnly=[];
mergedResult=sixgr.system.resolveSLSResourceReservations(cfg,slot0+1,"UL",budget,merged);
assert(isequal(mergedResult.ReservedPRBSymbolMask,r.ReservedPRBSymbolMask));
T=sixgr.system.buildResourceOpportunityTable(slot0+1,1,"UL",r.Budget,true);
assert(all(T.CellID==2) && T.NumSymbols==14 && numel(jsondecode(T.PRBSet))==5);
good=struct('PRBSet',[2 3],'SymbolAllocation',[0 14]);
sixgr.system.assertSLSGrantsRespectReservations(good,r);
bad=good; bad.PRBSet=1;
reject(@()sixgr.system.assertSLSGrantsRespectReservations(bad,r),'sixgr:system:ReservedResourceCollision');
future=context; future.Obligations.KnownAtAbsoluteSlot0=slot0;
reject(@()sixgr.system.resolveSLSResourceReservations(cfg,slot0+1,"UL",budget,future), ...
    'sixgr:system:NoncausalReservation');
missing=context; missing.PUCCHObligationsComplete=false;
reject(@()sixgr.system.resolveSLSResourceReservations(cfg,slot0+1,"UL",budget,missing), ...
    'sixgr:system:MissingPUCCHReservationAuthority');
onPUSCH=context; onPUSCH.Obligations.Transport="PUSCH";
reject(@()sixgr.system.resolveSLSResourceReservations(cfg,slot0+1,"UL",budget,onPUSCH), ...
    'sixgr:system:MissingPUSCHUCIReservationBinding');
carrier=nrCarrierConfig('NSizeGrid',6);
pusch=nrPUSCHConfig('PRBSet',2,'SymbolAllocation',[0 14]);
plan=sixgr.phy.ul.pusch.planUCIResources(carrier,pusch,.3,24,[1 0 0]);
g=struct('RNTI',1,'UEIndex',1,'ServingCell',2, ...
    'ControlAbsoluteSlot',slot0-1,'ScheduledAbsoluteSlot',slot0, ...
    'PRBSet',2,'SymbolAllocation',[0 14], ...
    'SLSUCIAllocation',plan);
onPUSCH.Obligations.RNTI=1;
onPUSCH.Obligations.PUSCHGrant=g;
onPUSCH.Obligations.PUSCHGrantSHA256=grantDigest(g);
onPUSCH.Obligations.PUSCHUCIAllocatedRECount=plan.AllocatedRECount;
onPUSCH.IssuedPUSCHGrants=g;
v=sixgr.system.resolveSLSResourceReservations(cfg,slot0+1,"UL",budget,onPUSCH);
assert(v.SchedulerOpportunityCount==84 && isempty(v.Evidence));
manual=onPUSCH;
manual.Obligations.PUSCHGrant.SLSUCIAllocation=rmfield(plan,'SHA256');
manual.Obligations.PUSCHGrantSHA256=grantDigest(manual.Obligations.PUSCHGrant);
manual.IssuedPUSCHGrants=manual.Obligations.PUSCHGrant;
reject(@()sixgr.system.resolveSLSResourceReservations(cfg,slot0+1,"UL",budget,manual), ...
    'sixgr:system:PUSCHUCIReservationBinding');
futureCSI=onPUSCH; futureCSI.Obligations.CSIOnly=true;
futureCSI.Obligations.ReferenceAvailableAtSlot0=slot0;
reject(@()sixgr.system.resolveSLSResourceReservations(cfg,slot0+1,"UL",budget,futureCSI), ...
    'sixgr:system:NoncausalCSIReservation');
unissued=onPUSCH; unissued.IssuedPUSCHGrants=struct([]);
reject(@()sixgr.system.resolveSLSResourceReservations(cfg,slot0+1,"UL",budget,unissued), ...
    'sixgr:system:PUSCHUCIReservationBinding');
mutated=onPUSCH; mutated.Obligations.PUSCHGrant.PRBSet=3;
reject(@()sixgr.system.resolveSLSResourceReservations(cfg,slot0+1,"UL",budget,mutated), ...
    'sixgr:system:PUSCHUCIReservationBinding');
badRE=onPUSCH; badRE.Obligations.PUSCHGrant.SLSUCIAllocation.Coordinates0Based=[36 11;37 11];
badRE.Obligations.PUSCHGrantSHA256=grantDigest(badRE.Obligations.PUSCHGrant);
badRE.IssuedPUSCHGrants=badRE.Obligations.PUSCHGrant;
reject(@()sixgr.system.resolveSLSResourceReservations(cfg,slot0+1,"UL",budget,badRE), ...
    'sixgr:system:PUSCHUCIReservationBinding');
csi=context; csi.Obligations.CSIOnly=true; csi.Obligations.ReferenceAvailableAtSlot0=slot0;
reject(@()sixgr.system.resolveSLSResourceReservations(cfg,slot0+1,"UL",budget,csi), ...
    'sixgr:system:NoncausalCSIReservation');
allUsed=budget;
allUsed.ReservedResourceRegions=struct('PRBSet',0:5,'SymbolAllocation',[0 14]);
full=sixgr.system.resolveSLSResourceReservations(cfg,slot0+1,"UL",allUsed,context);
assert(full.Budget.NPRB==0 && isempty(full.Budget.PRBSet));
assert(isempty(sixgr.system.buildResourceOpportunityTable(slot0+1,1,"UL",full.Budget,true)));
emptyBudget=full.Budget;
empty=sixgr.system.resolveSLSResourceReservations(cfg,slot0+1,"UL",emptyBudget,context);
assert(empty.InitialOpportunityCount==0 && empty.SchedulerOpportunityCount==0);
for candidate=0:39
    partition=sixgr.util.resolveTDDSlotPartition(cfg,candidate);
    if double(partition.DLSymbolAllocation(2))==14
        wrongDirection=context; wrongDirection.AsOfAbsoluteSlot0=candidate;
        reject(@()sixgr.system.resolveSLSResourceReservations(cfg,candidate+1,"UL",budget,wrongDirection), ...
            'sixgr:system:ReservationTDDCollision');
        break;
    end
end
ok=true; fprintf('SLS_RESOURCE_RESERVATIONS_PASS\n');
end
function d=grantDigest(g)
d=string(sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(g),'UTF-8'))));
end
function reject(fn,id)
try,fn();catch ME,assert(strcmp(ME.identifier,id),'Expected %s got %s',id,ME.identifier);return;end
error('test:MissingRejection','Expected %s',id);
end
