function ok=testSharedPUCCHPresenceScoring()
% Deterministic receipt/arithmetic fixtures, not a radio reliability test.
setup6GRSimToolkit('Verbose',false);
for mode=["silent","target","background","deep_null","cancelled","composite_cancellation"]
    [item,rx]=fixture(mode);
    before=rx;
    score=sixgr.truth.scoreSharedPUCCHPresence(item,rx,7);
    present=any(mode==["target","deep_null","composite_cancellation"]);
    assert(score.SignalPresent==double(present) && isequaln(rx,before));
    assert(~score.PresenceIndependentTrialsEstablished && ~score.PresenceScoringUsedByReceiver);
    if present
        assert(score.PresenceTargetNonzeroInputSamples>0 && isnan(score.FalseAlarmFlag));
    else
        assert(score.PresenceTargetNonzeroInputSamples==0 && score.FalseAlarmFlag==1 && score.FalseAcceptanceFlag==1);
        if mode=="background"
            assert(score.TrialType=="target_absent_with_background");
        else
            assert(score.TrialType=="no_signal_before_receiver_noise_and_RF");
        end
    end
end
[item,rx]=fixture("silent");
% A wider execution interval cannot prove its nonzero samples fall in the
% capture. A separate exact in-capture nonzero interval does prove background.
clipped=item;
s=clipped.Planes(2).Segments{1};
s.StartSample=-4; s.EndSampleExclusive=12;
s.Execution.StartSample=-4; s.Execution.EndSampleExclusive=12;
s.Execution.SignalContributions.NonzeroSampleCount=1;
s.Execution.SignalContributions.SampleCount=16;
clipped.Planes(2).Segments={s};
uncertain=sixgr.truth.scoreSharedPUCCHPresence(clipped,rx,7);
assert(uncertain.SignalPresent==0 && uncertain.TrialType=="target_absent_receiver_background_unknown");
first=s; first.StartSample=0; first.EndSampleExclusive=4;
first.Execution.StartSample=0; first.Execution.EndSampleExclusive=4;
first.Execution.SignalContributions.SampleCount=4;
s.StartSample=4; s.Execution.StartSample=4;
s.Execution.SignalContributions.SampleCount=8;
clipped.Planes(2).Segments={first,s};
definite=sixgr.truth.scoreSharedPUCCHPresence(clipped,rx,7);
assert(definite.TrialType=="target_absent_with_background" && ...
    definite.PresenceReceiverBackground=="nonzero_link_contribution_in_capture");
crcRejected=rx; crcRejected.CRCApplicable=true; crcRejected.CRCPassed=false;
crcScore=sixgr.truth.scoreSharedPUCCHPresence(item,crcRejected,7);
assert(crcScore.FalseAlarmFlag==1 && crcScore.FalseAcceptanceFlag==0);
truncated=rx; truncated.DecodedFields.CSIPart1=int8([]);
partial=sixgr.truth.scoreSharedPUCCHPresence(item,truncated,7);
assert(partial.FalseAlarmFlag==1 && partial.FalseAcceptanceFlag==0);
retained=sixgr.truth.scoreSharedPUCCHPresence(item,rx,7);
assert(retained.PresenceEvidenceSHA256==sixgr.phy.pucch.PUCCHUtil.hash(retained.PresenceEvidenceJSON));
json=jsondecode(retained.PresenceEvidenceJSON);
assert(string(json.Schema)=="shared_PUCCH_presence_receipts/v1" && ...
    isempty(json.TXSegments.ExecutedContributors.Receipt.Components));
missing=item;
missing.Planes(1).Segments{1}.Execution=rmfield(missing.Planes(1).Segments{1}.Execution,'ExecutedContributors');
unknown=sixgr.truth.scoreSharedPUCCHPresence(missing,rx,7);
assert(isnan(unknown.SignalPresent) && isnan(unknown.FalseAlarmFlag));
rx.DetectionOutcome="dtx"; rx.DTX=true; rx.ReceiverUsable=false;
quiet=sixgr.truth.scoreSharedPUCCHPresence(item,rx,7);
assert(quiet.FalseAlarmFlag==0 && quiet.FalseAcceptanceFlag==0);
rx.DetectionOutcome="unavailable";
unknownDecision=sixgr.truth.scoreSharedPUCCHPresence(item,rx,7);
assert(unknownDecision.SignalPresent==0 && isnan(unknownDecision.FalseAlarmFlag));
bad=item; bad.Context.ObservationID="wrong"; reject(@()sixgr.truth.scoreSharedPUCCHPresence(bad,rx,7));
bad=item; bad.Context.GNBReception.Assignment.Data.ObservationID="wrong";
reject(@()sixgr.truth.scoreSharedPUCCHPresence(bad,rx,7));
reject(@()sixgr.truth.scoreSharedPUCCHPresence(item,rx,8));
bad=item; bad.Planes(1).Segments{1}.Execution.ExecutedContributors(1).CommittedThroughSample=0;
reject(@()sixgr.truth.scoreSharedPUCCHPresence(bad,rx,7));
bad=item; bad.Planes(1).Segments=[bad.Planes(1).Segments,bad.Planes(1).Segments];
reject(@()sixgr.truth.scoreSharedPUCCHPresence(bad,rx,7));
bad=item; bad.Planes(2).Segments{1}.Execution.SignalContributions=struct([]);
reject(@()sixgr.truth.scoreSharedPUCCHPresence(bad,rx,7));
bad=item; bad.Planes(2).Segments{1}.Execution.SampleRateHz=999;
reject(@()sixgr.truth.scoreSharedPUCCHPresence(bad,rx,7));
% Same slot/context is insufficient: wrong assignment, cell or occasion
% cannot attach an audit to a different receiver trial.
T=table(1,1,4660,1,"observation_key","assignment","context",0,8,1000, ...
    'VariableNames',{'UEIndex','Slot','RNTI','ServingCell','PhysicalPUCCHOccasionId', ...
    'ReceiverAssignmentDigest','ReceiverContextDigest','ObservationStartSample', ...
    'ObservationEndSampleExclusive','ObservationSampleRateHz'});
