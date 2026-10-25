function out=collectSRSPhysicalMeasurementObservations(T,field,unit)
% Original SRS observations and operands; no pooled dB or new PHY execution.
% Absolute antenna/branch estimates and normalized post-RF engineering means
% are distinct measurements. Receipt checks do not qualify physical accuracy.
arguments
    T table
    field (1,1) string
    unit (1,1) string
end
assert(any(field==["SRS_RSRP_dBm","SRS_RSRP_dB_re_UnitOccupiedRE_Es"]), ...
    'sixgr:report:SRSObservationField','Ambiguous legacy power is not a physical measurement substitute.');
assert((field=="SRS_RSRP_dBm"&&unit=="dBm")|| ...
    (field=="SRS_RSRP_dB_re_UnitOccupiedRE_Es"&&unit=="dB_re_UnitOccupiedRE_Es"), ...
    'sixgr:report:SRSObservationUnit','Retain the original power definition.');
out=table('Size',[0 8],'VariableTypes',{'double','double','string','string','string','string','string','string'}, ...
    'VariableNames',{'SourceRowIndex','ValueNumeric','ValueText','Availability', ...
    'PopulationID','PopulationJSON','SupportConfigurationJSON','Notes'});
if isempty(T)||~ismember(field,string(T.Properties.VariableNames)), return; end
values=sixgr.truth.numericMeasurementColumn(T.(field),field);
for k=1:height(T)
    value=values(k); if isnan(value), continue; end
    identity=localIdentity(T,k);
    if field=="SRS_RSRP_dBm"
        [support,valid]=localAbsolute(T,k,value);
        note="Original independently acquired pre-RF SRS power estimate; maximum original receive branch. "+ ...
            "Internal-element or modeled identity-combined branch plane is retained, not hardware/accuracy qualification.";
    else
        [support,valid]=localNormalized(T,k,value);
        note="Original receiver-grid engineering SRS port/receive-branch mean; not the standardized diversity report. "+ ...
            "No installed pre/post-RF plane or absolute power is inferred from normalized values.";
    end
    identity.SourceArtifact="air_interface/csv/srs_trials.csv";
    identity.SourceRowIndex=k; identity.SourceField=field; identity.Unit=unit;
    identity.OriginalValueText=localValueText(value);
    identity.ProvenanceScope="retained_source_row_not_independent_reception_verification";
    if isfield(support,'OriginalEvidence')
        e=support.OriginalEvidence;
        % These are explicitly measurement-capsule clocks, not replacements
        % for the separate trial/post-RF observation or legacy frame fields.
        for name=["ReceiverID","PlaneID","ObservationID","ObservationStartSample", ...
                "ObservationEndSampleExclusive","ObservationSampleRateHz","PhysicalConfigurationEpoch", ...
                "ObservationSHA256","ReferencePlane","SelectedBranch0","Resource"]
            identity.("PowerMeasurement"+name)=e.(name);
        end
    end
    token=string(jsonencode(sixgr.util.jsonSafeValue(identity)));
    status="not_available"; if valid, status="observed"; end
    if ~valid, note=note+" Original scalar retained without complete original operand authority; not coverage."; end
    note=note+" No averaging across source observations, points, resources, receivers or planes.";
    out(end+1,:)={k,value,localValueText(value),status, ...
        string(sixgr.util.sha256Hex(char(token))),token, ...
        string(jsonencode(sixgr.util.jsonSafeValue(support))),note}; %#ok<AGROW>
end
end

function id=localIdentity(T,k)
id=struct();
for name=["Slot","Frame","SFN","Time_s","SweepPointIndex","ConfiguredSNR_dB","SNR_dB", ...
        "ResourceID","SRSResourceID","SRSConfigurationEpoch", ...
        "UEIndex","UEID","CellID","ServingCell","RNTI","RandomSeed","ChannelSeed", ...
        "ObservationStartSample","ObservationEndSampleExclusive","ObservationSampleRateHz", ...
        "SRSAbsolutePowerResourceID","SRSAbsolutePowerSelectedBranch0", ...
        "SRSOccupiedPRBCount","SRSCarrierPRBCount","SRSFrequencyPRBStart","SRSFrequencyPRBEnd"]
    if ismember(name,string(T.Properties.VariableNames)), id.(name)=localNumber(T,k,name); end
