function [summary,audit]=summarizeSharedRFEndpoint(plane,endpoint)
%SUMMARIZESHAREDRFENDPOINT Post-reception metadata from one executed endpoint.
% No YAML/configuration inference, receiver inputs, waveform regeneration or
% fitted measurements. Applied flags describe the covering stream segments;
% they do not prove sample mutation at every point of a cropped observation.
% Converter populations are additive only for complete executed segments.
arguments
    plane (1,1) struct
    endpoint (1,1) string {mustBeMember(endpoint,["TX","RX"])}
end
suffix=":post_rf"; if endpoint=="TX", suffix=":tx"; end
assert(all(isfield(plane,{'ReceiverID','Observation','Segments'})) && ...
    isscalar(string(plane.ReceiverID)) && endsWith(string(plane.ReceiverID),suffix) && ...
    isa(plane.Observation,'sixgr.phy.waveform.WaveformObservationBuffer') && ...
    isscalar(plane.Observation) && plane.Observation.isComplete(), ...
    'sixgr:truth:InvalidRFEndpointObservation','Retain one complete actual endpoint observation.');
id=string(plane.ReceiverID);
id=extractBefore(id,strlength(id)-strlength(suffix)+1);
assert(strlength(id)>0,'sixgr:truth:InvalidRFEndpointIdentity','A physical node ID is required.');
first=plane.Observation.StartSample; stop=plane.Observation.EndSampleExclusive;
segments=plane.Segments;
assert(iscell(segments) && ~isempty(segments) && stop>first, ...
    'sixgr:truth:MissingRFEndpointExecution','Retain ordered physical execution segments.');
replays=cell(0,1); bounds=zeros(0,2); next=first; whole=true;
for k=1:numel(segments)
    s=segments{k};
    assert(isstruct(s) && isscalar(s) && isfield(s,'Execution') && ...
        all(isfield(s.Execution,{'StartSample','EndSampleExclusive',char(endpoint)})), ...
        'sixgr:truth:MissingRFEndpointExecution','Each segment needs an executed endpoint and clock.');
    e=s.Execution; a=double(e.StartSample); b=double(e.EndSampleExclusive);
    validateattributes([a b],{'double'},{'real','finite','integer','nonnegative'});
    assert(b>a,'sixgr:truth:InvalidRFEndpointInterval','Execution intervals must be nonempty.');
    if b<=first || a>=stop, continue; end
    assert(max(a,first)==next,'sixgr:truth:RFEndpointCoverageGap', ...
        'Do not accept missing, reordered or overlapping endpoint execution.');
    nodes=e.(endpoint);
    assert(isstruct(nodes) && all(isfield(nodes,{'ID','Replay'})), ...
        'sixgr:truth:MissingRFEndpointExecution','Physical endpoint ownership is required.');
    node=nodes(string({nodes.ID})==id);
    assert(isscalar(node) && isstruct(node.Replay) && isscalar(node.Replay), ...
        'sixgr:truth:RFEndpointIdentityMismatch','Exactly one physical endpoint must own each interval.');
    r=node.Replay;
    assert(all(isfield(r,{'RFEndpoint','RFStreamStartSample','RFStreamEndSampleExclusive', ...
        'RFProcessingMode'})) && string(r.RFEndpoint)==lower(endpoint) && ...
        string(r.RFProcessingMode)=="retained_sample_stream" && ...
        isequal(double(r.RFStreamStartSample),a) && ...
        isequal(double(r.RFStreamEndSampleExclusive),b), ...
        'sixgr:truth:RFEndpointExecutionClockMismatch','Use the actual retained RF operator interval.');
    replays{end+1,1}=r; bounds(end+1,:)=[a b]; %#ok<AGROW>
    whole=whole && a>=first && b<=stop;
    next=min(b,stop);
end
assert(~isempty(replays) && next==stop,'sixgr:truth:RFEndpointCoverageGap', ...
    'Endpoint evidence must cover every observed sample.');
