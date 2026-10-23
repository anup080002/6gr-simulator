function ok=testSimultaneousULTransmitEvidence()
% Declared compact component receipts exercise joins/arithmetic, not RF runs.
setup6GRSimToolkit('Verbose',false);
ul=fixture("PUSCH",[10 30;50 60]); control=fixture("PUCCH",[20 40;55 65]);
[pairs,pop,rows]=sixgr.report.collectSimultaneousULTransmitEvidence(ul,control);
assert(height(pairs)==1 && all(rows.Qualified) && pop.CoverageComplete && ...
    pop.ObservedOverlapCount==1 && pop.OutcomePairCount==1 && ...
    pop.ConditionalSuccessRate==1 && pop.OverlapRate==1 && pairs.OverlapSamples==15);
assert(isequal(jsondecode(pairs.OverlapIntervalsJSON),[20 30;55 60]));
assert(pairs.PUSCHTransmissionID=="PUSCH_tx" && pairs.PUCCHTransmissionID=="PUCCH_tx");
% Same slot and same RX capture do not establish actual TX coexistence.
disjoint=fixture("PUCCH",[30 50;60 70]);
[p,z]=sixgr.report.collectSimultaneousULTransmitEvidence(ul,disjoint);
assert(isempty(p) && z.CoverageComplete && z.ObservedOverlapCount==0 && ...
    z.OverlapRate==0 && isnan(z.ConditionalSuccessRate) && z.OutcomePairCount==0);
% No any-PASS-by-slot pooling: failed payload and CRC belong to this pair.
failed=control; failed.UCIContentMatch=false;
[p,z]=sixgr.report.collectSimultaneousULTransmitEvidence(ul,failed);
assert(p.JointSuccess==0 && z.ConditionalSuccessRate==0 && z.FailedPairCount==1);
failedUL=ul; failedUL.CRCPass=0;
[p,z]=sixgr.report.collectSimultaneousULTransmitEvidence(failedUL,control);
assert(p.JointSuccess==0 && z.ConditionalSuccessRate==0);
erased=control; erased.DTXFlag=true; erased.UCIContentMatch=NaN;
[p,z]=sixgr.report.collectSimultaneousULTransmitEvidence(ul,erased);
assert(p.JointSuccess==0 && z.FailedPairCount==1);
crashed=control; crashed.Crash=true; crashed.Status="CRASH";
[p,z]=sixgr.report.collectSimultaneousULTransmitEvidence(ul,crashed);
assert(isnan(p.JointSuccess) && ~p.OutcomeQualified && z.ObservedOverlapCount==1 && ...
    z.OutcomePairCount==0 && z.UnknownOutcomePairCount==1 && ...
    z.FailedPairCount==0 && isnan(z.ConditionalSuccessRate));
% One failed pair cannot borrow another passing control occasion in its slot.
second=fixture("PUCCH",[10 15]); second=editEvidence(second,"Identity.TransmissionID","second_tx");
second=editEvidence(second,"Identity.ObservationID","second_rx");
second=editEvidence(second,"ReceiverBinding.SourceRowIdentity","second_occasion");
[p,z]=sixgr.report.collectSimultaneousULTransmitEvidence(ul,[failed;second]);
assert(height(p)==2 && z.ConditionalSuccessRate==0.5 && z.OutcomePairCount==2);
for field=["Identity.UEIndex","Identity.RNTI","Identity.ServingCell", ...
        "Identity.ClockEpoch","PopulationIdentity.SweepPointIndex", ...
        "PopulationIdentity.RandomSeed","PopulationIdentity.ChannelSeed"]
    other=editEvidence(control,field,2);
    if field=="Identity.UEIndex", other.UEIndex=2; other=editEvidence(other,"Identity.TransmitterID","ue_2"); end
    if field=="Identity.RNTI", other.RNTI=2; end
    if field=="Identity.ServingCell", other.BaseStationID=2; end
    [p,z,r]=sixgr.report.collectSimultaneousULTransmitEvidence(ul,other);
    assert(isempty(p) && all(r.Qualified) && z.ObservedOverlapCount==0 && isnan(z.ConditionalSuccessRate));
