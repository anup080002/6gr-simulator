function ok=testPowerWithheldPUCCHForPUSCHBinding()
% Declared identity contracts only: this does not execute a PHY receiver.
setup6GRSimToolkit('Verbose',false);
[a,t,s,g,b,c]=fixture(); before={a,t,s,g,b,c};
f=@(aa,tt,ss,gg,bb,cc)sixgr.truth.bindPowerWithheldPUCCHForPUSCH(aa,tt,ss,gg,bb,cc);
bound=f(a,t,s,g,b,c);
assert(bound.ObservationID==a.ObservationID&&bound.LogicalPUCCHGrantIdSet=="harq_original|PUCCH-CSI-original"&& ...
    bound.UEReceivedCodebookDigest==b.Digest&&~bound.PhysicalReceiverQualified&&isequaln(bound.Admission,a));
assert(isequaln(before,{a,t,s,g,b,c}),'Validation must not mutate original evidence.');
retained=a; retained.PowerReferenceStatus="reference_lifecycle_unavailable";
retained.PathlossReferenceLifetime="retained_filtered_reference";
retained.ReferenceLifecycleStatus="no_observation_for_current_reference_power_generation";
boundRetained=f(retained,t,s,g,b,c);
assert(isequaln(boundRetained.Admission,retained)&&~boundRetained.PhysicalReceiverQualified);
for mutation=["missing","wrong_mode","available","unknown"]
    bad=retained;
    switch mutation
        case "missing", bad.ReferenceLifecycleStatus=[];
        case "wrong_mode", bad.PathlossReferenceLifetime="configured_age_limit";
        case "available", bad.ReferenceLifecycleStatus="retained_filtered_reference_available";
        case "unknown", bad.ReferenceLifecycleStatus="arbitrary_failure";
    end
    reject(@()f(bad,t,s,g,b,c));
end
bad=a; bad.PowerReferenceStatus="arbitrary_failure"; reject(@()f(bad,t,s,g,b,c));
for name=["missing_audit","duplicate_audit","wrong_observation","wrong_grant","wrong_control", ...
        "wrong_clock","future","wrong_epoch","wrong_BWP","wrong_receiver","prepared", ...
        "admitted","numeric_flag","wrong_scope","wrong_occasion","wrong_ids","wrong_report", ...
        "trace_executed","trace_transferred","trace_unsuppressed","trace_other_admission", ...
        "trace_other_sweep","duplicate_trace","wrong_event","empty_book","tx_identity"]
    aa=a;tt=t;ss=s;gg=g;bb=b;cc=c;
    switch name
        case "missing_audit", aa=a([],:);
        case "duplicate_audit", aa=[a;a];
        case "wrong_observation", aa.ObservationID="other";
        case "wrong_grant", ss.ULGrantContextID="other";
        case "wrong_control", cc.GNBControlObservationID="other";
        case "wrong_clock", aa.DecisionSample=101;
        case "future", cc.AvailableAtSample=99;
        case "wrong_epoch", cc.ConfigurationEpoch=2;
        case "wrong_BWP", cc.ActiveULBWP=1;
        case "wrong_receiver", cc.ReceiverID="gnb_2_rx:post_rf";
        case "prepared", aa.UETransmissionPrepared=true;
        case "admitted", aa.PreparationAdmitted=true;
        case "numeric_flag", aa.PreparationAdmitted=0;
        case "wrong_scope", aa.Source="prepared_intent";
        case "wrong_occasion", aa.PhysicalOccasionID="other";
        case "wrong_ids", aa.PUCCHGrantIDsJSON='["harq_original"]';
        case "wrong_report", aa.CSIReportIdentitiesJSON='["other"]';
        case "trace_executed", tt.GrantExecutedFlag(1)=true;
        case "trace_transferred", tt.MultiplexedOnPUSCH(1)=true;
        case "trace_unsuppressed", tt.UETransmissionSuppressed(1)=false;
        case "trace_other_admission", tt.PowerAdmissionObservationID(1)="other";
        case "trace_other_sweep", tt.SweepPointIndex(1)=2;
        case "duplicate_trace", tt=[t;t(1,:)];
        case "wrong_event", tt.SourceSlot(1)=3;
        case "empty_book", bb=sixgr.phy.pucch.HARQACKCodebookBuilder.build('TYPE2_DYNAMIC',struct([]),1);
        case "tx_identity", ss.PUCCHTransmissionID="actual_or_unexplained_TX";
    end
    reject(@()f(aa,tt,ss,gg,bb,cc));