audit=struct('Source',"actual_retained_RF_endpoint_execution_only", ...
    'NodeID',id,'Endpoint',endpoint,'CaptureStartSample',first, ...
    'CaptureEndSampleExclusive',stop,'ExecutionIntervals',bounds, ...
    'WholeExecutionSegmentsOnly',whole,'ReceiverEstimatorInput',false, ...
    'AdditionalRFExecutions',0,'MissingFields',strings(1,0), ...
    'TimeVaryingFields',strings(1,0),'AppliedFlagScope', ...
    "any_covering_execution_segment_not_per_sample_observation_mutation");
summary=struct();
% Configuration/identity is copied only when identical in every executed
% interval. Deliberately exclude powers, EVM, IQ fits, phase RMS and hashes:
% equality of chunk values does not make them whole-observation statistics.
stationary=["RFImpairmentChainContract","RFEndpoint","RFProcessingMode", ...
    "RFConfigurationEpoch","RFStageOrder","RFConfiguredStageCount", ...
    "RFExecutedStageCount","RFAppliedStageCount", ...
    "InjectedCFO_Hz","InjectedTimingOffset_samples","SampleClockOffsetPpm", ...
    "PhaseNoiseAvailableBackend","PhaseNoiseTruthClassification", ...
    "PhaseNoiseApproximationReason","PhaseNoiseSeed","PhaseNoiseLevelApplied", ...
    "IQImbalanceModel","ConfiguredIQGainImbalance_dB", ...
    "ConfiguredIQPhaseImbalance_deg","ConfiguredIQImbalanceSource", ...
    "PAModel","PABackoff_dB","MutualCouplingMatrixSize", ...
    "ADCBits","ADCFullScale","ADCConventionConfigured", ...
    "ADCDitherRMSConfigured","ADCApertureJitterSecondsConfigured", ...
    "ADCINLLSBConfigured","ADCDNLLSBConfigured","ADCSeedConfigured", ...
    "DACBits","DACFullScale","AGCTargetRMS"];
for name=stationary
    [values,available,audit]=localValues(replays,name,audit);
    if ~available, continue; end
    if all(cellfun(@(v)isequaln(v,values{1}),values))
        summary.(name)=values{1};
    else
        audit.TimeVaryingFields(end+1)=name;
    end
end
flags=["CFOApplied","TimingOffsetApplied","SampleClockOffsetEnabled", ...
    "SampleClockOffsetApplied","PhaseNoiseConfigured","PhaseNoiseApplied", ...
    "IQImbalanceConfigured","IQImbalanceApplied","PAEnabled","PAApplied", ...
    "ElementRFEnabled","ElementRFApplied","MutualCouplingEnabled", ...
    "MutualCouplingApplied","AGCEnabled","AGCApplied", ...
    "ADCQuantizationApplied","ADCQuantizationExecuted", ...
    "DACQuantizationApplied","DACQuantizationExecuted","RFStrictOk","RFDisabledIdentity"];
for name=flags
    [values,available,audit]=localValues(replays,name,audit);
    if ~available, continue; end % Unknown is not false/disabled.
    assert(all(cellfun(@localBoolean,values)), ...
        'sixgr:truth:InvalidRFEndpointFlag','Executed %s must be logical or scalar 0/1.',name);
    values=cellfun(@logical,values);
    if any(name==["RFStrictOk","RFDisabledIdentity"])
        summary.(name)=all(values);
    else
        summary.(name)=any(values);
    end
end
summary.RFExecutionStatus="unavailable_incomplete_endpoint_validation";
if isfield(summary,'RFStrictOk')
    summary.RFExecutionStatus="executed_retained_sample_stream_validation_failed";
    if summary.RFStrictOk
        summary.RFExecutionStatus="executed_retained_sample_stream_validation_passed";
    end
end
for prefix=["ADC","DAC"]
    [summary,audit]=localConverter(summary,audit,replays,prefix,whole);
end
summary.RFMetadataSource=audit.Source;
summary.RFMetadataAppliedFlagScope=audit.AppliedFlagScope;
end

function [values,available,audit]=localValues(replays,name,audit)
available=all(cellfun(@(r)isfield(r,name),replays));
values={};
if available
    values=cellfun(@(r)r.(name),replays,'UniformOutput',false);
