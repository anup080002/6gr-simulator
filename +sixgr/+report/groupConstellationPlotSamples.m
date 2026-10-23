function [groups,summary,diagnostics] = groupConstellationPlotSamples(T)
% Exact supplied population/plane/scope; no inferred historical identities.
groups={}; summary=table(); diagnostics=table();
required=["direction","modulation","layer","snr_db","mcs_index", ...
    "reference_symbol_i","reference_symbol_q","equalized_i","equalized_q","truth_status"];
if ~istable(T) || isempty(T) || ~all(ismember(required,string(T.Properties.VariableNames)))
    return;
end
names=string(T.Properties.VariableNames);
rawFields=["RawEqualizedReal","RawEqualizedImag"];
rawDeclared=any(ismember(rawFields,names));
if rawDeclared
    realField=rawFields(1); imagField=rawFields(2);
    plane="retained_raw_equalized_receiver_symbols_no_fitted_substitution";
else
    realField="equalized_i"; imagField="equalized_q";
    plane="legacy_canonical_equalized_symbols_source_declared_plane_not_verified_raw";
end
receiverOK=localFinite(T,realField) & localFinite(T,imagField);
referenceOK=localFinite(T,"reference_symbol_i") & localFinite(T,"reference_symbol_q");
eligible=ismember(lower(strtrim(string(T.truth_status))), ...
    ["real_lls_evidence","truth","runtime_measured"]) & ...
    ismember(upper(strtrim(string(T.direction))),["DL","UL"]);
valid=eligible & receiverOK & referenceOK;
% Unknown metadata must not erase valid pairs. TB/slot/observation/native
% position IDs stay unchanged in G, not panel keys.
optional=["ue_id","UEIndex","UEID","RNTI","BaseStationID","ServingCell", ...
    "SourceRunID","RunID","RunUUID","ExecutionID","ConfigHash","ScenarioID","RunTag","RunFolder", ...
    "SweepPointIndex","SweepPointLabel","ConfiguredSNR_dB","Seed","RandomSeed","ChannelSeed", ...
    "SourceRandomSeed","SourceChannelSeed","PreparedRandomSeed","PreparedChannelSeed", ...
    "DropIndex","RealizationIndex","SweepAggregatePointIndex","SweepAggregateLabel", ...
    "SweepAggregateConfiguredSNR_dB","SweepAggregateSourceCSV","SweepAggregatePointStatus", ...
    "SourceArtifact","SourceTable","SourceCSV","normalization","Normalization","RuntimeNormalization", ...
    "EqualizationSource","SymbolComparisonDomain","SymbolOrdering","SymbolOrderingStatus", ...
    "SymbolCoordinateDomain","SymbolOrderLinearIndexDomain","CodewordIndex","CaptureScope"];
fields=["direction","modulation","layer","snr_db","mcs_index",optional(ismember(optional,names))];
key=repmat("constellation_cohort/v2",height(T),1);
for field=fields
    key=key+localFrame(field)+localFrame(string(class(T.(field))))+localFrame(localTokens(T.(field),height(T)));