end
for field=["PopulationIdentity.RunFolder","PopulationIdentity.ExecutionID", ...
        "PopulationIdentity.ConfigHash"]
    other=editEvidence(control,field,"different");
    [p,z]=sixgr.report.collectSimultaneousULTransmitEvidence(ul,other);
    assert(isempty(p) && z.ObservedOverlapCount==0);
end
other=editEvidence(control,"SampleRateHz",2000);
[p,z]=sixgr.report.collectSimultaneousULTransmitEvidence(ul,other);
assert(isempty(p) && z.CoverageComplete && z.ObservedOverlapCount==0);
% Repeated local IDs in two source points/seeds remain distinct populations.
u2=editEvidence(ul,"PopulationIdentity.SweepPointIndex",2);
c2=editEvidence(control,"PopulationIdentity.SweepPointIndex",2);
u2=editEvidence(u2,"PopulationIdentity.RandomSeed",2);
c2=editEvidence(c2,"PopulationIdentity.RandomSeed",2);
[p,z,~,cohorts]=sixgr.report.collectSimultaneousULTransmitEvidence([ul;u2],[control;c2]);
assert(height(p)==2 && isequal(p.SweepPointIndex,[1;2]) && isequal(p.RandomSeed,[1;2]) && ...
    z.OutcomePairCount==2 && all(p.PUSCHTransmissionID=="PUSCH_tx") && ...
    z.CohortCount==2 && isnan(z.ConditionalSuccessRate) && isnan(z.OverlapRate) && ...
    height(cohorts)==2 && all(cohorts.ConditionalSuccessRate==1) && all(cohorts.OverlapRate==1));
% Missing/unsealed or transplanted identity is unavailable, never count zero.
bad=control; bad.TransmitOccupancyEvidenceJSON="";
[p,z]=sixgr.report.collectSimultaneousULTransmitEvidence(ul,bad);
assert(isempty(p) && ~z.CoverageComplete && isnan(z.ObservedOverlapCount));
bad=control; bad.TransmitOccupancyEvidenceSHA256="wrong";
[~,z]=sixgr.report.collectSimultaneousULTransmitEvidence(ul,bad);
assert(~z.CoverageComplete);
bad=control; bad.UEIndex=2;
[~,z]=sixgr.report.collectSimultaneousULTransmitEvidence(ul,bad);
assert(~z.CoverageComplete);
bad=control; bad.RunFolder="another_source";
[~,z]=sixgr.report.collectSimultaneousULTransmitEvidence(ul,bad);
assert(~z.CoverageComplete);
% Same UE, slot, and payload do not bind another receiver outcome.
bad=control; bad.TransmitOccupancyEvidenceJSON=second.TransmitOccupancyEvidenceJSON;
bad.TransmitOccupancyEvidenceSHA256=second.TransmitOccupancyEvidenceSHA256;
[p,z]=sixgr.report.collectSimultaneousULTransmitEvidence(ul,bad);
assert(isempty(p) && ~z.CoverageComplete && isnan(z.ConditionalSuccessRate));
for field=["TransmitOccupancyObservationID","TransmitOccupancyTransmissionID", ...
        "TransmitOccupancyTXEndpoint","TransmitOccupancyRXEndpoint","PhysicalPUCCHOccasionId"]
    bad=control; bad.(field)="another_observation";
    [~,z]=sixgr.report.collectSimultaneousULTransmitEvidence(ul,bad);
    assert(~z.CoverageComplete);
end
for field=["ObservationStartSample","ObservationEndSampleExclusive","ObservationSampleRateHz", ...
        "TransmitOccupancyClockEpoch","TransmitOccupancyCompletedAtSample"]
    bad=control; bad.(field)=bad.(field)+1;
    [~,z]=sixgr.report.collectSimultaneousULTransmitEvidence(ul,bad);
    assert(~z.CoverageComplete);
