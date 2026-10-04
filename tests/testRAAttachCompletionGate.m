function ok=testRAAttachCompletionGate()
% Declared completion metadata tests, not fabricated physical access rows.
r=struct('RACompleted',true,'StrictOk',true,'RequireRRCSetupComplete',true, ...
    'Msg4ScheduledSlot',17,'SetupCompleteScheduledSlot',19, ...
    'RRCSetupCompleteCRC',true,'RRCSetupCompleteDecoded',true,'RRCConnected',true);
cfg=sixgr.config.defaultConfig();
fs=30.72e6; samplesPerSlot=fs*sixgr.time.slotDurationSec(cfg);
StageName=["Msg4";"RRCSetupComplete"]; StageSlot=[17;19];
ObservationStartSample=StageSlot*samplesPerSlot;
ObservationEndSampleExclusive=(StageSlot+1)*samplesPerSlot;
ObservationSampleRateHz=repmat(fs,2,1);
ObservationCompletionTime_s=ObservationEndSampleExclusive/fs;
ObservationCoverageSource=repmat("complete_contiguous_received_sample_buffer",2,1);
r.RuntimeStageRows=table(StageName,StageSlot,ObservationStartSample,ObservationEndSampleExclusive, ...
    ObservationSampleRateHz,ObservationCompletionTime_s,ObservationCoverageSource);
[slot0,count]=sixgr.truth.resolveRAAttachCompletion(r,cfg);
assert(slot0==19 && count==20);
campaignRows=(1:22).';
ready=campaignRows>count;
sixgr.truth.requirePostAttachWindow(numel(campaignRows),count);
localReject(@()sixgr.truth.requirePostAttachWindow(count,count), ...
    'sixgr:e2e:InsufficientPostAttachWindow');
localReject(@()sixgr.truth.requirePostAttachWindow(count-1,count), ...
    'sixgr:e2e:InsufficientPostAttachWindow');
assert(~any(ready(1:20)) && all(ready(21:22)), ...
    'Neither Msg4 nor the still-executing SetupComplete slot may release traffic.');
r.RequireRRCSetupComplete=false;
[slot0,count]=sixgr.truth.resolveRAAttachCompletion(r,cfg);
assert(slot0==17 && count==18);
r.RequireRRCSetupComplete=true;
tail=r; tail.RuntimeStageRows.ObservationEndSampleExclusive(2)=20*samplesPerSlot+7;
tail.RuntimeStageRows.ObservationCompletionTime_s(2)= ...
    tail.RuntimeStageRows.ObservationEndSampleExclusive(2)/fs;
[slot0,count]=sixgr.truth.resolveRAAttachCompletion(tail,cfg);
assert(slot0==19 && count==21,'A real receive tail must delay scheduling beyond the nominal final slot.');
bad=rmfield(r,'RuntimeStageRows');
localReject(@()sixgr.truth.resolveRAAttachCompletion(bad,cfg),'sixgr:truth:MissingRAReceiveCompletion');
bad=r; bad.RuntimeStageRows.ObservationSampleRateHz(2)=NaN;
localReject(@()sixgr.truth.resolveRAAttachCompletion(bad,cfg),'sixgr:truth:RAReceiveCompletionClockMismatch');
bad=r; bad.RuntimeStageRows.ObservationCompletionTime_s(2)=0;
localReject(@()sixgr.truth.resolveRAAttachCompletion(bad,cfg),'sixgr:truth:RAReceiveCompletionClockMismatch');
for name={'RRCSetupCompleteCRC','RRCSetupCompleteDecoded','RRCConnected'}
    bad=r; bad.(name{1})=false;
    localReject(@()sixgr.truth.resolveRAAttachCompletion(bad), ...
        'sixgr:truth:IncompleteRRCSetupComplete');
end
for value=[NaN,Inf,-1,18.5,16]
    bad=r; bad.SetupCompleteScheduledSlot=value;
    localReject(@()sixgr.truth.resolveRAAttachCompletion(bad), ...
        'sixgr:truth:RACompletionClockMismatch');
end
bad=rmfield(r,'SetupCompleteScheduledSlot');
localReject(@()sixgr.truth.resolveRAAttachCompletion(bad), ...
    'sixgr:truth:IncompleteRRCSetupComplete');
for name={'RACompleted','StrictOk'}
    bad=r; bad.(name{1})=false;
    localReject(@()sixgr.truth.resolveRAAttachCompletion(bad), ...
        'sixgr:truth:IncompleteRAAttach');
end
ok=true;
end

function localReject(call,id)
try, call(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('TEST:MissingRejection','Expected %s.',id);
end
