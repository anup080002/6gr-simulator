function authority = resolveReceiverTrackingAuthority(raw, consumerDirection)
%RESOLVERECEIVERTRACKINGAUTHORITY Validate supplied receiver tracking metadata.
% This is an implementation boundary, not authentication of a measurement.
% A processed estimate needs original direction/source labels. No direction,
% evidence source, sample origin or availability timestamp is manufactured.
% Causal delivery/epoch checks remain with the runtime state owner; these
% receiver structs do not carry a complete observation/availability clock.
arguments
    raw (1,1) struct
    consumerDirection {mustBeTextScalar}
end
consumerDirection=upper(strtrim(string(consumerDirection)));
assert(any(consumerDirection==["DL","UL"]), ...
    'sixgr:phy:rx:InvalidTrackingAuthority','Consumer direction must be DL or UL.');
authority=struct('Processed',false,'MeasurementDirection',"", ...
    'ConsumerDirection',consumerDirection,'DirectionCompatible',false, ...
    'Source',"unavailable_receiver_tracking_state", ...
    'Status',"unavailable_receiver_tracking_authority",'Reason',"no_processed_tracking_state");
authority.Processed=localAlias(raw,["TRSProcessed","RuntimeTRSProcessed"],"flag",false);
if ~authority.Processed, return; end
authority.MeasurementDirection=localAlias(raw, ...
    ["TrackingMeasurementDirection","RuntimeTRSMeasurementDirection"],"direction","");
declaredConsumer=localAlias(raw, ...
    ["TrackingConsumerDirection","RuntimeReceiverTrackingConsumerDirection"],"direction","");
authority.Source=localAlias(raw, ...
    ["RuntimeTRSRuntimeEvidenceSource","RuntimeEvidenceSource","TrackingEstimateSource"],"text","");
assert(strlength(authority.MeasurementDirection)>0 && strlength(declaredConsumer)>0 && ...
    strlength(authority.Source)>0,'sixgr:phy:rx:MissingTrackingAuthority', ...
    'Processed tracking requires original measurement/consumer directions and evidence source.');
authority.ConsumerDirection=declaredConsumer;
compatible=authority.MeasurementDirection==consumerDirection && declaredConsumer==consumerDirection;
declaredCompatible=localAlias(raw, ...
    ["TrackingDirectionCompatible","RuntimeReceiverTrackingDirectionCompatible"],"flag",compatible);
% Explicit false can withhold an otherwise matching state. Explicit true
% never overrides the original measured/consumer direction mismatch.
authority.DirectionCompatible=compatible && declaredCompatible;
authority.Reason=localAlias(raw, ...
    ["TrackingAuthorityReason","RuntimeReceiverTrackingAuthorityReason"],"text","");
declaredStatus=localAlias(raw, ...
    ["TrackingAuthorityStatus","RuntimeReceiverTrackingAuthorityStatus"],"text","");
if authority.DirectionCompatible
    assert(~startsWith(lower(declaredStatus),"rejected"), ...
        'sixgr:phy:rx:ConflictingTrackingAuthority','Rejected authority cannot authorize an estimate.');
    authority.Status="authorized_same_receiver_direction";
    authority.Reason="";
else
    authority.Status="rejected_cross_direction_receiver_state";
    if strlength(authority.Reason)==0
        authority.Reason="measurement_and_consumer_receiver_directions_differ";
    end
end
% Validate existing availability/estimate aliases before permissive legacy
% numeric readers can coerce text, vectors or conflicting aliases. NaN is
% retained as unavailable; an available value must be finite and original.
timingAvailable=localAlias(raw, ...
    ["TimingEstimateAvailable","RuntimeTRSTimingEstimateAvailable"],"flag",false);
timing=localAlias(raw, ...
    ["TimingEstimate_samples","RuntimeTRSTimingEstimate_samples","EstimatedTimingOffset_samples"],"number",NaN);
assert(~timingAvailable || isfinite(timing),'sixgr:phy:rx:InvalidTrackingAuthority', ...
    'Available timing requires an original finite scalar estimate.');
cfoAvailable=localAlias(raw,["CFOEstimateAvailable","RuntimeTRSCFOEstimateAvailable"],"flag",false);
cfo=localAlias(raw,["EstimatedCFO_Hz","RuntimeTRSEstimatedCFO_Hz","EstimatedCFO_PreCorrection_Hz"],"number",NaN);
common=localAlias(raw,["EstimatedCommonFrequency_Hz","RuntimeTRSEstimatedCommonFrequency_Hz","EstimatedCommonPhaseFrequency_Hz"],"number",NaN);
oscillator=localAlias(raw,["EstimatedOscillatorCFO_Hz","RuntimeTRSEstimatedOscillatorCFO_Hz"],"number",NaN);
assert(~cfoAvailable || any(isfinite([cfo common oscillator])), ...
    'sixgr:phy:rx:InvalidTrackingAuthority', ...
    'Available frequency tracking requires an original finite scalar estimate.');
localAlias(raw,["FrequencyEstimateDomain","RuntimeTRSFrequencyEstimateDomain"],"text","");
localAlias(raw,["KnownTimingDelay_samples","RuntimeKnownTimingDelay_samples"],"number",NaN);
age=localAlias(raw,["TRSAgeSlots","RuntimeTRSAgeSlots"],"age",NaN);
update=localAlias(raw,["TRSTrackingUpdateTime_s","RuntimeTRSTrackingUpdateTime_s"],"number",NaN);
assert((isnan(age) || age>=0) && (isnan(update) || update>=0), ...
    'sixgr:phy:rx:InvalidTrackingAuthority','Tracking age/update time cannot be negative.');
end

function value=localAlias(raw,names,kind,missing)
value=missing;
found=false;
for name=names
    if ~isfield(raw,name), continue; end
    original=raw.(name);
    switch kind
        case {"text","direction"}
            assert((ischar(original) && (isrow(original) || isempty(original))) || ...
                (isstring(original) && isscalar(original) && ~ismissing(original)), ...
                'sixgr:phy:rx:InvalidTrackingAuthority','Tracking field %s must be scalar text.',name);
            candidate=strtrim(string(original));
            if kind=="direction"
                candidate=upper(candidate);
                assert(any(candidate==["DL","UL"]),'sixgr:phy:rx:InvalidTrackingAuthority', ...
                    'Tracking direction %s must be DL or UL.',name);
            end
        case "flag"
            assert((isnumeric(original) || islogical(original)) && isreal(original) && ...
                isscalar(original) && any(original==[0 1]), ...
                'sixgr:phy:rx:InvalidTrackingAuthority','Tracking field %s must be scalar logical 0/1.',name);
            candidate=logical(original);
        otherwise
            assert(isnumeric(original) && isreal(original) && isscalar(original) && ...
                (isfinite(original) || isnan(original) || (kind=="age" && original==Inf)), ...
                'sixgr:phy:rx:InvalidTrackingAuthority','Tracking field %s must be a real numeric scalar.',name);
            candidate=double(original);
    end
    if found
        assert(isequaln(candidate,value),'sixgr:phy:rx:ConflictingTrackingAuthority', ...
            'Tracking aliases for %s disagree.',names(1));
    else
        value=candidate;
        found=true;
    end
end
end