end
for field=["CompletedAtSample","ActiveSampleCount"]
    bad=editEvidence(control,field,0);
    [~,z]=sixgr.report.collectSimultaneousULTransmitEvidence(ul,bad);
    assert(~z.CoverageComplete);
end
[~,z]=sixgr.report.collectSimultaneousULTransmitEvidence(ul,[control;control]);
assert(~z.CoverageComplete && isnan(z.ObservedOverlapCount));
% Explicit receiver-only absence differs from missing producer metadata.
absent=bad; absent.TransmitOccupancyEvidenceJSON="";
absent.ReceiverOnlyAssignment=true; absent.PUCCHTransmissionPrepared=false;
[p,z]=sixgr.report.collectSimultaneousULTransmitEvidence(ul,absent);
assert(isempty(p) && z.CoverageComplete && z.ObservedOverlapCount==0 && ...
    z.ExcludedNoTransmissionRows==1 && isnan(z.ConditionalSuccessRate));
[p,z,emptyTrials,emptyCohorts]=sixgr.report.collectSimultaneousULTransmitEvidence(ul([],:),control([],:));
assert(isempty(p) && z.CoverageComplete && z.ObservedOverlapCount==0 && ...
    isnan(z.OverlapRate) && isnan(z.ConditionalSuccessRate) && ...
    z.Status=="not_exercised_no_qualified_transmission" && ...
    isstring(p.CohortKey) && isstring(emptyTrials.Channel) && isstring(emptyCohorts.CohortKey));
[p,z]=sixgr.report.collectSimultaneousULTransmitEvidence(table(),table());
assert(isempty(p) && ~z.CoverageComplete && isnan(z.ObservedOverlapCount));
% Capture uses exact nonzero mapped samples, including isolated tail values.
reference=jsondecode(control.TransmitOccupancyEvidenceJSON);
identity=reference.Identity;
samples=zeros(8,2); samples([2 3 7],2)=[1;1;realmin];
e=sixgr.truth.captureTransmitOccupancy(samples,100,10,identity);
assert(isequal(e.ActiveIntervals,[101 103;106 107]) && e.ActiveSampleCount==3 && ...
    e.InputSampleCount==8 && e.EmissionStatus=="prepared_not_emitted");
zero=sixgr.truth.captureTransmitOccupancy(zeros(8,2),100,10,identity);
assert(~zero.HasNonzeroSamples && zero.ActiveSampleCount==0 && isempty(zero.ActiveIntervals));
% Production completion relies on the composer forbidding replacement or
% cancellation after its first nonzero sample, not on a composite IQ hash.
composer=sixgr.phy.waveform.WaveformStreamComposer(10,1,0);
chunk=sixgr.phy.waveform.WaveformChunk([0;1;2;0],0);
composer.enqueue("committed",chunk,10); composer.readThrough(2);
mustReject(@()composer.cancelUnemittedComponent("committed"),'WAVEFORM:CannotCancelEmittedComponent');
mustReject(@()composer.replaceUnemittedComponent("committed",chunk),'WAVEFORM:CannotReplaceEmittedComponent');
tail=composer.readThrough(4); assert(isequal(real(tail.Samples),[2;0]));
ok=true;
fprintf('testSimultaneousULTransmitEvidence: PASS (declared receipt components, not physical execution)\n');
end

function T=fixture(channel,runs)
identity=struct('Channel',channel,'TransmissionID',channel+"_tx", ...
    'ObservationID',channel+"_rx",'UEIndex',1,'RNTI',1,'ServingCell',1, ...
    'TransmitterID',"ue_1",'ClockDomain',"shared_physical_sample_clock/v1",'ClockEpoch',1);
x=zeros(100,2);
for k=1:size(runs,1), x(runs(k,1)+1:runs(k,2),1)=1; end
e=sixgr.truth.captureTransmitOccupancy(x,0,1000,identity);
e.EmissionStatus="completed_nonzero_contribution";
e.CommittedAtSample=runs(1,1)+1; e.CompletedAtSample=120;
e.PopulationIdentity=struct('RunFolder',"declared_component_run",'ExecutionID',"", ...
    'ConfigHash',"declared_config",'RunID',"test",'ScenarioID',"component", ...
    'RandomSeed',1,'ChannelSeed',1,'SweepPointIndex',1,'ConfiguredSNR_dB',20, ...
    'BoundAtSample',e.CommittedAtSample,'Source',"actual_first_active_sample_commit_runtime_context");
