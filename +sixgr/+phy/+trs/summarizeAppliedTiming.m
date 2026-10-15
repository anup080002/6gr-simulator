function out = summarizeAppliedTiming(detectionTable)
%SUMMARIZEAPPLIEDTIMING Describe actual TRS extraction-window clock shifts.
% Estimates alone, injected offsets and qualification pass/fail do not prove
% that a correction was executed. The extractor owns this evidence.
arguments
    detectionTable table = table()
end
out=struct('TimingEstimateUsed',false,'AppliedTimingCorrection_samples',NaN, ...
    'TimingEstimateApplicationPolicy',"no_executed_TRS_window_alignment", ...
    'TimingEstimateStatus',"unavailable_no_executed_TRS_window_alignment", ...
    'TimingEstimateWasClipped',false,'TRSAppliedTimingResourceCount',0, ...
    'TRSExpectedTimingResourceCount',height(detectionTable), ...
    'TRSAppliedTimingEvidenceJSON',"[]");
names=["Slot","ReceiveStartSample1Based","ReceiveEndSample1Based", ...
    "ReceivedSymbolCount","EstimatedTimingOffset_samples","ReceiveWindowSource"];
if isempty(detectionTable), return; end
assert(all(ismember(names,string(detectionTable.Properties.VariableNames))), ...
    'sixgr:phy:trs:IncompleteAppliedTimingEvidence', ...
    'Retain the actual extraction-window bounds and clock shift for every TRS resource.');
first=double(detectionTable.ReceiveStartSample1Based);
last=double(detectionTable.ReceiveEndSample1Based);
symbols=double(detectionTable.ReceivedSymbolCount);
shift=double(detectionTable.EstimatedTimingOffset_samples);
source=string(detectionTable.ReceiveWindowSource);
present=isfinite(first) | isfinite(last) | isfinite(symbols) | isfinite(shift);
valid=isfinite(first) & first>=1 & first==fix(first) & ...
    isfinite(last) & last>=first & last==fix(last) & ...
    isfinite(symbols) & symbols>=1 & symbols==fix(symbols) & ...
    isfinite(shift) & shift==fix(shift) & ...
    source=="measured_timing_actual_received_reference_symbol_window";
assert(all(~present | valid),'sixgr:phy:trs:InvalidAppliedTimingEvidence', ...
    'A partially populated or substituted extraction window is not executed timing evidence.');
out.TRSAppliedTimingResourceCount=nnz(valid);
out.TRSAppliedTimingEvidenceJSON=string(jsonencode(table2struct(detectionTable(:,names))));
if ~any(valid), return; end
out.TimingEstimateUsed=true;
out.TimingEstimateApplicationPolicy="per_resource_received_window_origin_shift_no_second_correction";
out.TimingEstimateStatus="available_applied_at_received_window_origins";
if all(shift(valid)==shift(find(valid,1)))
    out.AppliedTimingCorrection_samples=shift(find(valid,1));
else
    out.TimingEstimateStatus="available_per_resource_shifts_no_single_scalar_correction";
end
if ~all(valid)
    out.TimingEstimateStatus="partial_"+out.TimingEstimateStatus;
end
end