else
    audit.MissingFields=unique([audit.MissingFields name],'stable');
end
end

function yes=localBoolean(v)
yes=(islogical(v) || isnumeric(v)) && isscalar(v) && isreal(v) && ...
    isfinite(v) && any(v==[0 1]);
end

function [summary,audit]=localConverter(summary,audit,replays,prefix,whole)
for field=["ClippedSampleCount","ClippingSampleCount","ClippingRatio"]
    summary.(prefix+field)=NaN;
end
summary.(prefix+"ClippingPopulation")="unavailable";
summary.(prefix+"ClippingSource")="";
summary.(prefix+"ClippingThresholdRule")="";
summary.(prefix+"ClippingStatus")="unavailable_incomplete_converter_execution_evidence";
[executed,available,audit]=localValues(replays,prefix+"QuantizationExecuted",audit);
if ~available, return; end
assert(all(cellfun(@localBoolean,executed)),'sixgr:truth:InvalidRFEndpointFlag');
executed=cellfun(@logical,executed);
if ~any(executed)
    summary.(prefix+"ClippingStatus")="not_executed";
    return;
end
if ~all(executed)
    summary.(prefix+"ClippingStatus")="unavailable_converter_not_executed_over_entire_observation";
    return;
end
if ~whole
    summary.(prefix+"ClippingStatus")="unavailable_partial_execution_segment_requires_sample_masks";
    return;
end
names=prefix+["ClippedSampleCount","ClippingSampleCount","ClippingRatio", ...
    "ClippingStatus","ClippingPopulation","ClippingSource","ClippingThresholdRule"];
allPresent=true;
for name=names
    [~,present,audit]=localValues(replays,name,audit);
    allPresent=allPresent && present;
end
if ~allPresent, return; end
for name=names(4:end)
    values=cellfun(@(r)string(r.(name)),replays,'UniformOutput',false);
    assert(all(cellfun(@(v)isscalar(v) && ~ismissing(v),values)), ...
        'sixgr:truth:InvalidRFConverterPopulation','Converter population metadata must be scalar text.');
    if ~all(cellfun(@(v)v==values{1},values))
        audit.TimeVaryingFields(end+1)=name;
        summary.(prefix+"ClippingStatus")="unavailable_mixed_converter_population";
        return;
    end
end
if string(replays{1}.(prefix+"ClippingStatus"))~="measured"
    return; % An unmeasured population is not a measured zero.
end
for name=names(1:3)
    assert(all(cellfun(@(r)isnumeric(r.(name)) && isscalar(r.(name)) && ...
        isreal(r.(name)) && isfinite(r.(name)),replays)), ...
        'sixgr:truth:InvalidRFConverterPopulation','Converter counts and ratios must be finite scalars.');
end
clipped=cellfun(@(r)double(r.(prefix+"ClippedSampleCount")),replays);
counts=cellfun(@(r)double(r.(prefix+"ClippingSampleCount")),replays);
ratios=cellfun(@(r)double(r.(prefix+"ClippingRatio")),replays);
assert(all(clipped>=0 & clipped==fix(clipped) & clipped<=counts) && ...
    all(counts>0 & counts==fix(counts)) && sum(counts)<=flintmax && ...
    all(abs(ratios-clipped./counts)<=64*eps), ...
    'sixgr:truth:InvalidRFConverterPopulation','Clipping fractions must close against actual mask counts.');
summary.(prefix+"ClippedSampleCount")=sum(clipped);
summary.(prefix+"ClippingSampleCount")=sum(counts);
summary.(prefix+"ClippingRatio")=sum(clipped)/sum(counts);
summary.(prefix+"ClippingStatus")="measured";
summary.(prefix+"ClippingPopulation")=string(replays{1}.(prefix+"ClippingPopulation"));
summary.(prefix+"ClippingThresholdRule")=string(replays{1}.(prefix+"ClippingThresholdRule"));
summary.(prefix+"ClippingSource")="sum_of_complete_executed_converter_mask_populations";
end
