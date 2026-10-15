function [summary,audit]=summarizeSharedRFEndpoint(plane,endpoint)
%SUMMARIZESHAREDRFENDPOINT Post-reception metadata from one executed endpoint.
% No YAML/configuration inference, receiver inputs, waveform regeneration or
% fitted measurements. Applied flags describe the covering stream segments;
% they do not prove sample mutation at every point of a cropped observation.
% Cropped converter populations require retained sample-indexed statistics.
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
    "DACBits","DACFullScale","DACConfiguredFullScale","DACReferenceRMS", ...
    "DACReferenceHeadroom_dB","DACReferenceREEnergy","DACReferenceNfft", ...
    "DACReferenceSubcarriers","DACReferenceTxPorts","DACReferenceDomain", ...
    "DACReferenceSource","DACReferencePayloadDependent","AGCTargetRMS", ...
    "AGCControlModel"];
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
    "MutualCouplingApplied","AGCEnabled","AGCApplied","AGCExecuted","AGCDecisionCausal", ...
    "ADCQuantizationApplied","ADCQuantizationExecuted", ...
    "DACQuantizationApplied","DACQuantizationExecuted","RFStrictOk","RFDisabledIdentity"];
for name=flags
    [values,available,audit]=localValues(replays,name,audit);
    if ~available, continue; end % Unknown is not false/disabled.
    assert(all(cellfun(@localBoolean,values)), ...
        'sixgr:truth:InvalidRFEndpointFlag','Executed %s must be logical or scalar 0/1.',name);
    values=cellfun(@logical,values);
    if any(name==["RFStrictOk","RFDisabledIdentity","AGCDecisionCausal"])
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
    [summary,audit]=localConverterError(summary,audit,replays,prefix,whole, ...
        (bounds(:,2)-bounds(:,1))*plane.Observation.NumReceiveAntennas);
    if ~whole
        [summary,audit]=localCroppedConverter(summary,audit,replays,prefix, ...
            bounds,first,stop,plane.Observation.NumReceiveAntennas);
    end
end
[summary,audit]=localAGC(summary,audit,replays,bounds,first,stop);
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

function [summary,audit]=localCroppedConverter(summary,audit,replays,prefix,bounds,first,stop,channels)
% Never use a full segment's average/count for a partial observation.
% Old captures without the actual per-sample statistics remain unavailable.
if summary.(prefix+"ClippingStatus")~="unavailable_partial_execution_segment_requires_sample_masks" || ...
        summary.(prefix+"ErrorMeasurementStatus")~="unavailable_partial_execution_segment_requires_sample_errors"
    return;
end
[traces,present,audit]=localValues(replays,prefix+"SampleEvidence",audit);
if ~present, return; end
inputEnergy=0; errorEnergy=0; clipped=0; population=0;
definition=""; domain=""; clippingPopulation=""; thresholdRule="";
for k=1:numel(traces)
    trace=traces{k}; a=bounds(k,1); b=bounds(k,2); r=replays{k};
    assert(isstruct(trace) && isscalar(trace) && ...
        all(isfield(trace,{'Contract','StartSample','EndSampleExclusive', ...
        'NumChannels','InputEnergy','ErrorEnergy','ClippedCount'})) && ...
        isequal(string(trace.Contract),"executed_converter_sample_statistics/v1") && ...
        isequal(trace.StartSample,a) && isequal(trace.EndSampleExclusive,b) && ...
        isequal(trace.NumChannels,channels), ...
        'sixgr:truth:InvalidRFConverterSampleTrace', ...
        'Retain converter sample statistics on the actual endpoint clock and channel dimensions.');
    fields=["InputEnergy","ErrorEnergy","ClippedCount"];
    for name=fields
        v=trace.(name);
        assert(isnumeric(v) && isreal(v) && iscolumn(v) && numel(v)==b-a && ...
            all(isfinite(v) & v>=0), ...
            'sixgr:truth:InvalidRFConverterSampleTrace','Sample statistics must cover the full executed segment.');
    end
    assert(all(trace.ClippedCount==fix(trace.ClippedCount) & trace.ClippedCount<=channels), ...
        'sixgr:truth:InvalidRFConverterSampleTrace','Count the executed converter mask, not clipped components twice.');
    required=prefix+["ErrorSampleCount","InputEnergy","ErrorEnergy","ErrorDefinition", ...
        "ErrorDomain","ClippedSampleCount","ClippingPopulation","ClippingThresholdRule"];
    assert(all(isfield(r,cellstr(required))), 'sixgr:truth:InvalidRFConverterSampleTrace', ...
        'Retain matching segment totals and definitions for sample-trace reconciliation.');
    total=[sum(trace.InputEnergy) sum(trace.ErrorEnergy)];
    recorded=[r.(prefix+"InputEnergy") r.(prefix+"ErrorEnergy")];
    assert(all(isfinite(recorded) & recorded>=0) && ...
        all(abs(total-recorded)<=64*eps(max(1,recorded))*max(1,b-a)) && ...
        r.(prefix+"ErrorSampleCount")==(b-a)*channels && ...
        sum(trace.ClippedCount)==r.(prefix+"ClippedSampleCount"), ...
        'sixgr:truth:InvalidRFConverterSampleTrace','Per-sample populations must close against the actual complete converter execution.');
    current=[string(r.(prefix+"ErrorDefinition")),string(r.(prefix+"ErrorDomain")), ...
        string(r.(prefix+"ClippingPopulation")),string(r.(prefix+"ClippingThresholdRule"))];
    assert(numel(current)==4 && all(~ismissing(current) & strlength(current)>0), ...
        'sixgr:truth:InvalidRFConverterSampleTrace','Measurement definitions must be explicit.');
    if k==1
        definition=current(1); domain=current(2); clippingPopulation=current(3); thresholdRule=current(4);
    else
        assert(isequal(current,[definition domain clippingPopulation thresholdRule]), ...
            'sixgr:truth:InvalidRFConverterSampleTrace','Do not pool different converter measurement planes.');
    end
    range=(max(first,a)-a+1):(min(stop,b)-a);
    inputEnergy=inputEnergy+sum(trace.InputEnergy(range));
    errorEnergy=errorEnergy+sum(trace.ErrorEnergy(range));
    clipped=clipped+sum(trace.ClippedCount(range));
    population=population+numel(range)*channels;