sourceField="FrozenGrantContextId";
if channel=="PUCCH", sourceField="PhysicalPUCCHOccasionId"; end
e.ReceiverBinding=struct('ObservationID',identity.ObservationID, ...
    'ReceiverID',"gnb_1_rx:post_rf",'StartSample',0,'EndSampleExclusive',120, ...
    'SampleRateHz',1000,'CompletedAtSample',120, ...
    'SourceRowIdentityField',sourceField,'SourceRowIdentity',channel+"_receiver_grant");
T=struct2table(struct('UEIndex',1,'RNTI',1,'BaseStationID',1,'Frame',1,'Slot',1, ...
    'RXStartSample',0,'RXEndSampleExclusive',120,'Status',"PASS",'Crash',false, ...
    'CRCPass',1,'ExpectedBitCount',7,'PUCCHTransmissionPrepared',true, ...
    'ReceiverOnlyAssignment',false,'UCIContentMatch',true,'DTXFlag',false, ...
    'DetectionUsable',true,'DetectionAttempted',true, ...
    'TransmitOccupancyEvidenceJSON',string(jsonencode(e)), ...
    'TransmitOccupancyEvidenceSHA256',sixgr.util.sha256Hex(jsonencode(e))), 'AsArray',true);
T=stampBinding(T,e);
end

function T=editEvidence(T,path,value)
e=jsondecode(T.TransmitOccupancyEvidenceJSON);
e=sixgr.util.structSet(e,path,value);
e.ReceiverBinding.ObservationID=e.Identity.ObservationID;
e.ReceiverBinding.ReceiverID="gnb_"+e.Identity.ServingCell+"_rx:post_rf";
e.ReceiverBinding.SampleRateHz=e.SampleRateHz;
e.ReceiverBinding.CompletedAtSample=e.CompletedAtSample;
T.TransmitOccupancyEvidenceJSON=string(jsonencode(e));
T.TransmitOccupancyEvidenceSHA256=sixgr.util.sha256Hex(T.TransmitOccupancyEvidenceJSON);
T=stampBinding(T,e);
end

function T=stampBinding(T,e)
b=e.ReceiverBinding; id=e.Identity;
T.(b.SourceRowIdentityField)=string(b.SourceRowIdentity);
T.TransmitOccupancyObservationID=string(id.ObservationID);
T.TransmitOccupancyTransmissionID=string(id.TransmissionID);
T.TransmitOccupancyTXEndpoint=string(id.TransmitterID)+":tx";
T.TransmitOccupancyRXEndpoint=string(b.ReceiverID);
T.TransmitOccupancyClockDomain=string(id.ClockDomain);
T.TransmitOccupancyClockEpoch=id.ClockEpoch;
T.TransmitOccupancyStartSample=e.StartSample;
T.TransmitOccupancyEndSampleExclusive=e.EndSampleExclusive;
T.TransmitOccupancySampleRateHz=e.SampleRateHz;
T.TransmitOccupancyRXStartSample=b.StartSample;
T.TransmitOccupancyRXEndSampleExclusive=b.EndSampleExclusive;
T.TransmitOccupancyRXSampleRateHz=b.SampleRateHz;
T.TransmitOccupancyCompletedAtSample=b.CompletedAtSample;
T.ObservationStartSample=b.StartSample;
T.ObservationEndSampleExclusive=b.EndSampleExclusive;
T.ObservationSampleRateHz=b.SampleRateHz;
end

function mustReject(action,identifier)
try, action(); catch cause
    assert(strcmp(cause.identifier,identifier),'Unexpected exception: %s',cause.identifier); return;
end
error('test:ExpectedFailure','Expected %s.',identifier);
end
