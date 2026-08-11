function out = finalizeRunVisualAudit(runFolder)
%FINALIZERUNVISUALAUDIT Audit the exact final persisted raster tree.

arguments
    runFolder (1,1) string
end

plotManifestPath = fullfile(runFolder,"reports","csv","plot_manifest.csv");
plotManifest = table();
if exist(plotManifestPath,"file") == 2
    plotManifest = readtable(plotManifestPath, ...
        "VariableNamingRule","preserve","TextType","string");
end
integrity = sixgr.visual.verifyVisualArtifacts(runFolder,plotManifest);
integrityPath = fullfile(runFolder,"reports","csv", ...
    "visual_artifact_integrity.csv");
sixgr.util.csvWriteTable(integrityPath,integrity);

repoRoot = string(sixgr.utils.getRepoRoot());
toolPath = fullfile(repoRoot,"tools","audit_lls_visual_artifacts.py");
auditPath = fullfile(runFolder,"reports","csv","visual_artifact_audit.csv");
status = 1;
outputText = "";
if exist(toolPath,"file") == 2
    pythonExe = "python";
    try
        runtime = sixgr.lls6g.runners.resolveWebGUIContractPython();
        candidate = string(sixgr.util.structGet(runtime,"Executable",""));
        if logical(sixgr.util.structGet(runtime,"Ok",false)) && ...
                strlength(strtrim(candidate)) > 0
            pythonExe = candidate;
        end
    catch
    end
    command = sprintf('"%s" "%s" "%s"', ...
        localEscape(pythonExe),localEscape(toolPath),localEscape(runFolder));
    [status,outputText] = system(command);
end

audit = table();
if exist(auditPath,"file") == 2
    try
        audit = readtable(auditPath, ...
            "VariableNamingRule","preserve","TextType","string");
    catch
        audit = table();
    end
end
if isempty(audit)
    reason = "Visual semantic audit did not produce its required CSV.";
    if strlength(strtrim(string(outputText))) > 0
        reason = reason + " " + strtrim(string(outputText));
    end
    audit = localFailureAudit("visual_audit_tool_failed",reason);
    sixgr.util.csvWriteTable(auditPath,audit);
end

integrityOk = ~isempty(integrity) && all(localAsLogical( ...
    integrity.IntegrityOk,false));
auditOk = status == 0 && ismember("audit_ok", ...
    string(audit.Properties.VariableNames)) && ...
    all(localAsLogical(audit.audit_ok,false));
out = struct( ...
    "Ok",logical(integrityOk && auditOk), ...
    "Integrity",integrity, ...
    "Audit",audit, ...
    "IntegrityFailureCount",sum(~localAsLogical(integrity.IntegrityOk,false)), ...
    "AuditFailureCount",sum(~localAsLogical(audit.audit_ok,false)), ...
    "AuditToolExitCode",double(status), ...
    "AuditToolOutput",string(outputText));
end

function values = localAsLogical(raw,fallback)
if islogical(raw)
    values = raw(:);
elseif isnumeric(raw)
    values = isfinite(raw(:)) & raw(:) ~= 0;
else
    token = lower(strtrim(string(raw(:))));
    values = ismember(token,["1","true","yes","pass","passed","ok"]);
    missing = ismissing(token) | strlength(token) == 0;
    values(missing) = logical(fallback);
end
end

function value = localEscape(value)
value = strrep(char(string(value)),'"','""');
end

function T = localFailureAudit(code,reason)
T = table( ...
    "visual_artifact_audit", "", "audit_tool", false, "", "", ...
    "", "", "", "", NaN, NaN, NaN, NaN, false, false, "", "", ...
    "", "", "", "", "", 0, false, string(code), string(reason), ...
    'VariableNames', ["plot_id","artifact_path","artifact_kind", ...
    "is_manifest_row","manifest_status","visual_validity","source_csv", ...
    "x_column","y_column","plot_kind","row_count","unique_x_count", ...
    "unique_y_count","non_nan_y_count","nan_only_y","mixed_units", ...
    "source_mapping_status","curve_construction","truth_status_tokens", ...
    "actual_mime_type","declared_mime_type","extension","sha256", ...
    "byte_count","audit_ok","failure_code","failure_reason"]);
end
