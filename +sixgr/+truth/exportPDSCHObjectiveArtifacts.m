function artifacts = exportPDSCHObjectiveArtifacts(runFolder, cfg, trialTable, varargin)
%EXPORTPDSCHOBJECTIVEARTIFACTS Write DL PDSCH raw BLER/BER objective evidence.

ip = inputParser;
ip.addParameter("RunId", "", @(x) ischar(x) || isstring(x));
ip.addParameter("ScenarioName", "", @(x) ischar(x) || isstring(x));
ip.addParameter("StrictMode", false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter("SourceTable", "air_interface/csv/dl_pdsch_trials.csv", @(x) ischar(x) || isstring(x));
ip.parse(varargin{:});

if nargin < 2 || isempty(cfg)
    cfg = struct();
end
if nargin < 3 || ~istable(trialTable)
    trialTable = table();
end

layout = sixgr.report.resultLayout(runFolder);
sixgr.util.ensureFolder(layout.ReportCSVDir);
sixgr.util.ensureFolder(layout.AirInterfaceCSVDir);
jsonDir = fullfile(layout.ReportDir, "json");
sixgr.util.ensureFolder(jsonDir);

result = sixgr.truth.evaluatePDSCHObjectiveStrict(trialTable, cfg, ...
    "RunId", ip.Results.RunId, ...
    "ScenarioName", ip.Results.ScenarioName, ...
    "StrictMode", ip.Results.StrictMode, ...
    "SourceTable", ip.Results.SourceTable);

artifacts = struct("csv", {{}}, "json", {{}}, "Result", result);

summaryPath = fullfile(layout.ReportCSVDir, "dl_pdsch_raw_bler_ber_objective.csv");
failurePath = fullfile(layout.ReportCSVDir, "dl_pdsch_objective_failures.csv");
rowAuditPath = fullfile(layout.AirInterfaceCSVDir, "dl_pdsch_receiver_evidence_audit.csv");
schemaPath = fullfile(layout.ReportCSVDir, "dl_pdsch_objective_artifact_schema.csv");
toolboxPath = fullfile(jsonDir, "dl_pdsch_toolbox_capabilities.json");

sixgr.util.csvWriteTable(summaryPath, result.Summary);
sixgr.util.csvWriteTable(failurePath, result.Failures);
sixgr.util.csvWriteTable(rowAuditPath, result.RowAudit);
sixgr.util.csvWriteTable(schemaPath, localArtifactSchemaTable(summaryPath, failurePath, rowAuditPath, toolboxPath));
localWriteJSON(toolboxPath, localToolboxCapabilities());

artifacts.csv = {summaryPath, failurePath, rowAuditPath, schemaPath};
artifacts.json = {toolboxPath};
end

function T = localArtifactSchemaTable(summaryPath, failurePath, rowAuditPath, toolboxPath)
T = table( ...
    ["dl_pdsch_raw_bler_ber_objective"; "dl_pdsch_objective_failures"; "dl_pdsch_receiver_evidence_audit"; "dl_pdsch_toolbox_capabilities"], ...
    [string(summaryPath); string(failurePath); string(rowAuditPath); string(toolboxPath)], ...
    ["reports/csv"; "reports/csv"; "air_interface/csv"; "reports/json"], ...
    ["objective_summary"; "objective_failures"; "row_receiver_evidence_audit"; "toolbox_capability_manifest"], ...
    [true; true; true; true], ...
    'VariableNames', {'ArtifactId','FilePath','FolderFamily','SemanticRole','MachineReadable'});
end

function caps = localToolboxCapabilities()
caps = struct();
caps.MATLABVersion = string(version);
caps.ToolboxVersion = localToolboxVersion("5G Toolbox");
caps.nrPDSCHConfigAvailable = localFunctionAvailable("nrPDSCHConfig");
caps.nrPDSCHAvailable = localFunctionAvailable("nrPDSCH");
caps.nrPDSCHDecodeAvailable = localFunctionAvailable("nrPDSCHDecode");
caps.nrPDSCHIndicesAvailable = localFunctionAvailable("nrPDSCHIndices");
caps.nrPDSCHDMRSAvailable = localFunctionAvailable("nrPDSCHDMRS");
caps.nrPDSCHDMRSIndicesAvailable = localFunctionAvailable("nrPDSCHDMRSIndices");
caps.nrPDSCHPTRSAvailable = localFunctionAvailable("nrPDSCHPTRS");
caps.nrPDSCHPTRSIndicesAvailable = localFunctionAvailable("nrPDSCHPTRSIndices");
caps.nrDLSCHAvailable = localFunctionAvailable("nrDLSCH");
caps.nrDLSCHDecoderAvailable = localFunctionAvailable("nrDLSCHDecoder");
caps.nrTBSAvailable = localFunctionAvailable("nrTBS");
caps.nrOFDMModulateAvailable = localFunctionAvailable("nrOFDMModulate");
caps.nrOFDMDemodulateAvailable = localFunctionAvailable("nrOFDMDemodulate");
caps.nrChannelEstimateAvailable = localFunctionAvailable("nrChannelEstimate");
caps.nrEqualizeMMSEAvailable = localFunctionAvailable("nrEqualizeMMSE");
caps.nrTDLChannelAvailable = localFunctionAvailable("nrTDLChannel");
caps.nrCDLChannelAvailable = localFunctionAvailable("nrCDLChannel");
caps.StrictModeToolboxFallbackAllowed = false;
caps.GeneratedAt = string(datetime("now", "TimeZone", "UTC", "Format", "yyyy-MM-dd'T'HH:mm:ss'Z'"));
caps.ProducerModule = "sixgr.truth.exportPDSCHObjectiveArtifacts";
end

function tf = localFunctionAvailable(name)
tf = exist(char(name), "file") == 2 || exist(char(name), "class") == 8;
end

function v = localToolboxVersion(toolboxName)
toolboxName = string(toolboxName);
if toolboxName == "5G Toolbox" && localFunctionAvailable("nrPDSCHDecode")
    % Avoid MATLAB's ver() here: the audited R2024a environment can crash
    % natively while enumerating products. Function availability is the
    % strict runtime capability used by the receiver gate.
    v = "installed_version_query_not_used_runtime_function_probe";
else
    v = "unavailable";
end
end

function localWriteJSON(path, payload)
fid = fopen(path, "w");
if fid < 0
    error("sixgr:truth:PDSCHObjectiveJSONOpenFailed", "Unable to open %s for writing.", path);
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "%s", jsonencode(payload, "PrettyPrint", true));
end
