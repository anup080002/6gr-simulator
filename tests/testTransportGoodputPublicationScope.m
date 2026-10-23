function ok=testTransportGoodputPublicationScope()
setup6GRSimToolkit('Verbose',false);
T=table(["DL";"DL"],[1;1],["tb1";"tb1"],[1;1],[800;800],[1;2], ...
    'VariableNames',{'Direction','UEIndex','LogicalTBID','CRCPass','TBSize_bits','Slot'});
T.SweepPointIndex=ones(2,1); T.NDIEpoch=ones(2,1);
T=sixgr.kpi.creditTransportGoodput(T);
original=T;
cfg=struct('run',struct('scenarioID',"fixture",'runTag',"run1",'executionID',"exec1"), ...
    'meta',struct('configHash',repmat('a',1,64)));
bound=sixgr.truth.bindCoupledExecutionIdentity(T,cfg,"DL");
assert(isequal(bound.UniqueDeliveredTBBits,[800;0]) && ...
    isequal(bound.TransportGoodputPrePublicationKey,original.TransportGoodputKey) && ...
    sum(sixgr.kpi.transportGoodputBits(bound))==800);
assert(contains(bound.TransportGoodputKey(1),'"RunID":"run1"'));
again=sixgr.truth.bindCoupledExecutionIdentity(bound,cfg,"DL");
assert(isequaln(again,bound),'Binding must be idempotent.');
slice=sixgr.truth.bindCoupledExecutionIdentity(original(2,:),cfg,"DL");
assert(slice.UniqueDeliveredTBBits==0,'A sliced retry must not gain new payload credit.');
% Reproduce the legacy export: lifecycle columns were added after credit.
legacy=original; legacy.RunID=repmat("run1",2,1);
legacy.ExecutionID=repmat("exec1",2,1); legacy.ConfigHash=repmat(string(cfg.meta.configHash),2,1);
fixed=sixgr.truth.bindCoupledExecutionIdentity(legacy,cfg,"DL");
assert(sum(sixgr.kpi.transportGoodputBits(fixed))==800);
failed=original(1,:); failed.CRCPass=0;
failed=sixgr.kpi.creditTransportGoodput(failed);
failed.TransportGoodputKey=string(missing); % Declared CSV empty-field representation.
assert(sixgr.kpi.transportGoodputBits(failed)==0);
failed=sixgr.truth.bindCoupledExecutionIdentity(failed,cfg,"DL");
assert(failed.UniqueDeliveredTBBits==0 && failed.TransportGoodputKey=="");
for mutation=["crc","bits","epoch","run"]
    bad=legacy;
    switch mutation
        case "crc", bad.CRCPass(1)=0;
        case "bits", bad.TBSize_bits(1)=801;
        case "epoch", bad.NDIEpoch(1)=2;
        case "run", bad.RunID(1)="another_run";
    end
    caught=false;
    try
        sixgr.truth.bindCoupledExecutionIdentity(bad,cfg,"DL");
    catch e
        caught=startsWith(string(e.identifier),["sixgr:kpi:","sixgr:truth:"]);
        caught=any(caught);
    end
    assert(caught,'Corrupted CRC/payload/scientific scope/run identity must remain rejected.');
end
ok=true;
end