state=struct('SharedWaveformStream',struct('Physical',struct('ConfigurationEpoch',7)), ...
    'ControlTrials',struct('PUCCH',T));
bound=sixgr.truth.bindSharedPUCCHPresence(state,item,rx);
assert(bound.ControlTrials.PUCCH.SignalPresent==0);
for field=["ReceiverAssignmentDigest","PhysicalPUCCHOccasionId"]
    bad=state; bad.ControlTrials.PUCCH.(field)="wrong";
    reject(@()sixgr.truth.bindSharedPUCCHPresence(bad,item,rx),'sixgr:truth:AmbiguousPUCCHPresenceTrial');
end
bad=state; bad.ControlTrials.PUCCH.RNTI=7;
reject(@()sixgr.truth.bindSharedPUCCHPresence(bad,item,rx),'sixgr:truth:AmbiguousPUCCHPresenceTrial');
fprintf('SHARED_PUCCH_PRESENCE_SCORING_PASS exact_emission=1 background_and_tail_not_H0=1 missing_unknown=1 identity_and_clock_rejection=1\n');
ok=true;
end

function [item,rx]=fixture(mode)
fs=1000;
r=sixgr.phy.waveform.WaveformEventRuntime(fs,0, ...
    @(inputs,first,stop,state)processor(inputs,first,stop,state,mode),[]);
r.addTransmitter('ue_1',1,'double');
r.addReceiver('ue_1:tx',1); r.addReceiver('gnb_1_rx:post_rf',1);
if any(mode==["target","deep_null","cancelled","composite_cancellation"])
    r.enqueue('ue_1','target',sixgr.phy.waveform.WaveformChunk(complex(ones(8,1)),0));
end
if mode=="cancelled", r.cancelUnemittedComponent('ue_1','target'); end
if mode=="composite_cancellation"
    r.enqueue('ue_1','other',sixgr.phy.waveform.WaveformChunk(complex(-ones(8,1)),0));
end
r.commitTransmissionsThrough('ue_1',8);
r.observe('ue_1:tx','target',0,8); r.observe('gnb_1_rx:post_rf','target',0,8);
event=r.advanceUntilEvent(8);
h=struct('UEIndex',1,'RNTI',4660,'ServingCell',1, ...
    'Mapping',struct([]),'CSIReportCalendar',table("component_obligation",'VariableNames',{'ObligationID'}), ...
    'Assignment',struct('Digest',"assignment",'Resource',struct('Digest',"resource"), ...
        'Data',struct('ObservationID',"target",'RNTI',4660,'AbsoluteSlot0',0)), ...
    'Context',struct('Digest',"context",'Data',struct('ReportID',"target",'CSIPart1Bits',1), ...
        'HARQACKBits',0,'SRBits',0,'CSIPart1Bits',1,'CSIPart2Bits',0));
item=struct('ID',"target",'Kind',"PUCCH",'UE',1,'Context',struct('ObservationID',"target", ...
    'GNBReception',h,'Slot',1,'Key',"observation_key"),'Planes',rmfield(event.Completed,'ID'));
rx=struct('AssignmentDigest',"assignment",'ReportContextDigest',"context", ...
    'ReceiverObservationStartSample',0,'ReceiverObservationEndSampleExclusive',8, ...
    'ReceiverObservationSampleRateHz',fs,'DetectionOutcome',"detected", ...
    'ReceiverUsable',true,'DTX',false,'CRCApplicable',false,'CRCPassed',false, ...
    'DecodedFields',struct('HARQACK',int8([]),'SR',int8([]),'CSIPart1',int8(1),'CSIPart2',int8([])));
end

function [outputs,e,state]=processor(inputs,first,stop,state,mode)
x=inputs(1).Chunk.Samples;
y=x;
if mode=="deep_null", y(:)=0; end
if mode=="background", y(:)=1; end % Explicit retained-tail arithmetic fixture.
outputs=struct('ID',{'ue_1:tx','gnb_1_rx:post_rf'},'Chunk', ...
    {inputs(1).Chunk,sixgr.phy.waveform.WaveformChunk(y,first)});
e=struct('StartSample',first,'EndSampleExclusive',stop,'ConfigurationEpoch',7, ...
    'SampleRateHz',1000,'Source',"deterministic_receipt_scoring_fixture",'ApproximationMode',"none", ...
    'RX',struct('ID',"gnb_1_rx"),'Links',struct('ID',"link",'TX',"ue_1",'RX',"gnb_1_rx"), ...
    'SignalContributions',struct('LinkID',"link",'TX',"ue_1",'RX',"gnb_1_rx", ...
    'NonzeroSampleCount',nnz(y),'SampleCount',numel(y), ...
    'Source',"actual_link_after_TX_RF_channel_loss_before_noise_RX_RF"));
end

function reject(f,id)
if nargin<2, id='sixgr:truth:InvalidPUCCHPresenceEvidence'; end
try, f(); catch e, assert(strcmp(e.identifier,id),'Expected %s; got %s.',id,e.identifier); return; end
error('test:MissingRejection','Expected %s.',id);
end
