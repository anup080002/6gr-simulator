function ok = testPrompt9TrueLLSMasterIntegration()
%TESTPROMPT9TRUELLSMASTERINTEGRATION Guard Prompt 9 master/audit scaffolding.

setup6GRSimToolkit("Verbose", false);
root = fileparts(fileparts(mfilename("fullpath")));

assert(exist(fullfile(root, "run_true_lls.m"), "file") == 2, "Missing run_true_lls.m.");
assert(exist(fullfile(root, "grade10Checklist.m"), "file") == 2, "Missing grade10Checklist.m.");

registry = sixgr.utils.verifyFunctionRegistry("Strict", true);
assert(logical(registry.Ok), "Prompt 9 function registry must resolve current repo capabilities.");
assert(any(strcmp(string(registry.Table.Capability), "measurement_only_audit")), ...
    "Registry must include the Prompt 9 measurement-only audit capability.");

dry = run_true_lls("simulator/configs/scenarios/lls_mobile_2ue_100kmh_1sector_full_capture.yaml", ...
    "prompt9_registry_only", "Execute", false);
assert(logical(dry.Ok) && strcmp(string(dry.Status), "registry_only"), ...
    "run_true_lls Execute=false must perform a registry-only dry run.");

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>
layout = sixgr.report.resultLayout(tmp);
sixgr.util.ensureFolder(layout.AirInterfaceCSVDir);

good = table([0;0], [1;2], [1;2], [4660;4661], ["pdsch_dmrs_nrChannelEstimate";"pdsch_dmrs_nrChannelEstimate"], ...
    ["dmrs_nrChannelEstimate";"dmrs_nrChannelEstimate"], ["";""], [true;false], ...
    'VariableNames', {'Frame','Slot','UEIndex','RNTI','NoiseVarSource','ChannelEstMethod','UsedOracleFields','CRCPass'});
writetable(good, fullfile(layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv"));

audit = sixgr.audit.verifyMeasurementOnly(tmp, "ErrorOnViolation", false);
assert(logical(audit.Ok), "Clean measurement-only fixture must pass the oracle audit.");
assert(exist(fullfile(layout.ReportCSVDir, "measurement_only_audit.csv"), "file") == 2, ...
    "Measurement-only audit CSV must be written.");

bad = good;
bad.UsedOracleFields(2) = "scheduler_struct";
bad.NoiseVarSource(2) = "configured_snr";
writetable(bad, fullfile(layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv"));
badAudit = sixgr.audit.verifyMeasurementOnly(tmp, "ErrorOnViolation", false);
assert(~logical(badAudit.Ok) && double(badAudit.ViolationCount) >= 2, ...
    "Oracle audit must fail when oracle fields or configured-SNR noise sources are present.");

grade = grade10Checklist(tmp);
assert(~logical(grade.Ok), "Grade 10 checklist must fail closed for incomplete fixtures.");

exportReport = sixgr.export.exportAllEvidence(struct(), struct("meta", struct("scenario_id", "prompt9_fixture")), tmp);
assert(isfield(exportReport, "Stages") && istable(exportReport.Stages), ...
    "exportAllEvidence must return a stage table.");
assert(exist(fullfile(layout.ReportCSVDir, "export_all_evidence_status.csv"), "file") == 2, ...
    "exportAllEvidence status CSV must be written.");

ok = true;
end
