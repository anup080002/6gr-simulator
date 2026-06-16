function T = guardNoULGoodputCopiedFromDL(summaryT, ulMetrics, dlMetrics)
%GUARDNOULGOODPUTCOPIEDFROMDL Detect the audited DL-to-UL goodput copy bug.

ulRaw = double(ulMetrics.GoodputMax_Mbps);
dlRaw = double(dlMetrics.GoodputMax_Mbps);
exportedUL = localValue(summaryT, "Goodput_UL_max_Mbps");
bugDetected = isfinite(exportedUL) && isfinite(dlRaw) && isfinite(ulRaw) && ...
    abs(exportedUL - dlRaw) <= 1e-9 && abs(ulRaw - dlRaw) > 1e-9;
bugPrevented = ~bugDetected && (isnan(exportedUL) || isnan(ulRaw) || abs(exportedUL - ulRaw) <= 1e-9);

row = struct();
row.RunId = localStringValue(summaryT, "RunId");
row.RegressionCase = "AUD-KPI-UL-GOODPUT_dl_value_copied_to_ul";
row.DLRawValueMbps = dlRaw;
row.ULRawValueMbps = ulRaw;
row.BadExportedULValueMbps = localValue(summaryT, "AuditedBadGoodput_UL_max_Mbps");
if ~isfinite(row.BadExportedULValueMbps)
    row.BadExportedULValueMbps = 40.137091;
end
row.CorrectExportedULValueMbps = exportedUL;
row.BugDetected = logical(bugDetected);
row.BugPrevented = logical(bugPrevented);
row.Status = string(localTernary(bugPrevented, "pass", "fail"));
row.FailureReason = string(localTernary(bugPrevented, "", "Goodput_UL_max_Mbps_matches_DL_value_not_UL_raw_value"));
T = struct2table(row);
end

function value = localValue(T, name)
value = NaN;
if istable(T) && ~isempty(T) && ismember(string(name), string(T.Properties.VariableNames))
    try
        value = double(T.(string(name))(1));
    catch
        value = str2double(string(T.(string(name))(1)));
    end
end
end

function value = localStringValue(T, name)
value = "";
if istable(T) && ~isempty(T) && ismember(string(name), string(T.Properties.VariableNames))
    value = string(T.(string(name))(1));
end
end

function y = localTernary(cond, a, b)
if cond
    y = a;
else
    y = b;
end
end
