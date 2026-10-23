function T = collectCSIReportLatency(reports, measurements)
%COLLECTCSIREPORTLATENCY Post-reception audit, never scheduler/receiver input.
% Durations are simulated sample-clock intervals, not CPU time or a configured
% reporting period. The CSI reference-resource slot is not the UE's private
% observation slot. Bind that observation only through the retained UE audit.
arguments
    reports table
    measurements table
end
prototype=struct('ReportIdentity',"",'UEIndex',NaN,'RNTI',NaN, ...
    'ServingCell',NaN,'CSIReportConfigID',"",'CSIConfigurationEpoch',NaN, ...
    'CSIMeasurementID',"",'CSIMeasurementDigest',"", ...
    'SweepPointIndex',NaN,'ConfiguredSNR_dB',NaN,'ExecutionID',"", ...
    'ReportSourceRow',NaN,'MeasurementSourceRow',NaN, ...
    'MeasurementSourceSlot',NaN,'ConfiguredReferenceSlot',NaN, ...
    'DueSlot',NaN,'DeliveredSlot',NaN,'UCITransport',"", ...
    'ObservationID',"",'ClockDomain',"",'ClockEpoch',NaN,'SampleRateHz',NaN, ...
    'MeasurementStartSample',NaN,'MeasurementEndSampleExclusive',NaN, ...
    'MeasurementAvailableAtSample',NaN,'UCIStartSample',NaN, ...
    'UCIEndSampleExclusive',NaN,'ReportAvailableAtSample',NaN, ...
    'MeasurementCompletionDelay_ms',NaN,'MeasurementAvailableToUCIObservationEnd_ms',NaN, ...
    'UCIObservationDuration_ms',NaN,'UCICompletionDelay_ms',NaN, ...
    'MeasurementEndToDelivery_ms',NaN,'MeasurementAvailableToDelivery_ms',NaN, ...
    'LatencyAvailable',false,'LatencyStatus',"not_evaluated", ...
    'MeasurementSourceArtifact',"air_interface/csv/csi_rs_trials.csv", ...
    'ReportSourceArtifact',"air_interface/csv/received_csi_reports.csv");
T=struct2table(repmat(prototype,0,1));
if isempty(reports), return; end
[slots,authority]=sixgr.report.csiReportMeasurementAuditSlots(reports);
for k=1:height(reports)
    r=table2struct(reports(k,:)); out=prototype; out.ReportSourceRow=k;
    for field=["ReportIdentity","UEIndex","RNTI","ServingCell", ...
            "CSIReportConfigID","CSIConfigurationEpoch","SweepPointIndex", ...
            "ConfiguredSNR_dB","ExecutionID","DueSlot","DeliveredSlot","ObservationID"]
        if isfield(r,field), out.(field)=r.(field); end
    end
    out.ConfiguredReferenceSlot=number(r,'CSIReferenceSlot');
    out.UCITransport=string(sixgr.util.structGet(r,'CSIUCIChannel',""));
    out.LatencyStatus="not_delivered";
    decoded=sixgr.util.structGet(r,'CSIUCIDecodeOk',false);
    if (isnumeric(decoded) || islogical(decoded)) && isscalar(decoded) && decoded==1 && ...
            string(sixgr.util.structGet(r,'DeliveryStatus',""))=="delivered_to_runtime_scheduler"
        out=measure(out,r,slots(k),authority(k),measurements);
    end
    T=[T;struct2table(out,'AsArray',true)]; %#ok<AGROW>
end
end

function out=measure(out,r,slot,authority,measurements)
out.LatencyStatus="missing_identity_bound_UE_measurement_audit";
if ~isfinite(slot) || ~startsWith(authority,"posthoc_"), return; end
audit=jsondecode(string(r.UEReferenceRecordJSON)); % identity checked above
if ~isfield(audit,'ServingCell') || number(audit,'ServingCell')~=number(r,'ServingCell')
    out.LatencyStatus="mismatched_UE_audit_serving_cell"; return;
end
out.MeasurementSourceSlot=slot;
req=["Slot","UEIndex","RNTI","ObservationStartSample", ...
    "ObservationEndSampleExclusive","ObservationSampleRateHz", ...
    "ResultAvailableAtSample","MeasurementClockEpoch","MeasurementClockDomain", ...
    "CSIReportConfigID","CSIConfigurationEpoch","CSIMeasurementID","CSIMeasurementDigest"];
out.LatencyStatus="missing_CSI_receiver_clock";
if ~all(ismember(req,string(measurements.Properties.VariableNames))), return; end
out.LatencyStatus="missing_exact_UE_measurement_identity";
for field=["CSIMeasurementID","CSIMeasurementDigest"]
    value=string(sixgr.util.structGet(audit,field,""));
    if ~isscalar(value) || ismissing(value) || strlength(strtrim(value))==0, return; end
    out.(field)=value;