end
assert(population==(stop-first)*channels, 'sixgr:truth:InvalidRFConverterSampleTrace');
summary.(prefix+"ErrorSampleCount")=population;
summary.(prefix+"InputEnergy")=inputEnergy;
summary.(prefix+"ErrorEnergy")=errorEnergy;
summary.(prefix+"ErrorMeanSquare")=errorEnergy/population;
summary.(prefix+"ErrorMeasurementStatus")="measured_actual_converter_samples_cropped_to_capture";
summary.(prefix+"ErrorDefinition")=definition;
summary.(prefix+"ErrorDomain")=domain;
summary.(prefix+"ClippedSampleCount")=clipped;
summary.(prefix+"ClippingSampleCount")=population;
summary.(prefix+"ClippingRatio")=clipped/population;
summary.(prefix+"ClippingStatus")="measured";
summary.(prefix+"ClippingPopulation")=clippingPopulation;
summary.(prefix+"ClippingThresholdRule")=thresholdRule;
summary.(prefix+"ClippingSource")="actual_executed_converter_mask_counts_cropped_to_capture";
end

function [summary,audit]=localAGC(summary,audit,replays,bounds,first,stop)
for field=["AGCGain_dB","AGCGainMin_dB","AGCGainMax_dB","AGCGainIsTimeVarying","AGCGainSampleCount"]
    summary.(field)=NaN;
end
summary.AGCExecutionStatus="unavailable_incomplete_executed_AGC_evidence";
summary.AGCGainEvidenceSource="unavailable";
[executed,available,audit]=localValues(replays,"AGCExecuted",audit);
if ~available, return; end
assert(all(cellfun(@localBoolean,executed)),'sixgr:truth:InvalidRFEndpointFlag');
executed=cellfun(@logical,executed);
if ~any(executed), summary.AGCExecutionStatus="not_executed"; return; end
if ~all(executed), summary.AGCExecutionStatus="unavailable_AGC_not_executed_over_entire_observation"; return; end
[traces,available,audit]=localValues(replays,"AGCStreamTrace",audit);
if ~available, return; end
minimum=Inf; maximum=-Inf; count=0;
for k=1:numel(traces)
    trace=traces{k}; a=bounds(k,1); b=bounds(k,2);
    assert(isstruct(trace) && isscalar(trace) && ...
        all(isfield(trace,{'StartSample','EndSampleExclusive','AppliedGain_dB','ControlModel'})) && ...
        isequal(trace.StartSample,a) && isequal(trace.EndSampleExclusive,b) && ...
        isscalar(string(trace.ControlModel)) && ...
        string(trace.ControlModel)=="causal_windowed_joint_rms_attack_hold_release", ...
        'sixgr:truth:InvalidRFAGCTrace','Use the actual retained applied-gain trace on the matching receiver sample clock.');
    gain=trace.AppliedGain_dB;
    assert(isnumeric(gain) && isreal(gain) && isvector(gain) && ...
        numel(gain)==b-a && all(isfinite(gain)), ...
        'sixgr:truth:InvalidRFAGCTrace','Do not replace a sample-varying gain by the final AGC decision.');
    gain=double(gain(max(first,a)-a+1:min(stop,b)-a));
    minimum=min(minimum,min(gain)); maximum=max(maximum,max(gain)); count=count+numel(gain);
