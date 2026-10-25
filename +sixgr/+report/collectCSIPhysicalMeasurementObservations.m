function out=collectCSIPhysicalMeasurementObservations(T,field,unit)
% Preserve original selected CSI measurements, not a pooled dB statistic.
% Validates retained operands/identity, NOT independent PHY accuracy. Missing
% legacy support stays explicitly unqualified and cannot form a series.
arguments
    T table
    field (1,1) string
    unit (1,1) string
end
out=table('Size',[0 8],'VariableTypes',{'double','double','string','string','string','string','string','string'}, ...
    'VariableNames',{'SourceRowIndex','ValueNumeric','ValueText','Availability', ...
    'PopulationID','PopulationJSON','SupportConfigurationJSON','Notes'});
assert(any(field==["MeasurementRSRP_dBm","MeasurementRSRP_dB_re_UnitOccupiedRE_Es", ...
    "MeasurementRSRQ_dB","ReferenceMeasuredSINR_dB"]), ...
    'sixgr:report:CSIObservationField','Only original physical CSI measurements belong here.');
if isempty(T)||~ismember(field,string(T.Properties.VariableNames)), return; end
values=sixgr.truth.numericMeasurementColumn(T.(field),field);
assert(numel(values)==height(T),'sixgr:report:CSIObservationShape','One scalar per original row.');
for k=1:height(T)
    identity=localIdentity(T,k);
    localPopulation(identity);
    [support,validated]=localSupport(T,k,field,unit,values(k),identity);
    if isnan(values(k)), continue; end % Preserve unavailable operands in original raw CSV.
    identity.SourceArtifact="air_interface/csv/csi_rs_trials.csv";
    identity.SourceRowIndex=k; identity.SourceField=field;
    identity.Unit=unit;
    identity.OriginalValueText=localValueText(values(k));
    identity.ProvenanceScope="retained_source_row_not_independent_reception_verification";
    identityJSON=string(jsonencode(sixgr.util.jsonSafeValue(identity)));
    supportJSON=string(jsonencode(sixgr.util.jsonSafeValue(support)));
    state="not_available";
    if validated, state="observed"; end
    note="Original selected CSI observation; source column="+field+ ...
        "; no averaging across source rows, resources, receive branches, planes or operating points. "+ ...
        "Absolute units do not establish standardized reference-point, hardware or statistical accuracy. ";
    if ~validated
        note=note+"Legacy scalar retained without complete original operand/plane support; unqualified, not coverage. ";
    end
    note=note+"Original signed/nonfinite and per-branch operands remain in SupportConfigurationJSON and raw CSI CSV.";
    out(end+1,:)={k,values(k),localValueText(values(k)),state, ...
        string(sixgr.util.sha256Hex(char(identityJSON))),identityJSON,supportJSON,note}; %#ok<AGROW>
end
end

function id=localIdentity(T,k)
id=struct();
numeric=["Slot","Frame","SFN","Time_s","SweepPointIndex","ConfiguredSNR_dB","SNR_dB", ...
    "RandomSeed","ChannelSeed","ResourceID","ResourceSetID","BeamID","UEIndex","UEID", ...
    "CellID","ServingCell","RNTI","BWPID","ReceiverClockEpoch","MeasurementClockEpoch", ...
    "ObservationStartSample","ObservationEndSampleExclusive","ObservationSampleRateHz", ...
    "ResultAvailableAtSample","MeasurementSelectedResourceOrdinal", ...
    "MeasurementReceiveAntennaIndex1Based","MeasurementRSRQReceiveAntennaIndex1Based", ...
    "DLMeasurementNCellID"];