end
key=key+localFrame("PlottedIQSource")+localFrame(plane);
keys=unique(key,'stable');
for k=1:numel(keys)
    selected=key==keys(k); first=find(selected,1); accepted=selected & valid;
    count=nnz(accepted); sourceCount=nnz(selected);
    invalidReceiver=nnz(selected & eligible & ~receiverOK);
    invalidReference=nnz(selected & eligible & ~referenceOK);
    excludedAuthority=nnz(selected & ~eligible);
    reason="";
    if rawDeclared && ~all(ismember(rawFields,names))
        reason="missing_raw_receiver_component_no_fitted_substitution";
    elseif invalidReceiver>0
        reason="nonfinite_receiver_pair_no_fitted_substitution";
    end
    if invalidReference>0, reason=localReason(reason,"nonfinite_reference_pair"); end
    if excludedAuthority>0, reason=localReason(reason,"excluded_truth_or_direction"); end
    status="all_source_rows_plotted_not_full_capture_qualification";
    if count==0, status="unavailable_no_finite_authorized_pairs";
    elseif count<sourceCount, status="partial_source_population_plotted"; end
    label=localLabel(T,first,fields);
    captureScope=localText(T,first,"CaptureScope","not_retained");
    coordinateDomain=localText(T,first,"SymbolCoordinateDomain","not_retained");
    d=table(keys(k),label,plane,realField,imagField,captureScope,coordinateDomain, ...
        sourceCount,count,sourceCount-count,excludedAuthority,invalidReceiver,invalidReference,status,reason, ...
        'VariableNames',{'GroupIdentity','GroupLabel','PlottedIQSource','PlottedRealColumn','PlottedImagColumn', ...
        'CaptureScope','SymbolCoordinateDomain','SourceRowCount','PlottedSampleCount','RejectedSampleCount', ...
        'ExcludedAuthorityRowCount','InvalidReceiverPairCount','InvalidReferencePairCount','PopulationStatus','RejectionReason'});
    % Preserve supplied metadata types separately from display labels.
    for field=fields, d.("Cohort_"+field)=T.(field)(first,:); end
    diagnostics=[diagnostics;d]; %#ok<AGROW>
    if count==0, continue; end
    G=T(accepted,:); groups{end+1,1}=G; %#ok<AGROW>
    eq=complex(double(G.(realField)),double(G.(imagField)));
    ref=complex(double(G.reference_symbol_i),double(G.reference_symbol_q));
    errorEnergy=sum(abs(eq-ref).^2); referenceEnergy=sum(abs(ref).^2);
    evm=NaN;
    if referenceEnergy>0, evm=sqrt(errorEnergy/referenceEnergy); end
    % Plotted pairs only, not complete-observation or independent-trial EVM.
    r=table(string(G.direction(1)),string(G.modulation(1)), ...
        localNumber(G,"layer"),localNumber(G,"snr_db"),localNumber(G,"mcs_index"), ...
        count,errorEnergy,referenceEnergy,100*evm,20*log10(evm), ...
        'VariableNames',{'Direction','Modulation','Layer','ConfiguredSNR_dB', ...
        'MCS','CapturedSampleCount','ErrorEnergy','ReferenceEnergy','CaptureEVM_pct','CaptureEVM_dB'});
    r=[r,d]; r.EVMScope="plotted_paired_samples_not_trial_or_independent_population";
    summary=[summary;r]; %#ok<AGROW>
end
end

function valid=localFinite(T,field)
valid=false(height(T),1);
if ~ismember(field,string(T.Properties.VariableNames)), return; end
values=T.(field);
assert(isnumeric(values) && isreal(values) && iscolumn(values), ...
    'sixgr:report:ConstellationOperandShape','Constellation operands must be one real numeric value per row.');
valid=isfinite(values);
end

function tokens=localTokens(values,n)
% Injective scalar tokens: float bits, exact integers, length-framed text.
if ischar(values)
    assert(size(values,1)==n,'sixgr:report:ConstellationCohortShape','One cohort value per row is required.');
    values=string(values);
else
    assert(iscolumn(values) && numel(values)==n, ...
        'sixgr:report:ConstellationCohortShape','One scalar cohort value per row is required.');
end
if isnumeric(values)
    assert(isreal(values),'sixgr:report:ConstellationCohortType','Cohort metadata must be real.');
    if isfloat(values), tokens=string(cellstr(num2hex(values)));
    else, tokens=string(values); end
elseif islogical(values)
    tokens=string(double(values));
elseif isstring(values) || iscellstr(values) || iscategorical(values)
    values=string(values); missing=ismissing(values); values(missing)="";
    tokens="text:"+localFrame(values); tokens(missing)="missing";
else
    error('sixgr:report:ConstellationCohortType','Unsupported cohort value type %s.',class(values));
end
end

function value=localFrame(value)
value=string(value); value=compose('%d:',strlength(value))+value;
end

function label=localLabel(T,row,fields)
parts=strings(numel(fields),1);
for i=1:numel(fields)
    field=fields(i); value=T.(field)(row,:);
    if isnumeric(value) && isfloat(value), text=string(sprintf('%.17g',double(value)));
    else, text=string(value); end
    if ismissing(text) || strlength(text)==0, text="[not retained]"; end
    parts(i)=field+"="+text;
end
label=strjoin(parts," | ");
end

function text=localText(T,row,field,missingText)
text=missingText;
if ismember(field,string(T.Properties.VariableNames))
    text=string(T.(field)(row,:));
    if ismissing(text) || strlength(text)==0, text=missingText; end
end
end

function value=localNumber(T,field)
raw=T.(field)(1,:);
if isnumeric(raw) || islogical(raw), value=double(raw);
else, value=str2double(string(raw)); end
end

function text=localReason(text,next)
if strlength(text)==0, text=next; else, text=text+";"+next; end
end
