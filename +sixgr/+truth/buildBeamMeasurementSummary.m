function T=buildBeamMeasurementSummary(sourceT,direction,traceSource,specs,selectedSSB)
% Summarize exported observations without converting metadata into measurements.
if nargin<5, selectedSSB=false; end
T=table();
if ~istable(sourceT)||isempty(sourceT), return; end
vars=string(sourceT.Properties.VariableNames);
proxyName=findName(vars,"ProxyUsed");
if proxyName~=""
    proxy=numeric(sourceT,proxyName);
    assert(~any(proxy==1),'sixgr:truth:ProxyBeamSummaryInput', ...
        'Proxy beam rows cannot enter primary measured beam summaries.');
end
% Keep scenario identity and receiver/burst scopes, including missing identity
% as missing. Never infer a UE, carrier, BWP, or burst from a row number.
scope=["RunID","ExecutionID","UEIndex","ServingCell","ComponentCarrier", ...
    "BWPId","BurstID","Frame","Slot","PowerReferencePlane"];
aliases={"RunID","ExecutionID",["UEIndex","UEID"], ...
    ["ServingCell","CellID","BaseStationID"], ...
    ["ComponentCarrier","ComponentCarrierId"],["BWPId","ActiveBWP","BWPID"], ...
    ["BurstID","SSBBurstID"],"Frame","Slot","PowerReferencePlane"};
scopeValues=cell(size(scope));
for j=1:numel(scope)
    name=findName(vars,aliases{j});
    if name=="", scopeValues{j}=repmat(missing,height(sourceT),1);
    else, scopeValues{j}=sourceT.(name); end
    if ismember(scope(j),["RunID","ExecutionID","BurstID","PowerReferencePlane"])
        values=scopeValues{j}; absent=ismissing(values);
        values=string(values); values(absent)=missing; scopeValues{j}=values;
    end
end
directions=repmat(string(direction),height(sourceT),1);
name=findName(vars,"Direction");
if name~="", directions=string(sourceT.(name)); end
directions(ismissing(directions)|strlength(directions)==0)="BEAM";
snrName=findName(vars,["ConfiguredSNR_dB","SNR_dB"]);
snr=nan(height(sourceT),1); snrRole="operating_point_unavailable";
if snrName~=""
    snr=numeric(sourceT,snrName);
    snrRole="source_defined_snr_axis";
    if strcmpi(snrName,"ConfiguredSNR_dB"), snrRole="configured_operating_point_metadata"; end
end
keys=strings(height(sourceT),1);
for r=1:height(sourceT)
    identity=cell(1,numel(scope)+2);
    identity{1}=char(directions(r)); identity{2}=snr(r);
    for j=1:numel(scope), identity{j+2}=scopeValues{j}(r,:); end
    keys(r)=string(jsonencode(identity));