end
for name=["RunID","ExecutionID","ConfigHash","ScenarioID","RunFolder","Direction", ...
        "ReceiverID","ReceiverWindowID","ReceiverClockDomain","SRSResourceIDsJSON", ...
        "SRSConfigurationContextID","SRSConfigurationContextVersion", ...
        "SRSAbsolutePowerSource","SRSAbsolutePowerReferencePlane", ...
        "SRSRSRPSource","SRSRSRPStatus","SRSBandwidthCoverageStatus"]
    if ismember(name,string(T.Properties.VariableNames)), id.(name)=localText(T,k,name); end
end
end

function [s,valid]=localAbsolute(T,k,value)
s=struct('Validation',"unqualified_missing_original_absolute_power_evidence"); valid=false;
flag=localNumber(T,k,"SRSAbsolutePowerAvailable");
if isnan(flag), return; end
assert(any(flag==[0 1]),'sixgr:report:SRSObservationAvailability','Power availability must be original boolean 0/1.');
assert(flag==1,'sixgr:report:SRSObservationAvailability','An unavailable absolute measurement cannot publish finite power.');
token=localText(T,k,"SRSAbsolutePowerEvidenceJSON");
digest=localText(T,k,"SRSAbsolutePowerEvidenceSHA256");
assert(token~=""&&digest~=""&&strcmpi(string(sixgr.rrc.asn1.asn1SHA256Hex( ...
    unicode2native(char(token),'UTF-8'))),digest), ...
    'sixgr:report:SRSObservationDigest','Original absolute measurement capsule digest changed.');
e=jsondecode(token);
assert(isstruct(e)&&isscalar(e),'sixgr:report:SRSObservationMetadata','Require one original measurement capsule.');
version=localRawText(e,'Version');
assert(any(version==["sixgr.srs.antenna_power/v1","sixgr.srs.antenna_power/v2"]), ...
    'sixgr:report:SRSObservationMetadata','Unsupported absolute power evidence version.');
assert(localRawText(e,'Definition')=="TS_38.215_V18.4.0_5.2.5_UL_SRS_RSRP"&& ...
    localRawText(e,'WaveformAmplitudeUnit')=="sqrt_mW"&& ...
    localRawText(e,'Estimator')=="independent_preRF_nrChannelEstimate_per_symbol_known_SRS_reconstruction"&& ...
    localRawText(e,'Aggregation')=="maximum_branch_selection_satisfies_diversity_lower_bound", ...
    'sixgr:report:SRSObservationSource','Retain the original supported estimator, unit and aggregation.');
for name=["AccuracyQualified","DetectedPathPowerMeasured","PostRFEstimateConsumed","TruthChannelConsumed","ReceiverFeedbackInput"]
    assert(~localRawFlag(e,name),'sixgr:report:SRSObservationSource','Do not promote this measurement into another evidence class.');
end
assert(localNumber(T,k,"SRSAbsolutePowerAccuracyQualified")==0, ...
    'sixgr:report:SRSObservationSource','No accuracy qualification is supplied by this estimator.');
plane=localRawText(e,'ReferencePlane');
status=localText(T,k,"SRSAbsolutePowerStatus");
binding=e.ReceiveBranchBinding;
assert(isstruct(binding)&&isscalar(binding),'sixgr:report:SRSObservationPlane','Retain original branch binding disposition.');
assert(~localRawFlag(binding,'HardwareConformanceVerified')&&~localRawFlag(binding,'AccuracyQualified'), ...
    'sixgr:report:SRSObservationPlane','Modeled branch wiring is not hardware qualification.');
if version=="sixgr.srs.antenna_power/v1"
    assert(plane=="internal_physical_receive_element_before_RX_front_end"&& ...
        ~localRawFlag(binding,'Available')&& ...
        localRawText(e,'ReferencePointApplicability')== ...
        "internal_element_measurement_not_standardized_1O_or_2O_UL_SRS_RSRP_qualification"&& ...
        status=="available_actual_antenna_capture_estimate_not_accuracy_qualified", ...
        'sixgr:report:SRSObservationPlane','Original internal-element plane was relabelled.');
