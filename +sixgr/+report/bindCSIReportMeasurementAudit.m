function T = bindCSIReportMeasurementAudit(T, reportT, direction)
% Join retained measurement evidence to decoded reports for reporting only.
% Never called by the receiver or scheduler; UE audit timing is not control.
arguments
    T table
    reportT table
    direction (1,1) string
end
if ~(istable(T) && ~isempty(T))
    return;
end
n = height(T);
T.ReportSourceSlot = nan(n, 1);
T.ReportMeasurementSourceSlot = nan(n, 1);
T.ReportMeasurementSourceAuthority = strings(n, 1);
T.ReportDueSlot = nan(n, 1);
T.ReportDeliveredSlot = nan(n, 1);
T.ReportProcessed = false(n, 1);
T.ReportStatus = repmat("not_enqueued", n, 1);
T.ReportIdentity = strings(n, 1);
T.ReportCQIExactMatch = false(n, 1);
T.ReportRIExactMatch = false(n, 1);
T.ReportPMIExactMatch = false(n, 1);
T.ReportCRIExactMatch = false(n, 1);
T.ReportCSIExactMatch = false(n, 1);
T.ReportBindingStatus = repmat("missing_causal_report", n, 1);
if ~(istable(reportT) && ~isempty(reportT))
    return;
end
required = ["Direction","UEIndex","SourceSlot","DueSlot","CQI","RI","PMI","CRI","Processed"];
if ~all(ismember(required, string(reportT.Properties.VariableNames)))
    T.ReportBindingStatus(:) = "report_schema_incomplete";
    return;
end
[measurementSlots,auditAuthority] = sixgr.report.csiReportMeasurementAuditSlots(reportT);
for ii = 1:n
    ue = double(T.UEIndex(ii));
    sourceSlot = double(T.Slot(ii));
    mask = upper(string(reportT.Direction)) == upper(string(direction)) & ...
        isfinite(double(reportT.UEIndex)) & round(double(reportT.UEIndex)) == round(ue) & ...
        isfinite(measurementSlots) & measurementSlots == sourceSlot;
    if all(ismember("RNTI", string(T.Properties.VariableNames))) && ...
            ismember("RNTI", string(reportT.Properties.VariableNames))
        mask = mask & isfinite(double(reportT.RNTI)) & ...
            double(reportT.RNTI) == double(T.RNTI(ii));
    end
    hit = find(mask, 1, "last");
    if isempty(hit)
        continue;
    end
    T.ReportSourceSlot(ii) = double(reportT.SourceSlot(hit));
    T.ReportMeasurementSourceSlot(ii) = measurementSlots(hit);
    T.ReportMeasurementSourceAuthority(ii) = auditAuthority(hit);
    T.ReportDueSlot(ii) = double(reportT.DueSlot(hit));
    if ismember("DeliveredSlot", string(reportT.Properties.VariableNames))
        T.ReportDeliveredSlot(ii) = double(reportT.DeliveredSlot(hit));
    end
    T.ReportProcessed(ii) = logical(reportT.Processed(hit));
    if ismember("DeliveryStatus", string(reportT.Properties.VariableNames))
        T.ReportStatus(ii) = string(reportT.DeliveryStatus(hit));
    elseif T.ReportProcessed(ii)
        T.ReportStatus(ii) = "delivered_to_runtime_scheduler";
    else
        T.ReportStatus(ii) = "pending_causal_feedback_delay";
    end
    if ismember("ReportIdentity", string(reportT.Properties.VariableNames))
        T.ReportIdentity(ii) = string(reportT.ReportIdentity(hit));
    end
    T.ReportCQIExactMatch(ii) = localOptionalFiniteEqual(T, reportT, "CQI", ii, hit);
    T.ReportRIExactMatch(ii) = localOptionalFiniteEqual(T, reportT, "RI", ii, hit);
    T.ReportPMIExactMatch(ii) = localOptionalFiniteEqual(T, reportT, "PMI", ii, hit);
    T.ReportCRIExactMatch(ii) = localOptionalFiniteEqual(T, reportT, "CRI", ii, hit);
    exact = T.ReportCQIExactMatch(ii) && T.ReportRIExactMatch(ii) && ...
        T.ReportPMIExactMatch(ii) && T.ReportCRIExactMatch(ii);
    T.ReportCSIExactMatch(ii) = logical(exact);
    if exact
        T.ReportBindingStatus(ii) = "exact_measured_csi_report_bound";
    else
        csiFieldNames = ["CQI","RI","PMI","CRI"];
        mismatch = csiFieldNames(~[ ...
            T.ReportCQIExactMatch(ii), T.ReportRIExactMatch(ii), ...
            T.ReportPMIExactMatch(ii), T.ReportCRIExactMatch(ii)]);
        T.ReportBindingStatus(ii) = "measured_csi_report_value_mismatch:" + ...
            strjoin(mismatch, "+");
    end
end
end

function tf = localOptionalFiniteEqual(leftT, rightT, name, leftIdx, rightIdx)
tf = false;
if ~(ismember(string(name), string(leftT.Properties.VariableNames)) && ...
        ismember(string(name), string(rightT.Properties.VariableNames)))
    return;
end
a = double(leftT.(char(name))(leftIdx));
b = double(rightT.(char(name))(rightIdx));
tf = isfinite(a) && isfinite(b) && abs(a - b) <= 1e-9;
end