text=["RunID","RunTag","ExecutionID","ConfigHash","ScenarioID","RunFolder", ...
    "ReceiverID","ReceiverWindowID","ReceiverClockDomain","MeasurementClockDomain", ...
    "PhysicalMeasurementReferencePlane","PowerReferencePlane", ...
    "PhysicalMeasurementObservationSHA256","PhysicalMeasurementObservationHashPlane", ...
    "ReferenceSINRMeasurementJSON","CSIObservationPopulationJSON","CSIObservationPopulationSHA256", ...
    "CSIObservationPopulationSource","CSIObservationPopulationBindingJSON", ...
    "DLMeasurementConfigurationFamily","DLMeasurementConfigurationSHA256", ...
    "DLMeasurementInstallationSHA256","DLMeasurementAuthorityStatus","DLMeasurementAuthoritySource"];
for name=numeric
    if ismember(name,string(T.Properties.VariableNames)), id.(name)=localNumber(T,k,name); end
end
for name=text
    if ismember(name,string(T.Properties.VariableNames)), id.(name)=localText(T,k,name); end
end
% These are retained owner claims, not authority reconstructed by reporting.
% CSV 0/1 (and unavailable NaN) is distinct from a missing historical field.
for name=["DLMeasurementAuthorityRequired","DLMeasurementAuthorityEligible"]
    if ~ismember(name,string(T.Properties.VariableNames)), continue; end
    value=T.(name)(k,:);
    assert((islogical(value)||isnumeric(value))&&isreal(value)&&isscalar(value)&& ...
        (value==0||value==1||isnan(value)), ...
        'sixgr:report:CSIObservationMetadata','Retain original scalar authority flag, not a derived pass.');
    id.(name)=value;
end
end

function [s,ok]=localSupport(T,k,field,unit,value,id)
s=struct('Validation',"unqualified_missing_original_operands",'SourceField',field,'Unit',unit);
ok=false;
texts=["MeasurementPhysicalResourcesJSON","MeasurementSource","PhysicalMeasurementStatus", ...
    "MeasurementResourceIDs","MeasurementSymbolIndices0Based","MeasurementRSRQAntennaAggregation", ...
    "ReferenceMeasuredSINRSource","ReferenceMeasuredSINRStatus","ReferenceMeasuredSINRDomain", ...
    "PhysicalMeasurementPlaneBindingStatus","PhysicalMeasurementPlaneBindingJSON", ...
    "PhysicalMeasurementPlaneBindingSHA256"];
numbers=["MeasurementNumRB","MeasurementFirstPRB0Based","MeasurementSubcarrierSpacing_kHz", ...
    "MeasurementBandwidth_Hz","MeasurementRSRQNumeratorRSRP_dBm","MeasurementRSRQDenominatorRSSI_dBm", ...
    "MeasurementRSRQNumeratorRSRP_dB_re_UnitOccupiedRE_Es","MeasurementRSRQDenominatorRSSI_dB_re_UnitOccupiedRE_Es"];
for name=texts
    if ismember(name,string(T.Properties.VariableNames)), s.(name)=localText(T,k,name); end
end
for name=numbers
    if ismember(name,string(T.Properties.VariableNames)), s.(name)=localNumber(T,k,name); end
end
for name=["MeasurementPowerReferenceNormalized","PhysicalMeasurementPlaneBindingAvailable", ...
        "PhysicalMeasurementStandardizedReferencePointQualified","PhysicalMeasurementHardwareQualified"]
    if ismember(name,string(T.Properties.VariableNames))
        x=localNumber(T,k,name);
        assert(isnan(x)||any(x==[0 1]),'sixgr:report:CSIObservationMetadata','Original boolean metadata is 0/1 or missing.');
        s.(name)=x;
    end
end
raw=localText(T,k,"MeasurementPhysicalResourcesJSON");
if raw=="", return; end
resources=localJSON(raw,"MeasurementPhysicalResourcesJSON");
if isempty(resources)
    assert(isnan(value),'sixgr:report:CSIObservationResource','Finite selected value has no original resource population.'); return;
