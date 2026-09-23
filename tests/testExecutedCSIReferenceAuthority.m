function ok=testExecutedCSIReferenceAuthority()
% Real coded DL/CSI-RS TX through the shared owner; no UE CSI result used.
[ok,state]=testSharedDataPhysicalQueue("TDD",true);
assert(ok);
cfg=state.CfgMobility;
calendar=table([0;1],'VariableNames',{'CSIReferenceSlot'});
[eligible,evidence]=sixgr.truth.resolveCSIReceiveReferenceEvidence(state,cfg,1,1,calendar,9);
assert(isequal(eligible,[false;true]) && height(evidence)==1 && evidence.Slot==1, ...
    'test:ExecutedCSIReferenceRequired','Only the actually transmitted in-sweep reference may qualify.');
assert(isempty(state.ControlTrials.CSIRS), ...
    'This test must not depend on UE CSI measurement completion.');
poison=state;
poison.ControlTrials.CSIRS=struct('Observed',false,'Consumed',false, ...
    'ChannelEstimateAvailable',false,'CSIMeasurementAvailable',false, ...
    'ResourceExtractionAvailable',false,'CQI',99,'RI',99);
poison.PendingCSITable="deliberately_not_a_report_table";
[same,proof]=sixgr.truth.resolveCSIReceiveReferenceEvidence(poison,cfg,1,1,calendar,9);
assert(isequal(eligible,same) && isequaln(evidence,proof), ...
    'test:CSIReceiveLayoutUsesUEOutcome','GNB applicability cannot use UE measurement or payload state.');
for variant=["no_tx","previous_sweep","unfinished","epoch","resource","report_epoch","cell","gap"]
    s=state; c=cfg;
    switch variant
        case "no_tx", s.SharedDataTXLedger={};
        case "previous_sweep", s.SweepPointStartSlot=2;
        case "unfinished"
            s.SharedDataTXLedger{1}.Identity.EndSampleExclusive=state.SharedWaveformStream.Events.NextSampleIndex+1;
        case "epoch", s.SharedDataTXLedger{1}.CSIReference.PhysicalConfigurationEpoch=999;
        case "resource", c.phy.csirs.resourceSetID=c.phy.csirs.resourceSetID+1;
        case "report_epoch", c.phy.csi.reportConfiguration.Epoch=c.phy.csi.reportConfiguration.Epoch+1;
        case "cell", s.SharedDataTXLedger{1}.CSIReference.ServingCell=2;
        case "gap"
            c.phy.rsla.measurement_gaps=struct('enabled',true,'period_slots',10,'offset_slots',0,'length_slots',1);
    end
    [none,empty]=sixgr.truth.resolveCSIReceiveReferenceEvidence(s,c,1,1,calendar,9);
    assert(~any(none) && isempty(empty),'Unexpected reference eligibility: %s.',variant);
end
fake=state; fake.SharedDataTXLedger{1}.Identity.TransmissionID="unexecuted_preparation";
rejected=false;
try
    sixgr.truth.resolveCSIReceiveReferenceEvidence(fake,cfg,1,1,calendar,9);
catch err
    if ~strcmp(err.identifier,'sixgr:truth:CSIReferenceTXNotExecuted'), rethrow(err); end
    rejected=true;
end
assert(rejected,'A fabricated TX ledger must fail physical-owner binding.');
fprintf('EXECUTED_CSI_REFERENCE_AUTHORITY_PASS actual_TX=1 UE_measurement_dependency=0 negative_cases=9\n');
ok=true;
end
