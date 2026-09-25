function out=buildPAPRCCDFTable(rawTrials)
%BUILDPAPRCCDFTABLE Descriptive CCDFs of actual PAPR rows, never pooled SNRs.
% Correlated HARQ/slot observations are not independent Monte Carlo trials.
out=table(); chunks={};
if ~isstruct(rawTrials), return; end
for direction=["DL","UL"]
    if ~isfield(rawTrials,direction), continue; end
    T=rawTrials.(direction);
    if isstruct(T) && ~isempty(T), T=struct2table(T); end
    if ~istable(T)||isempty(T)||~ismember('PAPR_dB',T.Properties.VariableNames), continue; end
    if ismember('Direction',T.Properties.VariableNames)
        assert(all(upper(string(T.Direction))==direction), ...
            'sixgr:report:PAPRDirectionMismatch','PAPR source direction disagrees with its table.');
    end
    fields=["ConfiguredSNR_dB","EffectiveModulation","EffectiveLayers", ...
        "MCSIndex","TransformPrecodingApplied","ConfigHash"];
    aliases=["SNR_dB","Modulation","Layers","MCS","TransformPrecodingApplied","ConfigHash"];
    displayNames=["SNR","mod","layers","MCS","DFTs","cfg"];
    keys=strings(height(T),1); labels=keys; metadata=cell(height(T),1);
    for row=1:height(T)
        identity=struct('Direction',direction);
        label=direction;
        for f=1:numel(fields)
            name=fields(f);
            if ~ismember(name,string(T.Properties.VariableNames)), name=aliases(f); end
            if ismember(name,string(T.Properties.VariableNames))
                value=T.(name)(row,:);
                if iscell(value), value=value{1}; end
                identity.(fields(f))=value;
                text=join(string(value),"|");
                if fields(f)=="ConfigHash", text=extractBefore(text,min(strlength(text)+1,9)); end
                label=label+" "+displayNames(f)+"="+text;
            end
        end
        if ismember('PAPRMeasurementJSON',T.Properties.VariableNames)
            raw=string(T.PAPRMeasurementJSON(row));
            if ~ismissing(raw) && strlength(raw)>0
                identity.MeasurementContext=localMeasurementContext(raw);
                label=label+" plane="+string(identity.MeasurementContext.MeasurementPoint)+ ...
                    " window="+string(identity.MeasurementContext.ReferenceDomain);
            end
        end
        metadata{row}=identity;
        keys(row)=string(jsonencode(identity)); labels(row)=label;
    end
    populations=unique(keys,'stable');
    for p=1:numel(populations)
        population=keys==populations(p);
        values=double(T.PAPR_dB(population));
        samples=values(isfinite(values));
        if isempty(samples), continue; end
        thresholds=unique(samples); % Exact observed thresholds, including ties.
        count=arrayfun(@(x)sum(samples>x),thresholds);
        first=find(population,1); identity=metadata{first};
        snr=NaN;
        if isfield(identity,'ConfiguredSNR_dB')
            snr=double(identity.ConfiguredSNR_dB);
        end
        n=numel(thresholds);
        populationID=direction+":"+string(sixgr.util.sha256Hex( ...
            unicode2native(char(populations(p)),'UTF-8')));
        chunks{end+1}=table(repmat(direction,n,1),repmat(snr,n,1), ...
            repmat(populationID,n,1),repmat(labels(first),n,1), ...
            repmat(populations(p),n,1),thresholds,count,repmat(numel(samples),n,1), ...
            count/numel(samples),repmat(sum(~isfinite(values)),n,1), ...
            repmat(">",n,1),repmat("empirical_observations_no_independence_claim",n,1), ...
            'VariableNames',{'Direction','ConfiguredSNR_dB','PopulationID','Series', ...
            'PopulationContextJSON','PAPR_dB','Exceedances','SampleCount','CCDF', ...
            'UnavailableSampleCount','ThresholdComparator','StatisticalScope'}); %#ok<AGROW>
    end
end
if ~isempty(chunks), out=vertcat(chunks{:}); end
end

function context=localMeasurementContext(raw)
% Population identity excludes measured powers, but includes window/plane.
evidence=jsondecode(raw);
names={'ContractVersion','Source','MeasurementPoint','ReferenceDomain', ...
    'InputWaveformSampleCount','AggregateRule'};
portNames={'PortIndex','OversamplingFactor','MeasuredSampleCount', ...
    'InputSampleCount','OversamplingDefinition'};
assert(isstruct(evidence)&&isscalar(evidence)&&all(isfield(evidence,names))&& ...
    isfield(evidence,'PerPort')&&isstruct(evidence.PerPort)&&~isempty(evidence.PerPort)&& ...
    all(isfield(evidence.PerPort,portNames)), ...
    'sixgr:report:PAPRMeasurementContext','Incomplete PAPR measurement context.');
context=struct();
for f=1:numel(names), context.(names{f})=evidence.(names{f}); end
for p=1:numel(evidence.PerPort)
    for f=1:numel(portNames)
        context.PerPort(p).(portNames{f})=evidence.PerPort(p).(portNames{f});
    end
end
end
