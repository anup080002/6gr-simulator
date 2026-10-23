function expanded=expandExecutedSampleIntervals(T,cfg)
% Reporting-only native sample intervals. Never call a PRACH native symbol a
% carrier OFDM symbol or widen it to the receiver's whole capture window.
expanded=T;
if isempty(T) || ~ismember('ExecutedSampleIntervalsJSON',T.Properties.VariableNames), return; end
pieces=cell(height(T),1);
for i=1:height(T)
    row=T(i,:); raw=string(row.ExecutedSampleIntervalsJSON);
    if ismissing(raw) || strlength(strtrim(raw))==0
        pieces{i}=row; continue;
    end
    assert(all(ismember({'ExecutedSampleIntervalSource','ResourceGridPRBCount'},T.Properties.VariableNames)) && ...
        any(string(row.ExecutedSampleIntervalSource)==[ ...
        "executed_native_PRACH_CP_useful_samples_not_RF_activity", ...
        "executed_native_SSB_CP_useful_samples_not_RF_activity"]) && ...
        row.ResourceGridPRBCount==cfg.phy.carrier.NSizeGrid, ...
        'sixgr:truth:SampleIntervalAuthority','Native sample interval authority is missing or inconsistent.');
    intervals=jsondecode(raw);
    assert(isstruct(intervals) && ~isempty(intervals) && all(isfield(intervals, ...
        {'StartSample','EndSampleExclusive','SampleRateHz','NativeSymbolIndex0','CarrierPRBIntersectionSet0Based'})), ...
        'sixgr:truth:SampleIntervalSchema','Invalid native sample interval schema.');
    parts=cell(numel(intervals),1); previousEnd=-Inf; sampleRate=NaN;
    for k=1:numel(intervals)
        r=intervals(k);
        validateattributes([r.StartSample r.EndSampleExclusive r.SampleRateHz r.NativeSymbolIndex0], ...
            {'numeric'},{'vector','finite','integer','nonnegative'});
        assert(r.SampleRateHz>0 && r.EndSampleExclusive>r.StartSample && r.StartSample>=previousEnd && ...
            (isnan(sampleRate)||sampleRate==r.SampleRateHz), ...
            'sixgr:truth:SampleIntervalClock','Native sample intervals must be ordered, disjoint and same-clock.');
        prbs=reshape(double(r.CarrierPRBIntersectionSet0Based),1,[]);
        validateattributes(prbs,{'numeric'},{'vector','nonempty','finite','integer','nonnegative','<',cfg.phy.carrier.NSizeGrid});
        assert(isequal(prbs,unique(prbs,'sorted')),'sixgr:truth:SampleIntervalPRBs','PRB intersections must be canonical.');
        part=row;
        part.EnergyIntervalStartSample=r.StartSample;
        part.EnergyIntervalEndSampleExclusive=r.EndSampleExclusive;
        part.EnergyIntervalSampleRateHz=r.SampleRateHz;
        part.EnergyNativeSymbolIndex0=r.NativeSymbolIndex0;
        part.EnergyAllocatedPRBSetJSON=string(jsonencode(prbs));
        part.PRBs=numel(prbs);
        parts{k}=part; previousEnd=r.EndSampleExclusive; sampleRate=r.SampleRateHz;
    end
    pieces{i}=vertcat(parts{:});
end
names={'EnergyIntervalStartSample','EnergyIntervalEndSampleExclusive', ...
    'EnergyIntervalSampleRateHz','EnergyNativeSymbolIndex0','EnergyAllocatedPRBSetJSON','PRBs'};
for i=1:numel(pieces)
    for name=string(names)
        if ismember(name,pieces{i}.Properties.VariableNames), continue; end
        value=NaN; if name=="EnergyAllocatedPRBSetJSON", value=""; end
        pieces{i}.(name)=repmat(value,height(pieces{i}),1);
    end
    pieces{i}=pieces{i}(:,[T.Properties.VariableNames setdiff(names,T.Properties.VariableNames,'stable')]);
end
expanded=vertcat(pieces{:});
end
