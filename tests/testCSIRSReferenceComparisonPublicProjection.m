function [ok,result]=testCSIRSReferenceComparisonPublicProjection()
% Declared publication-boundary fixtures, not physical accuracy evidence.
setup6GRSimToolkit('Verbose',false);
folder=fullfile(pwd,'results','validation','csirs_reference_public_projection', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
assert(~isfolder(folder),'Never overwrite retained evidence.');
sixgr.util.ensureFolder(folder);
source=table([1;1;1],[46;46;46],[2;2;3],[7;7;9], ...
    'VariableNames',{'SFN','Slot','UEIndex','ResourceID'});
source.Frame=[2;2;2];
source.RunID=["declared_a";"declared_b";"declared_b"];
source.ReceiverID=["ue2";"ue2";"ue3"];
source.ReceiverWindowID=["declared_window_a";"declared_window_b";"declared_window_c"];
source.ReceiverObservationSHA256=repmat("",3,1);
source.ObservationStartSample=[100;200;300];
source.ObservationEndSampleExclusive=[150;250;350];
source.ObservationSampleRateHz=repmat(30.72e6,3,1);
source.MeasurementSelectedResourceOrdinal=[1;1;2];
source.MeasurementReceiveAntennaIndex1Based=[1;2;NaN]; % RSRP selection.
source.ReferenceMeasuredSINR_dB=[4;Inf;NaN];
source.ReferenceMeasuredSINRStatus=["available";"positive_signal_zero_disturbance";"nonpositive_signed_estimate"];
source.ReferenceMeasuredSINRSource=repmat("declared_received_reference_fixture",3,1);
source.ReferenceSINRMeasurementJSON=strings(3,1);
source.CSIRSEmittedPowerComparisonEvidenceJSON=strings(3,1);
source.CSIRSEmittedPowerComparisonEvidenceSHA256=strings(3,1);
source.CSIRSEmittedSINRComparisonEvidenceJSON=strings(3,1);
source.CSIRSEmittedSINRComparisonEvidenceSHA256=strings(3,1);
for k=1:3
    measured=struct('Scope',"declared_metadata_only",'ReceiveBranch1Based',3-k, ...
        'OriginalRSRPReceiveBranch1Based',source.MeasurementReceiveAntennaIndex1Based(k), ...
        'RatioToken',["finite";"+Inf";"unavailable_nonpositive"]);
    source.ReferenceSINRMeasurementJSON(k)=string(jsonencode(measured));
    evidence=struct('Scope',"declared_metadata_only",'ResourceID',source.ResourceID(k), ...
        'ReceiverWindowID',source.ReceiverWindowID(k),'OriginalRow',k, ...
        'StandardizedAccuracyQualified',false,'StatisticallyQualified',false);
    source.CSIRSEmittedPowerComparisonEvidenceJSON(k)=string(jsonencode(evidence));
    evidence.Kind="SINR";
    source.CSIRSEmittedSINRComparisonEvidenceJSON(k)=string(jsonencode(evidence));
    source.CSIRSEmittedPowerComparisonEvidenceSHA256(k)=sixgr.util.sha256Hex( ...
        char(source.CSIRSEmittedPowerComparisonEvidenceJSON(k)));
    source.CSIRSEmittedSINRComparisonEvidenceSHA256(k)=sixgr.util.sha256Hex( ...
        char(source.CSIRSEmittedSINRComparisonEvidenceJSON(k)));
    source.ReceiverObservationSHA256(k)=sixgr.util.sha256Hex(char(source.ReceiverWindowID(k)));
end
for prefix=["CSIRSEmittedPowerComparison","CSIRSEmittedSINRComparison"]
    source.(prefix+"Available")=[true;true;false];
    source.(prefix+"Status")=["declared_comparison";"declared_zero_disturbance";"declared_unavailable"];
    source.(prefix+"Source")=repmat("declared_original_receipt",3,1);
    source.(prefix+"ReportedError_dB")=[0.25;NaN;NaN];
    source.(prefix+"SelectedColumnError_dB")=[0.5;NaN;NaN];
    source.(prefix+"StandardizedAccuracyQualified")=false(3,1);
end
source.CSIRSEmittedPowerComparisonUnit=repmat("relative_to_unit_occupied_RE_Es",3,1);
% A fixed-linear port model is a SEPARATE diagnostic, not an independent
% unique attribution of the actual nonlinear multiport waveform. These
% declared receipts exercise publication only; no model/RF was executed.
prefix="CSIRSLinearPortModelComparison";
source.(prefix+"Available")=[true;true;false];
source.(prefix+"Status")=["declared_model_comparison";"declared_model_comparison";"unavailable_malformed_original_receipt"];
source.(prefix+"Source")=repmat("declared_fixed_linear_model_metadata_fixture",3,1);
source.(prefix+"EvidenceJSON")=strings(3,1);
source.(prefix+"EvidenceSHA256")=strings(3,1);
source.(prefix+"ErrorIdentifier")=["";"";"declared:MalformedOriginalReceipt"];
source.(prefix+"Unit")=repmat("relative_to_unit_occupied_RE_Es",3,1);
source.(prefix+"ReferencePlane")=repmat("declared_model_internal_element_plane",3,1);
source.(prefix+"Scope")=repmat("declared_fixed_linear_model_not_unique_nonlinear_port_truth",3,1);
source.(prefix+"ResourceCount")=[2;2;0];
source.(prefix+"SelectedResourceID")=[7;7;NaN];
source.(prefix+"ReportedPowerError_dB")=[1.25;2.25;NaN];
source.(prefix+"SelectedColumnPowerError_dB")=[1.5;2.5;NaN];
% Different disturbance operators do not define a SINR accuracy error.
% Keep their diagnostic difference without manufacturing compatibility.
source.(prefix+"ReportedSINRError_dB")=nan(3,1);
source.(prefix+"SelectedColumnSINRError_dB")=nan(3,1);
source.(prefix+"ReportedSINRLogRatioDifference_dB")=[-3.25;-4.25;NaN];
source.(prefix+"SelectedColumnSINRLogRatioDifference_dB")=[-3.5;-4.5;NaN];
source.(prefix+"SINREstimandCompatible")=false(3,1);
source.(prefix+"SINREstimandCompatibilityStatus")=["incompatible";"not_established";"not_evaluated"];
source.(prefix+"SINREstimandCompatibilityReason")=["declared_different_operators";"declared_signal_operator_unproved";"malformed_receipt"];
% Operator-matched CDM diagnostics are separate from both the raw-grid
% comparison and standards accuracy. Their CSI-IM denominator is observed,
% shared evidence, never promoted to an independent reference by projection.
source.(prefix+"CDMOperatorMatchedModelAvailable")=[true;false;false];
source.(prefix+"CDMStatus")=["declared_matched_model";"unavailable_no_CDM_receipt";"unavailable_bad_receipt"];
source.(prefix+"CDMDenominatorIndependentlyReferenced")=false(3,1);
for suffix=["CDMReportedPowerDifference_dB","CDMSelectedColumnPowerDifference_dB", ...
        "CDMReportedSINRLogRatioDifference_dB","CDMSelectedColumnSINRLogRatioDifference_dB"]
    source.(prefix+suffix)=[.125;NaN;NaN];
end
for suffix=["UniqueNonlinearPortAttributionQualified","StandardizedAccuracyQualified","HardwareQualified"]
    source.(prefix+suffix)=false(3,1);
end
for k=1:2
    model=struct('Scope',source.(prefix+"Scope")(k),'OriginalRow',k, ...
        'ReceiverWindowID',source.ReceiverWindowID(k), ...
        'OriginalRSRPSelectedColumn1',source.MeasurementReceiveAntennaIndex1Based(k), ...
        'OriginalSINRSelectedColumn1',3-k, ...
        'SignedCrossEnergy',[-.75 .25], ...
        'UniqueNonlinearPortAttributionQualified',false, ...
        'StandardizedAccuracyQualified',false,'HardwareQualified',false);
    source.(prefix+"EvidenceJSON")(k)=string(jsonencode(model));
    source.(prefix+"EvidenceSHA256")(k)=sixgr.util.sha256Hex(char(source.(prefix+"EvidenceJSON")(k)));
end
% Malformed evidence is retained for diagnosis but MUST NOT gain availability
% just because it survives projection or has a content hash.
source.(prefix+"EvidenceJSON")(3)="{malformed declared original receipt";
source.(prefix+"EvidenceSHA256")(3)=sixgr.util.sha256Hex(char(source.(prefix+"EvidenceJSON")(3)));
snapshot=source; randomBefore=rng;
p=project(source);
names=string(source.Properties.VariableNames);
retained=names(names~="RunID" & names~="UEIndex" & names~="ResourceID" & names~="Slot");
for name=retained
    assert(ismember(name,string(p.Properties.VariableNames))&&isequaln(p.(name),source.(name)), ...
        'Public CSI projection lost or changed original %s.',name);
end
assert(height(p)==3&&isequal(p.SourceRunID,source.RunID)&& ...
    isequal(p.UEId,source.UEIndex)&&isequal(p.ResourceId,source.ResourceID)&& ...
    isequal(p.Slot,source.Slot),'Do not collapse distinct observations sharing slot/resource.');
assert(isinf(p.ReferenceMeasuredSINR_dB(2))&&isnan(p.ReferenceMeasuredSINR_dB(3)));
assert(~any(p.CSIRSEmittedPowerComparisonStandardizedAccuracyQualified) && ...
    ~any(p.CSIRSEmittedSINRComparisonStandardizedAccuracyQualified));
assert(~any(p.(prefix+"UniqueNonlinearPortAttributionQualified"))&& ...
    ~any(p.(prefix+"StandardizedAccuracyQualified"))&&~any(p.(prefix+"HardwareQualified"))&& ...
    ~p.(prefix+"Available")(3)&&isnan(p.(prefix+"ReportedPowerError_dB")(3)));
assert(~isequaln(p.(prefix+"ReportedPowerError_dB"),p.CSIRSEmittedPowerComparisonReportedError_dB), ...
    'Model diagnostic errors must not replace original isolated-port comparisons.');

% Actual writer/reader boundary preserves opaque JSON and its original hash.
original=fullfile(folder,'original_declared_csirs_rows.csv');
sixgr.util.csvWriteTable(original,source,'PreserveSchema',true,'RoundTripNumericText',true);
originalHash=string(sixgr.util.sha256File(original));
imported=sixgr.util.csvReadTable(original,'TextType','string');
published=project(imported);
output=fullfile(folder,'csi_rs_runtime_event_table.csv');
sixgr.util.csvWriteTable(output,published,'PreserveSchema',true,'RoundTripNumericText',true);
roundtrip=sixgr.util.csvReadTable(output,'TextType','string');
for name=["ReferenceSINRMeasurementJSON","CSIRSEmittedPowerComparisonEvidenceJSON", ...
        "CSIRSEmittedPowerComparisonEvidenceSHA256","CSIRSEmittedSINRComparisonEvidenceJSON", ...
        "CSIRSEmittedSINRComparisonEvidenceSHA256",prefix+"EvidenceJSON",prefix+"EvidenceSHA256", ...
        prefix+"Status",prefix+"Scope",prefix+"ReferencePlane",prefix+"ErrorIdentifier", ...
        prefix+"SINREstimandCompatibilityStatus",prefix+"SINREstimandCompatibilityReason", ...
        prefix+"CDMStatus", ...
        "ReceiverWindowID","ReceiverObservationSHA256"]
    assert(isequal(roundtrip.(name),source.(name)),'CSV projection changed original %s.',name);
end
for suffix=["Available","ResourceCount","SelectedResourceID","ReportedPowerError_dB", ...
        "SelectedColumnPowerError_dB","ReportedSINRError_dB","SelectedColumnSINRError_dB", ...
        "ReportedSINRLogRatioDifference_dB","SelectedColumnSINRLogRatioDifference_dB", ...
        "SINREstimandCompatible", ...
        "CDMOperatorMatchedModelAvailable","CDMDenominatorIndependentlyReferenced", ...
        "CDMReportedPowerDifference_dB","CDMSelectedColumnPowerDifference_dB", ...
        "CDMReportedSINRLogRatioDifference_dB","CDMSelectedColumnSINRLogRatioDifference_dB", ...
        "UniqueNonlinearPortAttributionQualified","StandardizedAccuracyQualified","HardwareQualified"]
    name=prefix+suffix;
    assert(isequaln(double(roundtrip.(name)),double(source.(name))), ...
        'CSV projection changed original model numeric/qualification field %s.',name);
end
assert(all(isnan(roundtrip.(prefix+"ReportedSINRError_dB"))) && ...
    ~any(roundtrip.(prefix+"SINREstimandCompatible")) && ...
    all(isfinite(roundtrip.(prefix+"ReportedSINRLogRatioDifference_dB")(1:2))), ...
    'A finite cross-definition diagnostic must not become a SINR accuracy error.');
assert(roundtrip.(prefix+"CDMOperatorMatchedModelAvailable")(1)&& ...
    ~any(roundtrip.(prefix+"CDMDenominatorIndependentlyReferenced"))&& ...
    ~any(roundtrip.(prefix+"StandardizedAccuracyQualified")), ...
    'A matched model operator must not become an independently qualified SINR measurement.');
% Historical absence does not manufacture a new comparison receipt or pass.
minimal=source(:,{'SFN','Slot','UEIndex','ResourceID'});
legacy=project(minimal); legacyNames=string(legacy.Properties.VariableNames);
assert(~any(startsWith(legacyNames,"CSIRSEmittedPowerComparison") | ...
    startsWith(legacyNames,"CSIRSEmittedSINRComparison") | ...
    startsWith(legacyNames,"CSIRSLinearPortModelComparison") | legacyNames=="ReferenceSINRMeasurementJSON"));
assert(isempty(project(source([],:))));
assert(isequaln(source,snapshot)&&isequaln(rng,randomBefore)&& ...
    originalHash==string(sixgr.util.sha256File(original)));
result=struct('EvidenceRoot',string(folder),'OriginalSHA256',originalHash, ...
    'Scope',"declared_public_projection_and_CSV_not_physical_accuracy",'PHYExecutions',0);
ok=true;
fprintf('CSI_REFERENCE_PUBLIC_PROJECTION_PASS rows=3 PHY_executions=0 root=%s\n',folder);

    function out=project(input)
        tables=sixgr.truth.buildLLSPublicOutputTables(struct('csi_rs_table',input), ...
            sixgr.truth.llsOutputContract(), ...
            struct('logical_run_id',"declared_CSI_public_projection",'run_id',1));
        out=tables.csi_rs_runtime_event_table;
    end
end