else
    assert(plane=="modeled_receiver_branch_after_identity_combining_before_RX_front_end"&& ...
        localRawFlag(binding,'Available')&&localRawText(binding,'ReferencePlane')==plane&& ...
        localRawText(binding,'Status')=="verified_modeled_identity_combined_receiver_branch_plane"&& ...
        localRawText(e,'ReferencePointApplicability')== ...
        "modeled_identity_combined_receiver_branches_not_hardware_or_accuracy_qualification"&& ...
        status=="available_modeled_receiver_branch_power_not_accuracy_qualified", ...
        'sixgr:report:SRSObservationPlane','Original modeled receiver-branch plane was relabelled.');
end
for pair={ ["SRSAbsolutePowerSource","Estimator"], ["SRSAbsolutePowerReferencePlane","ReferencePlane"], ...
        ["SRSAbsolutePowerAggregation","Aggregation"] }
    names=pair{1}; assert(localText(T,k,names(1))==localRawText(e,names(2)), ...
        'sixgr:report:SRSObservationSource','Power source/plane/aggregation alias disagrees.');
end
assert(isstruct(e.Resource)&&isscalar(e.Resource),'sixgr:report:SRSObservationResource','Retain original installed resource.');
resource=localRawNumber(e.Resource,'ResourceID'); localIndex(resource,0);
assert(localRawText(e.Resource,'ConfigHash')~="",'sixgr:report:SRSObservationResource','Missing original installed resource digest.');
assert(localNumber(T,k,"SRSAbsolutePowerResourceID")==resource, ...
    'sixgr:report:SRSObservationResource','Original measured resource alias changed.');
for name=["ResourceID","SRSResourceID"]
    alias=localNumber(T,k,name);
    if ~isnan(alias), assert(alias==resource,'sixgr:report:SRSObservationResource','Original resource identity changed.'); end
end
power=localRawVector(e,'PerReceiveBranch_W');
assert(~isempty(power)&&all(isfinite(power)&power>=0)&&any(power>0), ...
    'sixgr:report:SRSObservationOperands','Require original nonnegative linear branch powers.');
indices=localRawVector(e,'ReceiveBranchIndices0');
assert(isequal(indices,0:numel(power)-1),'sixgr:report:SRSObservationBranch','Original branch ordering changed.');
[reported,selected]=max(power); branch=localRawNumber(e,'SelectedBranch0');
assert(branch==selected-1&&localNumber(T,k,"SRSAbsolutePowerSelectedBranch0")==branch, ...
    'sixgr:report:SRSObservationBranch','Retain original maximum-branch selection including tie order.');
localEqual(localRawNumber(e,'Reported_W'),reported);
localEqual(localRawNumber(e,'EngineeringBranchMean_W'),mean(power));
localEqual(value,10*log10(reported)+30);
localEqual(localNumber(T,k,"SRSAbsolutePowerBranchMean_dBm"),10*log10(mean(power))+30);
branchDB=localVector(T,k,"SRSRSRPPerReceiveAntenna_dBm");
assert(numel(branchDB)==numel(power),'sixgr:report:SRSObservationBranch','Missing original per-branch values.');
for n=1:numel(power), localEqual(branchDB(n),10*log10(power(n))+30); end
ports=localRawNumber(e,'SRSNumPorts'); localIndex(ports,1);
portPower=localRawMatrix(e,'PerPortReceiveBranch_W'); counts=localRawVector(e,'MappedRECountPerPort');
% JSON vectors have no row/column orientation. Restore only the original
% declared one-dimensional port/branch shape, never transpose a matrix.
if isvector(portPower)&&(ports==1||numel(power)==1)&&numel(portPower)==ports*numel(power)
    portPower=reshape(portPower,ports,numel(power));
end
assert(isequal(size(portPower),[ports,numel(power)])&&all(isfinite(portPower(:))&portPower(:)>=0)&& ...
    numel(counts)==ports&&all(isfinite(counts)&counts>0&counts==fix(counts)), ...
    'sixgr:report:SRSObservationOperands','Retain original per-port support/power dimensions.');