end
% ACK/NACK received-event values are not a power admission decision. They
% retain their own digest and do not certify a UE transmission or reception.
e=b.Events.Data;e.State="NACK";
other=sixgr.phy.pucch.HARQACKCodebookState('TYPE2_DYNAMIC',sixgr.phy.pucch.HARQACKEvent(e),1);
changed=f(a,t,s,g,other,c);
assert(changed.UEReceivedCodebookDigest~=bound.UEReceivedCodebookDigest&&~changed.PhysicalReceiverQualified);
% Late-row corruption cannot hide behind the first matching logical grant.
late=t; late.UETransmissionSuppressed(end)=false; reject(@()f(a,late,s,g,b,c));
ok=true;fprintf('POWER_WITHHELD_PUSCH_BINDING_PASS negatives=32 retained_lifecycle=1 scope=declared_original_identity_contract_not_PHY\n');
end

function [a,t,s,g,b,c]=fixture()
disposition="closed_untransmitted_missing_measured_power_reference";
r=struct('PUCCHGrantId',"harq_original",'UEIndex',1,'RNTI',101,'ScheduledAbsoluteSlot',10, ...
    'ServingCell',1,'BaseStationID',1,'ComponentCarrier',0,'ActiveULBWP',0,'SweepPointIndex',1, ...
    'UETransmissionSuppressed',true,'UEProducerDisposition',disposition, ...
    'PowerAdmissionObservationID',"original_pucch_observation",'GrantExecutedFlag',false, ...
    'MultiplexedOnPUSCH',false,'UCIType',"harq_ack",'SourceSlot',4,'HarqID',0,'FeedbackForDirection',"DL");
t=struct2table([r;r],'AsArray',true);t.PUCCHGrantId(2)="PUCCH-CSI-original";t.UCIType(2)="csi_part1_part2";
occasion=sixgr.truth.CoupledTruthRuntime.sharedPUCCHOccasionKey(t(1,:));
r=struct('UEIndex',1,'ServingCell',1,'RNTI',101,'BaseStationID',1,'ComponentCarrier',0, ...
    'ActiveULBWP',0,'SweepPointIndex',1,'DecisionSlot',9,'PUCCHResourceSlot',10, ...
    'DecisionSample',100,'ClockEpoch',1,'SampleRateHz',30720000, ...
    'MeasuredPowerReferenceRequired',true,'PreparationAdmitted',false,'UETransmissionPrepared',false, ...
    'ObservationID',"original_pucch_observation",'PhysicalOccasionID',occasion, ...
    'SelectedGNBTransport',"PUSCH",'UEProducerDisposition',disposition, ...
    'PUCCHGrantIDsJSON',string('["harq_original","PUCCH-CSI-original"]'), ...
    'CSIReportIdentitiesJSON',string('["original"]'), ...
    'Source',"original_PUCCH_reference_preparation_admission", ...
    'EvidenceClass',"preparation_admission_not_PHY_execution", ...
    'Action',"defer_PUCCH_unavailable_measured_power_reference",'PowerReferenceStatus',"no_measurements");
a=struct2table(r,'AsArray',true);
s=struct('PUCCHObservationID',a.ObservationID,'UEIndex',1,'TargetSlot',10, ...
    'ULGrantContextID',"original_ul_grant",'GNBControlObservationID',"original_ul_control", ...
    'HARQMappingDigest',"original_mapping",'PUCCHTransmissionID',"",'SelectedAtSample',100, ...
    'Source',"gnb_scheduled_PUSCH_not_UE_transport_transfer");
g=struct('UEIndex',1,'RNTI',101,'Slot',10,'PHYGrant',struct('GrantContextId',"original_ul_grant"));
e=struct('DAI',1,'EventIndex',1,'PDSCHID',"declared_received_event",'Priority',0,'ServingCell',1, ...
    'State',"ACK",'UEId',1,'RNTI',101,'DataAbsoluteSlot',3,'HARQProcess',0,'TargetSlot',10, ...
    'PUCCHResourceIndicator',0,'ConfigurationEpoch',1);
b=sixgr.phy.pucch.HARQACKCodebookState('TYPE2_DYNAMIC',sixgr.phy.pucch.HARQACKEvent(e),1);
c=struct('ConfigurationEpoch',1,'UCIConfigurationEpoch',1,'SampleRateHz',30720000, ...
    'AvailableAtSample',200,'ComponentCarrier',0,'ActiveULBWP',0, ...
    'ReceiverID',"gnb_1_rx:post_rf",'GNBControlObservationID',"original_ul_control");
end
function reject(f)
try,f();catch ME
    assert(any(strcmp(ME.identifier,{'sixgr:truth:PowerWithheldPUCCHBinding','sixgr:truth:ReceivedPUCCHProducerMismatch'})), ...
        'Unexpected rejection %s',ME.identifier);return;
end
error('sixgr:test:PowerWithheldAccepted','Malformed original identities were accepted.');
end
