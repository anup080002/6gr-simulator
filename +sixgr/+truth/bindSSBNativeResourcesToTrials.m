function [T,audit]=bindSSBNativeResourcesToTrials(T,cfg,N,configHash,sourceHash)
% Bind the monitored beam in the exact committed broadcast capture, even
% after CRC failure. No nearest-slot matching or decoded-identity fallback.
required={'ConfigHash','cell_id','allocation_id','ssb_index0', ...
    'broadcast_start_sample','broadcast_end_sample_exclusive','observation_sample_rate_hz'};
assert(all(ismember(required,N.Properties.VariableNames)) && ...
    all(string(N.ConfigHash)==string(configHash)) && ...
    ~isempty(regexp(char(sourceHash),'^[a-f0-9]{64}$','once')), ...
    'sixgr:truth:SSBBindingAuthority','Native ledger needs matching configuration and source identity.');
defaults=sixgr.truth.ssbNativeSampleIntervals();
for name=string(fieldnames(defaults)).'
    if ~ismember(name,T.Properties.VariableNames), T.(name)=repmat(defaults.(name),height(T),1); end
end
prototype=struct('TrialRow',NaN,'NativeRows',0,'AllocationID',"", ...
    'Status',"no_exact_native_SSB_identity",'SourceSHA256',sourceHash);
rows=repmat(prototype,height(T),1);
for i=1:height(T)
    rows(i).TrialRow=i;
    assert(ismember('ConfigHash',T.Properties.VariableNames) && string(T.ConfigHash(i))==string(configHash), ...
        'sixgr:truth:SSBBindingScope','Receiver and native SSB configurations differ.');
    needed={'CellID','RequestedSSBOccasionIndex','ObservationStartSample', ...
        'ObservationEndSampleExclusive','ObservationSampleRateHz'};
    if ~all(ismember(needed,T.Properties.VariableNames)), continue; end
    selected=N.cell_id==T.CellID(i) & N.ssb_index0==T.RequestedSSBOccasionIndex(i) & ...
        N.broadcast_start_sample==T.ObservationStartSample(i) & ...
        N.broadcast_end_sample_exclusive==T.ObservationEndSampleExclusive(i) & ...
        N.observation_sample_rate_hz==T.ObservationSampleRateHz(i);
    if ~any(selected), continue; end
    if numel(unique(string(N.allocation_id(selected))))~=1
        rows(i).Status="ambiguous_native_SSB_identity"; continue;
    end
    for field=["RunID","ExecutionID","ScenarioID","SweepPointIndex","SweepRealizationIndex", ...
            "ConfiguredSNR_dB","Seed","TrialIndex"]
        if ~ismember(field,N.Properties.VariableNames) || ~ismember(field,T.Properties.VariableNames), continue; end
        value=string(T.(field)(i)); actual=string(N.(field)(selected));
        known=~ismissing(actual)&strlength(strtrim(actual))>0;
        if ~ismissing(value) && strlength(strtrim(value))>0
            assert(all(actual(known)==value),'sixgr:truth:SSBBindingPopulation', ...
                'Native SSB and receiver populations differ: %s.',field);
        end
    end
    e=sixgr.truth.ssbNativeSampleIntervals(N(selected,:),cfg.phy.carrier);
    previous=string(T.ExecutedSampleIntervalsJSON(i));
    if ~ismissing(previous) && strlength(strtrim(previous))>0
        assert(isequaln(jsondecode(previous),jsondecode(e.ExecutedSampleIntervalsJSON)), ...
            'sixgr:truth:SSBBindingConflict','Producer and retained native SSB intervals disagree.');
    end
    for name=string(fieldnames(e)).', T.(name)(i)=e.(name); end
    rows(i).NativeRows=nnz(selected); rows(i).AllocationID=e.NativeAllocationID;
    rows(i).Status="bound_exact_native_SSB_capture_and_monitored_beam";
end
audit=struct2table(rows);
end