support=localRawMatrix(e,'ResourceSupportSubcarrier0Symbol0');
assert(size(support,2)==2&&~isempty(support)&&all(isfinite(support(:))&support(:)>=0&support(:)==fix(support(:)))&& ...
    size(unique(support,'rows'),1)==size(support,1)&& ...
    localRawNumber(e,'UniquePhysicalRECount')==size(support,1)&&all(counts<=size(support,1)), ...
    'sixgr:report:SRSObservationSupport','Original unique RE support/counts disagree.');
nfft=localRawNumber(e,'Nfft'); localIndex(nfft,1);
localEqual(localRawNumber(e,'RawGridScaleToSqrtW'),1/(nfft*sqrt(1000)));
localClock(e);
s.OriginalEvidenceJSON=token; s.OriginalEvidenceSHA256=digest; s.OriginalEvidence=e;
s.Validation="original_power_capsule_and_selected_operands_checked_not_accuracy_qualified";
valid=true;
end

function localClock(e)
rx=localRawText(e,'ReceiverID');
assert(startsWith(rx,"gnb_")&&endsWith(rx,"_rx")&&localRawText(e,'PlaneID')==rx+":pre_rf"&& ...
    localRawText(e,'ObservationID')~="",'sixgr:report:SRSObservationClock','Original endpoint/capture identity changed.');
first=localRawNumber(e,'ObservationStartSample'); last=localRawNumber(e,'ObservationEndSampleExclusive');
localIndex(first,0); localIndex(last,1); localIndex(localRawNumber(e,'PhysicalConfigurationEpoch'),0);
fs=localRawNumber(e,'ObservationSampleRateHz');
intervals=localRawMatrix(e,'ExecutionIntervals');
% A single original [start,end] interval is encoded as a JSON vector.
% jsondecode restores vectors as columns; restore only this exact pair,
% not malformed matrices or an inferred interval from capture endpoints.
if isvector(intervals)&&numel(intervals)==2
    intervals=reshape(intervals,1,2);
end
assert(last>first&&isfinite(fs)&&fs>0&&size(intervals,2)==2&&~isempty(intervals)&& ...
    all(isfinite(intervals(:))&intervals(:)>=0&intervals(:)==fix(intervals(:)))&& ...
    intervals(1,1)<=first&&intervals(end,2)>=last&&all(intervals(:,2)>intervals(:,1))&& ...
    all(intervals(2:end,1)==intervals(1:end-1,2)), ...
    'sixgr:report:SRSObservationClock','Original execution intervals must cover this capture continuously.');
for name=["ObservationSHA256","ReferenceSymbolSHA256","AlignedWaveformSHA256","ReceivedGridSHA256"]
    assert(~isempty(regexp(char(localRawText(e,name)),'^[0-9a-fA-F]{64}$','once')), ...
        'sixgr:report:SRSObservationDigest','Retain original sample/operator digests.');
end
end

function [s,valid]=localNormalized(T,k,value)
s=struct('Validation',"unqualified_missing_original_postRF_engineering_operands"); valid=false;
source=localText(T,k,"SRSRSRPSource"); status=localText(T,k,"SRSRSRPStatus");
s.OriginalSource=source; s.OriginalStatus=status;
if source==""||status=="", return; end
assert(source=="received_srs_channel_estimate_times_known_reference_symbols"&&status=="observed", ...
    'sixgr:report:SRSObservationSource','Finite normalized power must retain its original engineering source/status.');
branch=localVector(T,k,"SRSRSRPPerReceiveAntenna_dB_re_UnitOccupiedRE_Es");
if isempty(branch), return; end
positive=isfinite(branch);
assert(any(positive)&&~any(isinf(branch)&branch>0), ...
    'sixgr:report:SRSObservationOperands','Original engineering branch mean requires positive finite support.');