end
if isstruct(resources), resources=num2cell(resources); end
assert(iscell(resources)&&isvector(resources),'sixgr:report:CSIObservationMetadata','Original resource population must be an array.');
ordinal=localNumber(T,k,"MeasurementSelectedResourceOrdinal");
if isnan(ordinal), return; end
assert(isfinite(ordinal)&&ordinal>=1&&ordinal==fix(ordinal)&&ordinal<=numel(resources), ...
    'sixgr:report:CSIObservationResource','Selected resource ordinal is outside the original population.');
r=resources{ordinal};
if isempty(r)
    assert(isnan(value),'sixgr:report:CSIObservationResource','Finite selected value has no original resource.'); return;
end
assert(isstruct(r)&&isscalar(r),'sixgr:report:CSIObservationResource','One original selected resource is required.');
resourceID=localRawNumber(r,'ResourceID');
assert(isfinite(resourceID)&&resourceID>=0&&resourceID==fix(resourceID), ...
    'sixgr:report:CSIObservationResource','Retain the original numeric resource ID.');
% ResourceID is a producer-selected identity, not CRI, a beam index, or an
% ordinal. Only compare declared identities; do not manufacture any.
if isfield(id,'ResourceID')&&isfinite(id.ResourceID)
    assert(id.ResourceID==resourceID,'sixgr:report:CSIObservationResource','Selected resource identity changed.');
end
resourceIDs=localText(T,k,"MeasurementResourceIDs");
if resourceIDs~=""
    ids=localVectorToken(resourceIDs);
    assert(numel(ids)==numel(resources)&&ids(ordinal)==resourceID, ...
        'sixgr:report:CSIObservationResource','Resource ID vector no longer identifies selected original resource.');
end
powerUnit=localRawText(r,'PowerUnit');
assert(any(powerUnit==["W_resource_grid","relative_to_unit_occupied_RE_Es"]), ...
    'sixgr:report:CSIObservationUnit','Original physical measurement units are required.');
normalized=powerUnit=="relative_to_unit_occupied_RE_Es";
assert((field=="MeasurementRSRP_dBm"&&unit=="dBm")|| ...
    (field=="MeasurementRSRP_dB_re_UnitOccupiedRE_Es"&&unit=="dB_re_UnitOccupiedRE_Es")|| ...
    (any(field==["MeasurementRSRQ_dB","ReferenceMeasuredSINR_dB"])&&unit=="dB"), ...
    'sixgr:report:CSIObservationUnit','Metric units must retain their original definition.');
if isfield(s,'MeasurementPowerReferenceNormalized')&&~isnan(s.MeasurementPowerReferenceNormalized)
    assert(logical(s.MeasurementPowerReferenceNormalized)==normalized, ...
        'sixgr:report:CSIObservationUnit','Original normalized/absolute authority disagrees.');
end
suffix="_dBm"; if normalized, suffix="_dB_re_UnitOccupiedRE_Es"; end
if field=="MeasurementRSRP_dBm"&&normalized || field=="MeasurementRSRP_dB_re_UnitOccupiedRE_Es"&&~normalized
    assert(isnan(value),'sixgr:report:CSIObservationUnit','Do not publish the opposite power plane.'); return;
end
if startsWith(field,"MeasurementRSRP")
    branch=localNumber(T,k,"MeasurementReceiveAntennaIndex1Based");
    vector=localRawVector(r,"RSRPPerAntenna"+suffix);
elseif field=="MeasurementRSRQ_dB"
    branch=localNumber(T,k,"MeasurementRSRQReceiveAntennaIndex1Based");
    vector=localRawVector(r,'RSRQPerAntenna_dB');
