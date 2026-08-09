function ok = testApplicationGoodputReportingTruthBinding()
% Application throughput must come from strict same-waveform protocol
% delivery evidence and never fall back to PHY/TB goodput.
tmp = tempname;
mkdir(tmp);
c = onCleanup(@() localCleanup(tmp)); %#ok<NASGU>

scenarioPath = fullfile("simulator", "configs", "scenarios", ...
    "webgui_sinr_sweep_64x4_mu_mimo_repair_slice.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, tmp);
layout = sixgr.report.resultLayout(tmp);
sixgr.util.ensureFolder(layout.PacketFlowCSVDir);
sixgr.util.ensureFolder(layout.ReportCSVDir);
sixgr.util.ensureFolder(layout.AirInterfaceCSVDir);

ledger = table(["DL";"UL"], ["app_dl_1";"app_ul_1"], [true;true], [true;true], ...
    [12500;7500], 'VariableNames', ...
    {'Direction','PacketId','DeliverySuccess','SameWaveformProtocolComplete','DeliveredBits'});
sixgr.util.csvWriteTable(fullfile(layout.PacketFlowCSVDir, ...
    "live_application_packet_delivery_ledger.csv"), ledger);

recon = table(["DL_Application_Goodput_Mbps";"UL_Application_Goodput_Mbps"], ...
    [1.25;0.75], [true;true], [true;true], [true;true], [true;true], [1;1], ...
    'VariableNames', {'KPIName','Value','StrictOk','SchemaValid', ...
    'FormulaExecuted','ReconciliationPass','SourceRowCount'});
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, ...
    "kpi_reconstruction_summary.csv"), recon);

% Deliberately conflicting PHY values prove that reporting does not use
% these rows as an application-throughput substitute.
phy = table([999;999], [999;999], 'VariableNames', {'GoodBits','Goodput_Mbps'});
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv"), phy);
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, "ul_pusch_trials.csv"), phy);

out = sixgr.truth.exportLLSReportingBundle(tmp, scfg, cfg, struct("Ok", true), ...
    localManifest(), struct("StartedUTC", "test", "ElapsedSeconds", 1), struct());
rows = out.CategoryRows(string(out.CategoryRows.MetricKey) == ...
    "user_perceived_throughput", :);
assert(height(rows) == 2, ...
    "Exactly one strict application-goodput row per direction is required.");
assert(all(string(rows.Availability) == "derived"), ...
    "Application goodput must be a derived strict KPI, not a PHY observation.");
assert(abs(double(rows.ValueNumeric(string(rows.Entity) == "DL")) - 1.25) < 1e-12);
assert(abs(double(rows.ValueNumeric(string(rows.Entity) == "UL")) - 0.75) < 1e-12);
assert(all(string(rows.SourceArtifact) == "reports/csv/kpi_reconstruction_summary.csv"));
assert(all(contains(string(rows.Notes), "no PHY-goodput proxy")));

% A delivery claim without same-waveform protocol completion must fail
% closed and must not reappear as a finite PHY-equivalent row.
ledger.SameWaveformProtocolComplete(:) = false;
sixgr.util.csvWriteTable(fullfile(layout.PacketFlowCSVDir, ...
    "live_application_packet_delivery_ledger.csv"), ledger);
out = sixgr.truth.exportLLSReportingBundle(tmp, scfg, cfg, struct("Ok", true), ...
    localManifest(), struct("StartedUTC", "test", "ElapsedSeconds", 1), struct());
rows = out.CategoryRows(string(out.CategoryRows.MetricKey) == ...
    "user_perceived_throughput", :);
assert(isempty(rows) || ~any(rows.CountsTowardCoverage & isfinite(rows.ValueNumeric)), ...
    "Incomplete protocol evidence must not be replaced by PHY/TB goodput.");

% A failed run can legitimately reach reporting before any PHY trial table
% exists. Its tracking artifact must remain a typed unavailable row rather
% than crashing recovery because the table schema and values differ.
delete(fullfile(layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv"));
delete(fullfile(layout.AirInterfaceCSVDir, "ul_pusch_trials.csv"));
sixgr.truth.exportLLSReportingBundle(tmp, scfg, cfg, struct("Ok", false), ...
    localManifest(), struct("StartedUTC", "test", "ElapsedSeconds", 1), ...
    struct("RunCompletion", "failed", "ResultOk", false));
tracking = readtable(fullfile(layout.ReportCSVDir, ...
    "cfo_to_tracking_traces.csv"), "Delimiter", ",", ...
    "VariableNamingRule", "preserve", "TextType", "string");
assert(height(tracking) == 1 && width(tracking) == 30 && ...
    string(tracking.TraceSource(1)) == "not_available" && ...
    string(tracking.Status(1)) == "not_available", ...
    "Empty-runtime recovery must publish the exact 30-column tracking schema.");
ok = true;
end

function manifest = localManifest()
manifest = struct("CodeVersion", "test", "CodeDetail", "clean", ...
    "RandomSeed", 1, "GeneratedUTC", "test", "RunnerProfile", "test", ...
    "RunCompletion", "completed", "DeterministicMode", "test");
end

function localCleanup(path)
if exist(path, "dir") == 7
    rmdir(path, "s");
end
end
