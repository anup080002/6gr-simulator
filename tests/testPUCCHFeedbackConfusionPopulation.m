function ok=testPUCCHFeedbackConfusionPopulation()
% Declared receipt-format boundaries. No waveform or H0 statistics claim.
a=episode("absent_false_ACK",0,1,false);
b=episode("absent_correct_DTX",0,0,true);
c=episode("present_missed",10,0,true);
t=[struct2table(a);struct2table(b);struct2table(c)]; before=t;
r=sixgr.report.collectPUCCHFeedbackConfusion(t,"DTX_TO_ACK");
assert(r.Status=="PASS"&&r.Numerator==1&&r.Denominator==2&&r.Rate==.5);
assert(isequaln(before,t)&&~r.StatisticallyQualified);
% Changing received DTX verdict cannot change independently defined H0.
t.DTXFlag=~t.DTXFlag;
same=sixgr.report.collectPUCCHFeedbackConfusion(t,"DTX_TO_ACK");
assert(isequaln(r,same));
unknown=removevars(t,'PresenceEvidenceJSON');
r=sixgr.report.collectPUCCHFeedbackConfusion(unknown,"DTX_TO_ACK");
assert(r.Status=="NOT_EXERCISED"&&r.Denominator==0&&isnan(r.Rate));
bad=t; bad.PresenceObservationID(1)="wrong";
reject(@()sixgr.report.collectPUCCHFeedbackConfusion(bad,"DTX_TO_ACK"));
bad=t; bad.SignalPresent(3)=0; bad.PresenceTargetNonzeroInputSamples(3)=0;
reject(@()sixgr.report.collectPUCCHFeedbackConfusion(bad,"DTX_TO_ACK"));
n=episode("present_nack_false_ack",10,1,false); n.ExpectedAck=0;
r=sixgr.report.collectPUCCHFeedbackConfusion(struct2table(n),"NACK_TO_ACK");
assert(r.Numerator==1&&r.Denominator==1);
n.ReceiverExpectedHARQBitCount=2; % Scalar ExpectedAck cannot score two bits.
r=sixgr.report.collectPUCCHFeedbackConfusion(struct2table(n),"NACK_TO_ACK");
assert(r.Status=="NOT_EXERCISED");
ok=true;
end
function r=episode(name,count,ack,dtx)
components=struct('ComponentID',name,'StartSample',0,'EndSampleExclusive',100, ...
    'NonzeroSampleCount',count,'OriginalSampleSHA256',string(repmat('a',1,64)));
receipt=struct('Schema',"consumed_waveform_components/v1",'CompleteContributorList',true, ...
    'StartSample',0,'EndSampleExclusive',100,'Components',components);
roster=struct('TransmitterID',"ue_1",'CommittedThroughSample',100,'Receipt',receipt);
segment=struct('StartSample',0,'EndSampleExclusive',100,'ConfigurationEpoch',1, ...
    'SampleRateHz',1000,'ExecutedContributors',roster);
e=struct('Schema',"shared_PUCCH_presence_receipts/v1",'ObservationID',name, ...
    'PhysicalOccasionID',name, ...
    'ConfigurationEpoch',1,'ReceiverAssignmentDigest',"assignment", ...
    'ReceiverContextDigest',"context",'RXStartSample',0,'RXEndSampleExclusive',100, ...
    'TXStartSample',0,'TXEndSampleExclusive',100,'SampleRateHz',1000, ...
    'TXSegments',segment,'RXSegments',struct('StartSample',0,'EndSampleExclusive',100));
raw=string(jsonencode(e));
r=struct('PresenceScoringStatus',"observed_executed_component_presence", ...
    'PresenceEvidenceJSON',raw,'PresenceEvidenceSHA256',sixgr.phy.pucch.PUCCHUtil.hash(raw), ...
    'PresenceObservationID',name,'PresenceReceiverAssignmentDigest',"assignment", ...
    'PresenceReceiverContextDigest',"context",'PresenceConfigurationEpoch',1, ...
    'PresenceRXStartSample',0,'PresenceRXEndSampleExclusive',100,'PresenceSampleRateHz',1000, ...
    'PresenceUEIndex',1,'PresenceRNTI',7,'UEIndex',1,'RNTI',7, ...
    'ReceiverAssignmentDigest',"assignment",'ReceiverContextDigest',"context", ...
    'ObservationStartSample',0,'ObservationEndSampleExclusive',100,'ObservationSampleRateHz',1000, ...
    'PhysicalPUCCHOccasionId',name,'PresenceScoringUsedByReceiver',false, ...
    'PresenceTargetNonzeroInputSamples',count,'SignalPresent',double(count>0), ...
    'ObservedHARQACKBitCount',ack,'ExpectedAck',1,'ReceiverExpectedHARQBitCount',1,'DTXFlag',dtx);
end
function reject(f)
try, f(); catch e
    assert(string(e.identifier)=="sixgr:report:FeedbackPresenceAuthorityMismatch"); return;
end
error('sixgr:test:ExpectedRejection','Contradictory presence receipt was accepted.');
end