end
mask=measurements.Slot==slot & measurements.UEIndex==r.UEIndex & measurements.RNTI==r.RNTI;
mask=mask & string(measurements.CSIReportConfigID)==string(audit.CSIReportConfigID) & ...
    measurements.CSIConfigurationEpoch==audit.CSIConfigurationEpoch & ...
    string(measurements.CSIMeasurementID)==out.CSIMeasurementID & ...
    string(measurements.CSIMeasurementDigest)==out.CSIMeasurementDigest;
if ismember("CellID",string(measurements.Properties.VariableNames))
    mask=mask & measurements.CellID==r.ServingCell;
end
% Retain population identities when a joint sweep is supplied. Never join
% an identically numbered slot from another point/configuration/receiver.
for field=["ServingCell","SweepPointIndex","ConfiguredSNR_dB","ExecutionID"]
    if isfield(r,field) && ismember(field,string(measurements.Properties.VariableNames))
        mask=mask & measurements.(field)==r.(field);
    end
end
% Select the retained UE sample-clock instance before requiring uniqueness.
% Reused observation IDs in a different execution epoch must not collide.
if isfinite(number(audit,'MeasurementClockEpoch'))
    mask=mask & measurements.MeasurementClockEpoch==number(audit,'MeasurementClockEpoch');
end
hit=find(mask);
if isempty(hit), out.LatencyStatus="missing_matching_CSI_observation"; return; end
assert(isscalar(hit),'sixgr:report:CSILatencyAmbiguousObservation', ...
    'CSI latency requires one exact observation, not the first same-slot candidate.');
m=table2struct(measurements(hit,:));
out.MeasurementSourceRow=hit;
ueClock=[number(audit,'MeasurementAvailableAtSample'),number(audit,'MeasurementClockEpoch')];
rxClock=[number(r,'AvailableAtSample'),number(r,'ReceiverClockEpoch'), ...
    number(r,'ObservationStartSample'),number(r,'ObservationEndSampleExclusive'), ...
    number(r,'ObservationSampleRateHz')];
if any(~isfinite([ueClock rxClock]))
    out.LatencyStatus="missing_independent_sample_clock_operands"; return;
end
domain="shared_receiver_sample_clock/v1";
assert(string(sixgr.util.structGet(audit,'MeasurementClockDomain',""))==domain && ...
    string(sixgr.util.structGet(r,'ReceiverClockDomain',""))==domain && ...
    string(m.MeasurementClockDomain)==domain && ...
    ueClock(2)==m.MeasurementClockEpoch && rxClock(2)==m.MeasurementClockEpoch && ...
    ueClock(1)==m.ResultAvailableAtSample && rxClock(5)==m.ObservationSampleRateHz, ...
    'sixgr:report:CSILatencyClockMismatch', ...
    'UE and gNB observations must share the executed sample rate/epoch and retained completion.');
times=[m.ObservationStartSample,m.ObservationEndSampleExclusive, ...
    m.ResultAvailableAtSample,rxClock(3),rxClock(4),rxClock(1)];
assert(all(isfinite(times)) && all(times>=0 & times==fix(times)) && ...
    times(2)>times(1) && times(3)>=times(2) && times(5)>=times(3) && ...
    times(5)>times(4) && times(6)>=times(5) && ...
    isfinite(rxClock(5)) && rxClock(5)>0, ...
    'sixgr:report:CSILatencyNoncausalClock', ...
    'Measurement completion, UCI capture and report availability must be causal.');
out.ClockDomain=domain; out.ClockEpoch=rxClock(2); out.SampleRateHz=rxClock(5);
out.MeasurementStartSample=times(1); out.MeasurementEndSampleExclusive=times(2);
out.MeasurementAvailableAtSample=times(3); out.UCIStartSample=times(4);
out.UCIEndSampleExclusive=times(5); out.ReportAvailableAtSample=times(6);
scale=1000/out.SampleRateHz;
out.MeasurementCompletionDelay_ms=(times(3)-times(2))*scale;
% A capture may include receiver pre-roll. Do not call its start an on-air
% UCI transmit timestamp, or reject legitimate overlapping capture windows.
out.MeasurementAvailableToUCIObservationEnd_ms=(times(5)-times(3))*scale;
out.UCIObservationDuration_ms=(times(5)-times(4))*scale;
out.UCICompletionDelay_ms=(times(6)-times(5))*scale;
out.MeasurementEndToDelivery_ms=(times(6)-times(2))*scale;
out.MeasurementAvailableToDelivery_ms=(times(6)-times(3))*scale;
out.LatencyAvailable=true;
out.LatencyStatus="measured_simulated_sample_clock_posthoc_join_not_UE_control_information";
end

function value=number(s,field)
value=NaN;
if isfield(s,field) && isnumeric(s.(field)) && isscalar(s.(field))
    value=double(s.(field));
end
end
