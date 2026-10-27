function measurement=bindSSBSearchMeasurementIdentity(measurement,row)
% Search-candidate identity is not a detected SSB/resource or power sample.
% Preserve legacy valid-measurement IDs consumed by power-control/filter APIs.
if string(measurement.SignalType)~="SSB", return; end
measurement.RequestedSSBOccasionIndex=NaN;
measurement.SSBSearchCaptureSHA256="";
measurement.SSBSearchCaptureStartSample=NaN;
measurement.SSBSearchCaptureEndSampleExclusive=NaN;
measurement.SSBSearchCaptureSampleRateHz=NaN;
measurement.SSBSearchIdentityStatus="unavailable_original_search_candidate_or_capture";
required=["RequestedSSBOccasionIndex","ReceiverObservationSHA256", ...
    "ObservationStartSample","ObservationEndSampleExclusive","ObservationSampleRateHz"];
if istable(row), names=string(row.Properties.VariableNames);
else, names=string(fieldnames(row)); end
if ~all(ismember(required,names)), return; end
candidate=row.RequestedSSBOccasionIndex;
first=row.ObservationStartSample; stop=row.ObservationEndSampleExclusive;
rate=row.ObservationSampleRateHz; hash=string(row.ReceiverObservationSHA256);
for value={candidate,first,stop,rate}
    v=value{1};
    if ~(isnumeric(v)&&isreal(v)&&isscalar(v)&&isfinite(v)), return; end
end
if candidate<0||candidate~=fix(candidate)||first<0||first~=fix(first)|| ...
        stop<=first||stop~=fix(stop)||rate<=0||~isscalar(hash)||ismissing(hash)|| ...
        isempty(regexp(char(hash),'^[a-fA-F0-9]{64}$','once')), return; end
measurement.RequestedSSBOccasionIndex=double(candidate);
measurement.SSBSearchCaptureSHA256=hash;
measurement.SSBSearchCaptureStartSample=double(first);
measurement.SSBSearchCaptureEndSampleExclusive=double(stop);
measurement.SSBSearchCaptureSampleRateHz=double(rate);
measurement.SSBSearchIdentityStatus="original_requested_candidate_and_received_capture";
if ~measurement.Valid && ~isfinite(measurement.ResourceId)
    % Distinguish searches sharing one capture and captures sharing one slot.
    % No received-resource identity, validity or measured value is inferred.
    capture=struct('SampleSHA256',hash,'StartSample',first, ...
        'EndSampleExclusive',stop,'SampleRateHz',rate,'ServingCell',measurement.ServingCell);
    key=sixgr.util.sha256Hex(char(jsonencode(sixgr.util.jsonSafeValue(capture))));
    measurement.MeasurementId=char(string(measurement.MeasurementId)+ ...
        "_requested_candidate_"+candidate+"_capture_"+string(key));
end
end