end
groups=unique(keys,'stable'); rows=struct([]);
for g=1:numel(groups)
    mask=keys==groups(g); indices=find(mask); first=indices(1);
    sample=sourceT(mask,:);
    base=struct('Direction',directions(first),'TraceSource',string(traceSource), ...
        'SNR_dB',snr(first),'SNR_dBValueRole',snrRole,'AggregationAxis',snrName, ...
        'Metric',"",'MeanValue',NaN,'P05Value',NaN,'P95Value',NaN,'SampleCount',0);
    for j=1:numel(scope), base.(scope(j))=scopeValues{j}(first,:); end
    present=scope(cellfun(@(v)~all(ismissing(v),'all'),scopeValues));
    base.IdentityScope=strjoin(present,'|');
    base=quality(base,sample);
    base.SelectionPolicy=""; base.SelectionEvidenceRole=""; base.ScoreAxis="";
    base.BeamIndexConvention=""; base.TieCount=NaN; base.TiePolicy="";
    base.ObservedCandidateRowCount=NaN; base.UnscoredCandidateCount=NaN;
    if selectedSSB
        % This is a measured strongest-SS-RSRP comparison, not evidence that
        % the access receiver selected/decoded this candidate. Do not compare
        % RSRP and correlation metrics or use an internal one-based beam ID.
        scoreAxis="SS_RSRP_dBm";
        if string(base.PowerReferencePlane)=="normalized_fixed_esn0_unit_occupied_re_es"
            scoreAxis="SS_RSRP_dB_re_UnitOccupiedRE_Es";
        end
        if findName(vars,"SSBIndex")=="" || findName(vars,scoreAxis)=="", continue; end
        beams=numeric(sample,findName(vars,"SSBIndex"));
        score=numeric(sample,findName(vars,scoreAxis));
        assert(~any(isfinite(beams)&(beams<0|beams~=fix(beams))), ...
            'sixgr:truth:InvalidPhysicalSSBIndex','SSBIndex must be a nonnegative integer.');
        valid=isfinite(score)&isfinite(beams);
        if ~any(valid), continue; end
        candidates=find(valid); [best,k]=max(score(valid)); winner=candidates(k);
        chosen=quality(base,sample(winner,:));
        chosen.SelectionPolicy="maximum_observed_SS_RSRP";
        chosen.SelectionEvidenceRole="posthoc_measured_candidate_comparison_not_receiver_decision";
        chosen.ScoreAxis=scoreAxis;
        chosen.BeamIndexConvention="physical_SSB_index_zero_based";
        chosen.TieCount=nnz(score(valid)==best);
        chosen.TiePolicy="first_source_row_among_equal_scores";
        chosen.ObservedCandidateRowCount=height(sample);
        chosen.UnscoredCandidateCount=nnz(isfinite(beams)&~isfinite(score));
        selectedMetrics=["P1SelectedSSBBeamIndex","P1SelectedSSBBeamScore","P1SSBSweptBeamCount"];
        values=[beams(winner),best,numel(unique(beams(isfinite(beams))))];
        for j=1:numel(values)
            row=chosen; row.Metric=selectedMetrics(j);
            row.MeanValue=values(j); row.P05Value=values(j); row.P95Value=values(j); row.SampleCount=1;
            rows=append(rows,row);
        end
    else
        for j=1:numel(specs)
            name=findName(vars,specs(j).Columns);
            if name=="", continue; end
            values=numeric(sample,name); values=values(isfinite(values));
            if isempty(values), continue; end
            row=base; row.Metric=string(specs(j).Metric);
            row.MeanValue=mean(values); row.P05Value=prctile(values,5);
            row.P95Value=prctile(values,95); row.SampleCount=numel(values);
            rows=append(rows,row);
        end
    end
end
if ~isempty(rows), T=struct2table(rows,'AsArray',true); end
end

function row=quality(row,T)
row.QualityAxis="unavailable_measured_quality";
row.QualityValueRole="receiver_quality_unavailable"; row.QualitySource="";
row.QualityMean_dB=NaN; row.QualityP05_dB=NaN; row.QualityP95_dB=NaN; row.QualitySampleCount=0;
vars=string(T.Properties.VariableNames);
for candidate=["PostEqSINR_dB","MeasuredWidebandSINR_dB","MeasuredTrialSINR_dB","SINR_dB"]
    name=findName(vars,candidate); if name=="", continue; end
    values=numeric(T,name); valid=isfinite(values); if ~any(valid), continue; end
    prefix=erase(candidate,"_dB");
    sourceName=findName(vars,prefix+"Source");
    roleName=findName(vars,prefix+"ValueRole");
    role="source_defined_quality_role_unavailable"; source=name;
    if roleName~="", role=joinLabels(string(T.(roleName)(valid)),role); end
    if sourceName~="", source=joinLabels(string(T.(sourceName)(valid)),source); end
    row.QualityAxis=name; row.QualityValueRole=role; row.QualitySource=source;
    values=values(valid); row.QualityMean_dB=mean(values);
    row.QualityP05_dB=prctile(values,5); row.QualityP95_dB=prctile(values,95);
    row.QualitySampleCount=numel(values);
    return;
end
end

function out=joinLabels(labels,absent)
labels=unique(labels(~ismissing(labels)&strlength(strtrim(labels))>0),'stable');
if isempty(labels), out=absent;
elseif numel(labels)==1, out=labels(1);
else, out="mixed_source_labels:"+strjoin(labels,'|'); end
end

function name=findName(vars,candidates)
name="";
for candidate=string(candidates)
    idx=find(strcmpi(vars,candidate),1);
    if ~isempty(idx), name=vars(idx); return; end
end
end

function values=numeric(T,name)
raw=T.(name);
if isnumeric(raw)||islogical(raw), values=double(raw);
else
    tokens=lower(strtrim(string(raw))); values=str2double(tokens);
    values(ismember(tokens,["true","yes","pass","ok"]))=1;
    values(ismember(tokens,["false","no","fail"]))=0;
end
assert(iscolumn(values),'sixgr:truth:InvalidBeamSummaryColumn', ...
    'Beam summary requires one scalar per row in %s.',name);
end

function rows=append(rows,row)
if isempty(rows), rows=row; else, rows(end+1,1)=row; end
end
