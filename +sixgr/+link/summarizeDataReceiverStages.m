function row = summarizeDataReceiverStages(rx, direction)
%SUMMARIZEDATARECEIVERSTAGES Descriptive summaries of returned receiver evidence.
% No CRC, allocation, configured SNR or channel-estimate magnitude is a
% generic detector. This projection never changes receiver/decode usability.
% With no inputs it supplies a typed unavailable schema, not an executed row.
row = struct('DetectionApplicable',NaN,'DetectionAttempted',NaN, ...
    'DetectionSuccess',NaN,'DetectionUsable',NaN,'DetectionStatus',"receiver_result_not_retained", ...
    'DetectionSource',"",'MeasurementApplicable',NaN, ...
    'MeasurementAttempted',NaN,'MeasurementUsable',NaN, ...
    'MeasurementStatus',"receiver_result_not_retained",'MeasurementSource',"", ...
    'MeasurementDefinition',"",'MeasurementValue_dB',NaN, ...
    'MeasurementValueRole',"",'MeasurementValueStatus',"", ...
    'MeasurementSummarySource',"",'MeasurementAttemptKnown',false);
if nargin==0, return; end
assert(isstruct(rx) && isscalar(rx) && any(string(direction)==["DL","UL"]), ...
    'sixgr:link:DataStageSummaryInput','Require the original directional receiver result.');
row.DetectionApplicable=0;
row.DetectionAttempted=0;
row.DetectionSuccess=0;
row.DetectionUsable=0;
row.DetectionStatus="not_applicable_scheduled_data_no_generic_detector";
row.DetectionSource="scheduled_data_receiver_no_generic_detection_contract";
detectorFields=["DetectionApplicable","DetectionAttempted","DetectionSuccess","DetectionUsable", ...
    "DetectionStatus","DetectionSource"];
if any(isfield(rx,cellstr(detectorFields)))
    % A partial explicit contract must stay partial, not borrow N/A defaults.
    row.DetectionApplicable=NaN; row.DetectionAttempted=NaN;
    row.DetectionSuccess=NaN; row.DetectionUsable=NaN;
    row.DetectionStatus="explicit_receiver_detection_contract";
    row.DetectionSource="";
    row=localCopy(row,rx,detectorFields);
end
measurementFields=["MeasurementApplicable","MeasurementAttempted","MeasurementUsable", ...
    "MeasurementStatus","MeasurementSource","MeasurementDefinition", ...
    "MeasurementValue_dB","MeasurementValueRole","MeasurementValueStatus"];
if any(isfield(rx,cellstr(measurementFields)))
    row=localCopy(row,rx,measurementFields);
    row.MeasurementSummarySource="explicit_receiver_measurement_contract";
    row.MeasurementAttemptKnown=isfinite(row.MeasurementAttempted);
    return;
end
% Use only the post-equalization subsection of the existing validator. Pass
% its exact retained scalar operands, not Hest/LLR arrays for a second scan.
% Its broader inferred stage flags are NOT copied into the trial.
postEq=struct();
for name=["PostEqSINR_dB","PostEqSINRSource","PostEqSINRValueRole", ...
        "PostEqSINRValueStatus","SINRComputationMethod"]
    if isfield(rx,name), postEq.(name)=rx.(name); end
end
if string(direction)=="DL"
    check=sixgr.phy.dl.validatePDSCHReceiverEvidence(postEq,'StrictMode',false);
else
    check=sixgr.phy.ul.validatePUSCHReceiverEvidence(postEq,'StrictMode',false);
end
available=localTrue(rx,'PostEqSINRAvailable') && ...
    localTrue(rx,'PostEqSINRReceiverDerived') && check.PostEqSINRAvailable && ...
    check.PostEqSINRReceiverDerived;
row.MeasurementApplicable=1;
row.MeasurementUsable=double(available);
row.MeasurementDefinition="receiver_post_equalization_SINR_only_not_all_receiver_measurements";
row.MeasurementSummarySource="qualified_original_receiver_post_equalization_SINR";
row.MeasurementStatus="qualified_post_equalization_SINR_unavailable_attempt_unknown";
row.MeasurementSource=string(sixgr.util.structGet(rx,'PostEqSINRSource',""));
row.MeasurementValueRole=string(sixgr.util.structGet(rx,'PostEqSINRValueRole',""));
row.MeasurementValueStatus=string(sixgr.util.structGet(rx,'PostEqSINRValueStatus',""));
if available
    row.MeasurementAttempted=1;
    row.MeasurementAttemptKnown=true;
    row.MeasurementValue_dB=double(rx.PostEqSINR_dB);
    row.MeasurementStatus="qualified_receiver_post_equalization_SINR_available";
end
end

function row=localCopy(row,rx,names)
for name=names
    if ~isfield(rx,name), continue; end
    value=rx.(name);
    if isnumeric(row.(name))
        assert((isnumeric(value)||islogical(value)) && isscalar(value), ...
            'sixgr:link:DataStageSummaryValue','%s must be a scalar.',name);
        value=double(value);
        if endsWith(name,["Applicable","Attempted","Usable","Success"])
            assert(isnan(value)||value==0||value==1, ...
                'sixgr:link:DataStageSummaryValue','%s must be unknown, false or true.',name);
        end
    else
        value=string(value);
        assert(isscalar(value),'sixgr:link:DataStageSummaryValue','%s must be scalar text.',name);
    end
    row.(name)=value;
end
end

function tf=localTrue(rx,name)
value=sixgr.util.structGet(rx,name,NaN);
tf=(isnumeric(value)||islogical(value)) && isscalar(value) && ...
    isfinite(double(value)) && double(value)==1;
end