else
    rawSINR=localText(T,k,"ReferenceSINRMeasurementJSON");
    if rawSINR=="", return; end
    q=localJSON(rawSINR,"ReferenceSINRMeasurementJSON");
    assert(isfield(r,'SINR')&&isstruct(r.SINR)&&isscalar(r.SINR)&&isequaln(q,r.SINR), ...
        'sixgr:report:CSIObservationSINR','Selected SINR evidence differs from its original resource.');
    branch=localRawNumber(q,'ReceiveBranch1Based');
    vector=localRawVector(q,'CSI_SINRPerReceiveAntenna_dB');
    originalSINR=localRawNumber(q,'CSI_SINR_dB');
    sinrSource=localRawText(q,'Source');
    assert(localText(T,k,"ReferenceMeasuredSINRSource")==sinrSource&& ...
        localRawText(r,'RSRPSource')==sinrSource&& ...
        any(sinrSource==["nrChannelEstimate_port3000_reference_RE_power_per_receive_branch", ...
        "received_flat_LS_noise_debiased_port3000_reference_RE_power", ...
        "received_CDM_despread_CSI_IM_noise_debiased_port3000_reference_RE_power"]), ...
        'sixgr:report:CSIObservationSINR','Original selected SINR source changed or is unsupported.');
    domain=localRawText(q,'MeasurementDomain');
    assert(domain=="csi_rs_port3000_reference_re_received_plane"&& ...
        localText(T,k,"ReferenceMeasuredSINRDomain")==domain, ...
        'sixgr:report:CSIObservationSINR','Original selected SINR measurement domain changed.');
    % The physical-resource owner adds this alias; the standalone native
    % SINR producer has no PowerUnit field. Never manufacture that alias.
    if isfield(q,'PowerUnit')
        assert(localRawText(q,'PowerUnit')==powerUnit, ...
            'sixgr:report:CSIObservationUnit','SINR and selected-resource power units disagree.');
    end
    s.OriginalSINR=q; % Retains dedicated CSI-IM/residual distinction and signed operands.
    if isinf(value)&&isnan(originalSINR)
        % Legacy JSON encodes +/-Inf as null without a signed numeric token.
        % Preserve the CSV scalar and bytes, but do not invent JSON authority.
        s.Validation="unqualified_nonfinite_original_JSON_operand"; return;
    end
    localEqual(value,originalSINR,'sixgr:report:CSIObservationSINR');
end
if isnan(branch)
    assert(isnan(value),'sixgr:report:CSIObservationBranch','Finite scalar lacks its original selected branch.'); return;
end
assert(isfinite(branch)&&branch>=1&&branch==fix(branch)&&branch<=numel(vector), ...
    'sixgr:report:CSIObservationBranch','Original selected receive branch is invalid.');
assert(localRawNumber(r,'NumReceiveAntennas')==numel(vector), ...
    'sixgr:report:CSIObservationBranch','Do not renumber or drop missing receive branches.');
localEqual(value,vector(branch),'sixgr:report:CSIObservationBranch');
for pair={ ["MeasurementNumRB","NumRB"], ["MeasurementFirstPRB0Based","FirstPRB0Based"], ...
        ["MeasurementSubcarrierSpacing_kHz","SubcarrierSpacing_kHz"] }
    names=pair{1};
    if isfield(s,names(1))&&isfinite(s.(names(1)))
        localEqual(s.(names(1)),localRawNumber(r,names(2)),'sixgr:report:CSIObservationSupport');
    end