end
assert(count==stop-first,'sixgr:truth:InvalidRFAGCTrace','Applied gain must cover each received time sample once.');
summary.AGCGainMin_dB=minimum; summary.AGCGainMax_dB=maximum;
summary.AGCGainIsTimeVarying=minimum~=maximum;
summary.AGCGainSampleCount=count;
summary.AGCGainEvidenceSource="actual_applied_gain_trace_cropped_to_receiver_capture_not_next_gain_decision";
summary.AGCExecutionStatus="executed_time_varying_sample_gain";
if minimum==maximum
    summary.AGCGain_dB=minimum;
    summary.AGCExecutionStatus="executed_stationary_sample_gain";
end
end

function [summary,audit]=localConverterError(summary,audit,replays,prefix,whole,expectedCount)
for field=["ErrorSampleCount","InputEnergy","ErrorEnergy","ErrorMeanSquare"]
    summary.(prefix+field)=NaN;
end
summary.(prefix+"ErrorDefinition")="unavailable";
summary.(prefix+"ErrorDomain")="unavailable";
summary.(prefix+"ErrorMeasurementStatus")="unavailable_incomplete_converter_error_evidence";
[executed,available,audit]=localValues(replays,prefix+"QuantizationExecuted",audit);
if ~available, return; end
assert(all(cellfun(@localBoolean,executed)),'sixgr:truth:InvalidRFEndpointFlag');
executed=cellfun(@logical,executed);
if ~any(executed), summary.(prefix+"ErrorMeasurementStatus")="not_executed"; return; end
if ~all(executed), summary.(prefix+"ErrorMeasurementStatus")="unavailable_converter_not_executed_over_entire_observation"; return; end
if ~whole
    summary.(prefix+"ErrorMeasurementStatus")="unavailable_partial_execution_segment_requires_sample_errors";
    return;
end
names=prefix+["ErrorSampleCount","InputEnergy","ErrorEnergy","ErrorMeanSquare", ...
    "ErrorDefinition","ErrorDomain","ErrorMeasurementStatus"];
for name=names
    [~,available,audit]=localValues(replays,name,audit);
    if ~available, return; end
end
for name=names(5:end)
    values=cellfun(@(r)string(r.(name)),replays,'UniformOutput',false);
    assert(all(cellfun(@(v)isscalar(v) && ~ismissing(v) && v==values{1},values)), ...
        'sixgr:truth:InvalidRFConverterErrorPopulation','Do not pool different converter error definitions.');
end
if string(replays{1}.(prefix+"ErrorMeasurementStatus"))~="measured_actual_converter_samples", return; end
for name=names(1:4)
    assert(all(cellfun(@(r)isnumeric(r.(name)) && isscalar(r.(name)) && ...
        isreal(r.(name)) && isfinite(r.(name)) && r.(name)>=0,replays)), ...
        'sixgr:truth:InvalidRFConverterErrorPopulation','Converter energies/counts require finite nonnegative measurements.');
end
count=cellfun(@(r)double(r.(prefix+"ErrorSampleCount")),replays);
input=cellfun(@(r)double(r.(prefix+"InputEnergy")),replays);
energy=cellfun(@(r)double(r.(prefix+"ErrorEnergy")),replays);
mse=cellfun(@(r)double(r.(prefix+"ErrorMeanSquare")),replays);
assert(isequal(count,expectedCount) && all(count>0 & count==fix(count)) && sum(count)<=flintmax && ...
    all(abs(energy./count-mse)<=64*eps(max(1,mse))), ...
    'sixgr:truth:InvalidRFConverterErrorPopulation','Converter MSE must close on its actual sample population.');
summary.(prefix+"ErrorSampleCount")=sum(count);
summary.(prefix+"InputEnergy")=sum(input);
summary.(prefix+"ErrorEnergy")=sum(energy);
summary.(prefix+"ErrorMeanSquare")=sum(energy)/sum(count);
summary.(prefix+"ErrorMeasurementStatus")="measured_complete_executed_converter_sample_population";
summary.(prefix+"ErrorDefinition")=string(replays{1}.(prefix+"ErrorDefinition"));
summary.(prefix+"ErrorDomain")=string(replays{1}.(prefix+"ErrorDomain"));
end
