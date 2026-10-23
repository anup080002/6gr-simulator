function [T,audit]=bindPRACHNativeResourcesToTrials(T,cfg,N,configHash,sourceHash)
% Reporting copies only; the caller hash-verifies the native ledger file.
required={'ConfigHash','carrier_origin_slot0','cell_id','ue_id','ra_attempt_id','ra_stage','allocation_id'};
assert(all(ismember(required,N.Properties.VariableNames)) && ...
    all(string(N.ConfigHash)==string(configHash)) && ...
    ~isempty(regexp(char(sourceHash),'^[a-f0-9]{64}$','once')), ...
    'sixgr:truth:PRACHBindingAuthority','Native ledger needs matching config and source identity.');
defaults=sixgr.truth.prachNativeSampleIntervals();
for name=string(fieldnames(defaults)).'
    if ~ismember(name,T.Properties.VariableNames), T.(name)=repmat(defaults.(name),height(T),1); end
end
prototype=struct('TrialRow',NaN,'NativeRows',0,'AllocationID',"",'Status',"no_exact_native_identity",'SourceSHA256',sourceHash);
rows=repmat(prototype,height(T),1);
for i=1:height(T)
    rows(i).TrialRow=i;
    assert(ismember('ConfigHash',T.Properties.VariableNames) && string(T.ConfigHash(i))==string(configHash), ...
        'sixgr:truth:PRACHBindingScope','Receiver and native grid configurations differ.');
    needed={'RACellId','RAUEId','RAAttemptId','Msg1ScheduledSlot','RASlotTimeBase'};
    if ~all(ismember(needed,T.Properties.VariableNames)) || string(T.RASlotTimeBase(i))~="absolute_zero_based", continue; end
    selected=N.cell_id==T.RACellId(i) & N.ue_id==T.RAUEId(i) & ...
        N.ra_attempt_id==T.RAAttemptId(i) & N.carrier_origin_slot0==T.Msg1ScheduledSlot(i) & string(N.ra_stage)=="Msg1";
    if ~any(selected), continue; end
    if numel(unique(string(N.allocation_id(selected))))~=1
        rows(i).Status="ambiguous_native_PRACH_identity"; continue;
    end
    e=sixgr.truth.prachNativeSampleIntervals(N(selected,:),cfg.phy.carrier);
    previous=string(T.ExecutedSampleIntervalsJSON(i));
    if ~ismissing(previous) && strlength(strtrim(previous))>0
        assert(isequaln(jsondecode(previous),jsondecode(e.ExecutedSampleIntervalsJSON)), ...
            'sixgr:truth:PRACHBindingConflict','Producer and retained native intervals disagree.');
    end
    for name=string(fieldnames(e)).', T.(name)(i)=e.(name); end
    rows(i).NativeRows=nnz(selected); rows(i).AllocationID=e.NativeAllocationID;
    rows(i).Status="bound_exact_native_PRACH_identity";
end
audit=struct2table(rows);
end