end
symbols=localText(T,k,"MeasurementSymbolIndices0Based");
if symbols~=""
    assert(isequal(localVectorToken(symbols),localRawVector(r,'SymbolIndices0Based').'), ...
        'sixgr:report:CSIObservationSupport','Original symbol support changed.');
end
if field=="MeasurementRSRQ_dB"
    numerator=localRawVector(r,"RSRPPerAntenna"+suffix);
    denominator=localRawVector(r,"RSSIPerAntenna"+suffix);
    assert(numel(numerator)==numel(vector)&&numel(denominator)==numel(vector), ...
        'sixgr:report:CSIObservationSupport','RSRQ operands must retain the same receive branches.');
    for pair={ ["MeasurementRSRQNumeratorRSRP"+suffix,"RSRP"], ["MeasurementRSRQDenominatorRSSI"+suffix,"RSSI"] }
        names=pair{1}; expected=numerator(branch); if names(2)=="RSSI", expected=denominator(branch); end
        if isfield(s,names(1))&&~isnan(s.(names(1)))
            localEqual(s.(names(1)),expected,'sixgr:report:CSIObservationSupport');
        end
    end
    nrb=localRawNumber(r,'NumRB');
    assert(isfinite(nrb)&&nrb>0&&nrb==fix(nrb),'sixgr:report:CSIObservationSupport','RSRQ requires original positive RB support.');
    localEqual(value,10*log10(nrb)+numerator(branch)-denominator(branch), ...
        'sixgr:report:CSIObservationSupport');
end
s.SelectedResource=r;
plane=localText(T,k,"PhysicalMeasurementReferencePlane");
status=localText(T,k,"PhysicalMeasurementStatus");
assert(isfield(r,'Available')&&(islogical(r.Available)||isnumeric(r.Available))&& ...
    isscalar(r.Available)&&isreal(r.Available)&&any(r.Available==[0 1]), ...
    'sixgr:report:CSIObservationMetadata','Retain the original resource availability flag.');
knownSources=["nrChannelEstimate_port3000_reference_RE_power_per_receive_branch", ...
    "received_flat_LS_noise_debiased_port3000_reference_RE_power", ...
    "received_CDM_despread_CSI_IM_noise_debiased_port3000_reference_RE_power"];
source=localRawText(r,'RSRPSource');
resourceSource=localRawText(r,'Source');
outerSource=localText(T,k,"MeasurementSource");
ok=~isnan(value)&&plane~=""&&~any(contains(lower(plane),["unavailable","unknown"]))&& ...
    startsWith(status,"available")&&logical(r.Available)&&any(source==knownSources)&& ...
    any(resourceSource==["received_port3000_linear_RSRP_and_nrCSIRSMeasurements_RSSI", ...
        "received_port3000_linear_RSRP_and_native_RSSI_normalized_unit_RE_grid"])&& ...
    any(outerSource==["received_port3000_linear_RSRP_and_native_RSSI_pre_front_end_grid", ...
        "actual_csirs_re_measurement_relative_to_unit_occupied_re_es"]);
if ok, s.Validation="original_selected_scalar_and_operand_identity_checked_not_accuracy_qualified"; end
end

function localPopulation(id)
if ~isfield(id,'CSIObservationPopulationJSON')||id.CSIObservationPopulationJSON=="", return; end
p=localJSON(id.CSIObservationPopulationJSON,"CSIObservationPopulationJSON");
assert(localRawText(p,'Version')=="csi_observation_population/v1"&& ...
    localRawText(p,'Source')=="configured_queue_context_not_emission_proof"&& ...
    isfield(p,'Fields')&&isstruct(p.Fields)&&isscalar(p.Fields)&&isfield(p,'Queue'), ...
    'sixgr:report:CSIObservationPopulation','Use the original queued capsule, not reconstructed point metadata.');
expectedFields=["RunFolder","RunID","RunTag","ExecutionID","ConfigHash","ScenarioID", ...
    "RandomSeed","ChannelSeed","SweepPointIndex","ConfiguredSNR_dB"];
assert(isequal(sort(string(fieldnames(p.Fields))),sort(expectedFields(:)))&& ...
    localRawText(p,'ConfiguredSNRRole')=="configured_operating_point_label_not_measured_SINR_or_thermal_noise_authority"&& ...
    localRawText(p,'SeedRole')=="configured_global_and_channel_seeds_not_executed_receiver_noise_stream_seed", ...
    'sixgr:report:CSIObservationPopulation','Retain the versioned original population schema and scope.');
if isfield(id,'CSIObservationPopulationSource')
    assert(id.CSIObservationPopulationSource==string(p.Source), ...
        'sixgr:report:CSIObservationPopulation','Original population source changed.');
end
for name=["RandomSeed","ChannelSeed","SweepPointIndex","ConfiguredSNR_dB"]
    assert(isfield(p.Fields,name),'sixgr:report:CSIObservationPopulation','Missing declared population coordinate.');
    if isempty(p.Fields.(name)), p.Fields.(name)=NaN; end % Producer NaN -> JSON null.
    localRawNumber(p.Fields,name);
    x=p.Fields.(name);
    assert((name~="ConfiguredSNR_dB"&&isnan(x))||(isfinite(x)&& ...
        (name=="ConfiguredSNR_dB"||(x>=0&&x==fix(x)))), ...
        'sixgr:report:CSIObservationPopulation','Invalid original point/seed coordinate.');
end
digest=localRawText(p,'SHA256');
assert(string(sixgr.util.sha256Hex(jsonencode(rmfield(p,'SHA256'))))==digest && ...
    isfield(id,'CSIObservationPopulationSHA256')&&id.CSIObservationPopulationSHA256==digest, ...
    'sixgr:report:CSIObservationPopulationDigest','Original queued population digest changed.');
for name=string(fieldnames(p.Fields)).'
    if ~isfield(id,name), continue; end
    a=id.(name); b=p.Fields.(name);
    if isnumeric(a), localSame(a,b,'sixgr:report:CSIObservationPopulation');
    else, assert(a==string(b),'sixgr:report:CSIObservationPopulation','Original population text changed.'); end
end
assert(isfield(id,'CSIObservationPopulationBindingJSON')&&id.CSIObservationPopulationBindingJSON~="", ...
    'sixgr:report:CSIObservationPopulation','Original completed binding must accompany a queued capsule.');
b=localJSON(id.CSIObservationPopulationBindingJSON,"CSIObservationPopulationBindingJSON");
assert(localRawText(b,'Source')=="queued_population_matched_to_completed_same_owner_CSI_RS_TX_receipt"&& ...
    strlength(localRawText(b,'ComponentID'))>0, ...
    'sixgr:report:CSIObservationPopulation','Retain the original completed-source binding.');
for pair={ ["Slot","SourceSlot"], ["CellID","ServingCell"], ["ObservationSampleRateHz","SampleRateHz"], ...
        ["MeasurementClockEpoch","PhysicalConfigurationEpoch"], ["ResultAvailableAtSample","ReceiverResultAvailableAtSample"] }
    names=pair{1};
    assert(isfield(id,names(1)),'sixgr:report:CSIObservationPopulation','Missing original receiver identity.');
    localSame(id.(names(1)),localRawNumber(b,names(2)),'sixgr:report:CSIObservationPopulation');
end
q=p.Queue;
for name=["SourceSlot","PhysicalConfigurationEpoch","SampleRateHz"]
    a=localRawNumber(q,name); other=localRawNumber(b,name);
    assert(isfinite(a)&&a>=0&&(name=="SampleRateHz"||a==fix(a)), ...
        'sixgr:report:CSIObservationPopulation','Original queue coordinates must be finite.');
    if name=="SampleRateHz", assert(a>0,'sixgr:report:CSIObservationPopulation','Sample rate must be positive.'); end
    if name=="SourceSlot", assert(a>=1,'sixgr:report:CSIObservationPopulation','Source slot is one-based.'); end
    localSame(a,other,'sixgr:report:CSIObservationPopulation');
end
assert(isfield(id,'ObservationEndSampleExclusive'), ...
    'sixgr:report:CSIObservationPopulation','Original receiver end sample is required.');
times=[localRawNumber(q,'QueuedAtSample'),localRawNumber(b,'FirstActiveSample'), ...
    localRawNumber(b,'CommittedAtSample'),id.ObservationEndSampleExclusive,id.ResultAvailableAtSample];
assert(all(isfinite(times)&times>=0&times==fix(times))&&all(diff(times)>=0)&&times(2)<times(3), ...
    'sixgr:report:CSIObservationPopulation','Original queue/TX completion/reception order changed.');
assert(localRawText(q,'ClockDomain')=="shared_physical_sample_clock/v1"&& ...
    isfield(id,'MeasurementClockDomain')&&id.MeasurementClockDomain=="shared_receiver_sample_clock/v1", ...
    'sixgr:report:CSIObservationPopulation','Preserve original clock domains.');
end

function value=localNumber(T,k,name)
value=NaN;
if ~ismember(name,string(T.Properties.VariableNames)), return; end
value=sixgr.truth.numericMeasurementColumn(T.(name)(k,:),name);
assert(isscalar(value),'sixgr:report:CSIObservationMetadata','Require one original scalar.');
end
function value=localText(T,k,name)
value=""; if ~ismember(name,string(T.Properties.VariableNames)), return; end
raw=T.(name)(k,:); if iscell(raw)&&isscalar(raw), raw=raw{1}; end
if isnumeric(raw)&&isscalar(raw)&&isnan(raw), return; end
assert((ischar(raw)&&isrow(raw))||(isstring(raw)&&isscalar(raw)), ...
    'sixgr:report:CSIObservationMetadata','Require original scalar text, not numeric text casting.');
value=string(raw); if ismissing(value), value=""; end
end
function value=localJSON(raw,name)
try, value=jsondecode(raw); catch
    error('sixgr:report:CSIObservationMetadata','Malformed original %s JSON.',name);
end
end
function value=localRawNumber(s,name)
assert(isstruct(s)&&isscalar(s)&&isfield(s,name)&&isnumeric(s.(name))&& ...
    isreal(s.(name))&&(isscalar(s.(name))||isempty(s.(name))), ...
    'sixgr:report:CSIObservationMetadata','Require original numeric scalar %s.',name);
value=s.(name); if isempty(value), value=NaN; end
end
function value=localRawVector(s,name)
assert(isfield(s,name)&&isnumeric(s.(name))&&isreal(s.(name))&&isvector(s.(name)), ...
    'sixgr:report:CSIObservationMetadata','Require original numeric receive-branch vector %s.',name);
value=double(s.(name)(:).');
end
function value=localRawText(s,name)
assert(isstruct(s)&&isscalar(s)&&isfield(s,name)&& ...
    ((ischar(s.(name))&&(isrow(s.(name))||isempty(s.(name))))||(isstring(s.(name))&&isscalar(s.(name)))), ...
    'sixgr:report:CSIObservationMetadata','Require original text %s.',name);
value=string(s.(name));
assert(~ismissing(value),'sixgr:report:CSIObservationMetadata','Original source text is missing.');
end
function x=localVectorToken(raw)
if startsWith(strtrim(raw),"["), x=jsondecode(raw);
else, x=str2double(split(raw,"|")); end
assert(isnumeric(x)&&isreal(x)&&isvector(x)&&all(isfinite(x)), ...
    'sixgr:report:CSIObservationMetadata','Original resource IDs must be a finite numeric vector.');
x=double(x(:));
end
function localEqual(a,b,id)
assert(isnumeric(a)&&isreal(a)&&isscalar(a)&&isnumeric(b)&&isreal(b)&&isscalar(b),id,'Compare original numeric scalars.');
assert(isequaln(a,b)||(isfinite(a)&&isfinite(b)&&abs(a-b)<=64*eps(max([1 abs(a) abs(b)]))), ...
    id,'Original measurement/identity operands disagree; no replacement value is permitted.');
end
function localSame(a,b,id)
assert(isnumeric(a)&&isreal(a)&&isscalar(a)&&isnumeric(b)&&isreal(b)&&isscalar(b)&&isequaln(a,b), ...
    id,'Original identity coordinates must match exactly.');
end
function value=localValueText(x)
if isinf(x), value=string(x); else, value=string(sprintf('%.17g',x)); end
end