localEqual(value,10*log10(mean(10.^(branch(positive)/10))));
s.OriginalPerReceiveAntenna_dB_re_UnitOccupiedRE_Es=branch;
s.Aggregation="linear_mean_of_positive_received_branch_port_means";
s.Scope="supplied_receiver_grid_engineering_estimate_not_standardized_diversity_report";
s.Validation="original_engineering_branch_mean_operands_checked_not_accuracy_qualified";
valid=true;
end

function value=localNumber(T,k,name)
value=NaN; if ~ismember(name,string(T.Properties.VariableNames)), return; end
value=sixgr.truth.numericMeasurementColumn(T.(name)(k,:),name);
assert(isscalar(value),'sixgr:report:SRSObservationMetadata','Require one original numeric scalar.');
end
function value=localText(T,k,name)
value=""; if ~ismember(name,string(T.Properties.VariableNames)), return; end
raw=T.(name)(k,:); if iscell(raw)&&isscalar(raw), raw=raw{1}; end
if isnumeric(raw)&&isscalar(raw)&&isnan(raw), return; end
assert((ischar(raw)&&(isrow(raw)||isempty(raw)))||(isstring(raw)&&isscalar(raw)), ...
    'sixgr:report:SRSObservationMetadata','Preserve original scalar text, not numeric casting.');
value=string(raw); if ismissing(value), value=""; end
end
function value=localVector(T,k,name)
token=localText(T,k,name); value=[]; if token=="", return; end
if startsWith(strtrim(token),"["), value=jsondecode(token);
else
    parts=strip(split(token,"|"));
    for part=parts(:).'
        assert(~isempty(regexpi(char(part),'^[+-]?(?:(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?|Inf|NaN)$','once')), ...
            'sixgr:report:SRSObservationMetadata','Malformed original branch token must not become a missing branch.');
    end
    value=str2double(parts);
end
assert(isnumeric(value)&&isreal(value)&&isvector(value), ...
    'sixgr:report:SRSObservationMetadata','Original vector tokens must preserve numeric branch positions.');
value=double(value(:).');
end
function value=localRawNumber(s,name)
assert(isstruct(s)&&isscalar(s)&&isfield(s,name)&&isnumeric(s.(name))&&isreal(s.(name))&&isscalar(s.(name)), ...
    'sixgr:report:SRSObservationMetadata','Retain original numeric scalar %s.',name);
value=double(s.(name));
end
function value=localRawText(s,name)
assert(isstruct(s)&&isscalar(s)&&isfield(s,name)&& ...
    ((ischar(s.(name))&&(isrow(s.(name))||isempty(s.(name))))||(isstring(s.(name))&&isscalar(s.(name)))), ...
    'sixgr:report:SRSObservationMetadata','Retain original scalar text %s.',name);
value=string(s.(name)); assert(~ismissing(value),'sixgr:report:SRSObservationMetadata','Missing original text.');
end
function value=localRawFlag(s,name)
assert(isfield(s,name)&&islogical(s.(name))&&isscalar(s.(name)), ...
    'sixgr:report:SRSObservationMetadata','Require original JSON logical flag %s, not numeric authority.',name);
value=logical(s.(name));
end
function value=localRawVector(s,name)
value=localRawMatrix(s,name);
assert(isvector(value),'sixgr:report:SRSObservationMetadata','Require original numeric vector %s.',name);
value=value(:).';
end
function value=localRawMatrix(s,name)
assert(isfield(s,name)&&isnumeric(s.(name))&&isreal(s.(name))&&ismatrix(s.(name)), ...
    'sixgr:report:SRSObservationMetadata','Require original numeric matrix %s.',name);
value=double(s.(name));
end
function localIndex(value,minimum)
assert(isfinite(value)&&value>=minimum&&value<flintmax&&value==fix(value), ...
    'sixgr:report:SRSObservationMetadata','Original integer identity/support is invalid.');
end
function localEqual(a,b)
assert(isequaln(a,b)||(isfinite(a)&&isfinite(b)&&abs(a-b)<=64*eps(max(abs([a b])))), ...
    'sixgr:report:SRSObservationOperands','Original operands disagree beyond CSV/roundoff tolerance.');
end
function value=localValueText(x)
if isinf(x), value=string(x); else, value=string(sprintf('%.17g',x)); end
end
