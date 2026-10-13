function ok = testLLSAvailabilityAggregation()
%TESTLLSAVAILABILITYAGGREGATION Guard semantic availability rollups in the LLS report bundle.

setup6GRSimToolkit("Verbose", false);

runFolder = tempname;
mkdir(runFolder);
cleanup = onCleanup(@() rmdir(runFolder, "s")); %#ok<NASGU>
scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", ...
    "lls_4x4_rank2_bidirectional_focused_validation.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, runFolder);
manifest = struct("CodeVersion", "test", "CodeDetail", "clean", ...
    "RandomSeed", 23, "GeneratedUTC", "test", "RunnerProfile", "test", ...
    "RunCompletion", "failed", "DeterministicMode", "test");
% The main run's optional QCLAccuracy column is all blank. MATLAB imports
% this as cells; no QCL measurement may be invented to keep reports alive.
optional=table({'';''},'VariableNames',{'QCLAccuracy'});
sixgr.util.csvWriteTable(fullfile(runFolder,'air_interface','csv','dl_pdsch_trials.csv'),optional);
% Declared report-reducer fixtures, not measured PHY episodes. The first
% row is receiver-only: no transmitted payload, no bit comparison. The
% other two are one-bit transmissions with known failure/success. Delivery
% uses the transmitted population, not BitsCompared or CRC alone.
pucch=table([NaN;0;1],[0;1;1],[0;1;1],[0;1;1], ...
    [1;0;0],ones(3,1),ones(3,1),zeros(3,1), ...
    'VariableNames',{'UCIContentMatch','BitsCompared','ExpectedBitCount', ...
    'PUCCHTransmissionPrepared','DTXFlag','DetectionUsable','DetectionAttempted','Crash'});
sixgr.util.csvWriteTable(fullfile(runFolder,'air_interface','csv','pucch_trials.csv'),pucch);
% A PRACH-only duration is not end-to-end UE attachment latency. This
% report-only fixture mirrors the standalone diagnostic's 74-ms field.
prach=table(74,'VariableNames',{'ProcedureDelay_ms'});
sixgr.util.csvWriteTable(fullfile(runFolder,'air_interface','csv','prach_trials.csv'),prach);
sixgr.truth.exportLLSReportingBundle(runFolder, scfg, cfg, ...
    struct("Ok", false), manifest, ...
    struct("StartedUTC", "test", "ElapsedSeconds", 0), ...
    struct("RunCompletion", "failed", "ResultOk", false));
coveragePath = fullfile(runFolder, "reports", "csv", "lls_output_spec_coverage.csv");

coverage = readtable(coveragePath, "VariableNamingRule", "preserve");
detail = readtable(fullfile(runFolder, "reports", "csv", "lls_output_metric_rows.csv"), "VariableNamingRule", "preserve");
% The same population is also summarized under signaling overhead. Select
% the metric identity, not only Entity/Statistic, when asserting uniqueness.
uci=detail(string(detail.MetricKey)=="uci_multiplexing_efficiency" & ...
    string(detail.Entity)=="UCI" & string(detail.Statistic)=="success_ratio",:);
assert(height(uci)==1 && abs(uci.ValueNumeric-.5)<1e-12, ...
    'Receiver-only UCI must not crash or enter the transmitted-payload denominator.');
sent=detail(string(detail.MetricKey)=="uci_multiplexing_efficiency" & ...
    string(detail.Entity)=="UCI" & string(detail.Statistic)=="transmitted_bits",:);
assert(height(sent)==1 && sent.ValueNumeric==2, ...
    'Delivery must count the two actual fixture transmissions, not receiver-only occasions.');
qcl=detail(contains(lower(string(detail.MetricKey)),"qcl"),:);
assert(~isempty(qcl) && ~any(logical(qcl.CountsTowardCoverage)), ...
    'Blank QCL inputs must remain unavailable, not observed zero correlation.');
inventory = readtable(fullfile(runFolder, "reports", "csv", "artifact_inventory.csv"), "VariableNamingRule", "preserve");
summaryT = readtable(fullfile(runFolder, "reports", "csv", "per_scenario_summary_tables.csv"), "VariableNamingRule", "preserve");
autoMd = string(fileread(fullfile(runFolder, "reports", "automatic_markdown_summary.md")));
execMd = string(fileread(fullfile(runFolder, "reports", "executive_summary.md")));
techMd = string(fileread(fullfile(runFolder, "reports", "technical_report.md")));

assert(all(ismember(["CountsTowardCoverage","CoveredRowCount","ObservedRowCount","DerivedRowCount","ConfigOnlyRowCount","DisabledRowCount","PlaceholderRowCount"], ...
    string(coverage.Properties.VariableNames))), ...
    "Coverage summary must expose semantic state counts and coverage-credit flags.");
assert(all(ismember(["SemanticState","CountsTowardCoverage"], string(inventory.Properties.VariableNames))), ...
    "Artifact inventory must expose semantic state and coverage-credit flags.");

assert(localCoverageState(coverage, "scenario_identifiers") == "config_only", ...
    "Scenario identifiers must roll up as config_only.");
assert(localCoverageState(coverage, "ai_confidence_traces") == "not_supported", ...
    "Suppressed disabled-AI traces must roll up as not_supported.");
assert(localCoverageState(coverage, "curves_access_delay_cdf") == "not_available", ...
    "Missing access-delay evidence must roll up as not_available without a placeholder.");
assert(~localCoverageCredit(coverage, "scenario_identifiers"), ...
    "Config-only metrics must not receive coverage credit.");
assert(~localCoverageCredit(coverage, "ai_confidence_traces"), ...
    "Suppressed disabled metrics must not receive coverage credit.");
assert(~localCoverageCredit(coverage, "curves_access_delay_cdf"), ...
    "Unavailable metrics must not receive coverage credit.");

assert(~any(string(inventory.RelativePath) == "reports/image/ai_confidence_trace.png") && ...
    ~any(string(inventory.RelativePath) == "reports/csv/ai_confidence_trace.csv"), ...
    "Artifact inventory must not claim suppressed disabled-AI artifacts exist.");
assert(~any(string(inventory.RelativePath) == "reports/image/access_delay_cdf.png"), ...
    "Artifact inventory must not claim an unavailable access-delay plot exists.");
assert(localInventoryState(inventory, "reports/csv/lls_output_spec_coverage.csv") == "derived", ...
    "Artifact inventory must mark the coverage CSV as a derived report artifact.");

assert(height(summaryT) == 1, "Per-scenario summary table must contain one row for the smoke run.");
assert(double(summaryT.CoveredMetricCount(1)) == sum(logical(coverage.CountsTowardCoverage)), ...
    "Per-scenario covered-metric count must match the coverage-credit flags.");
assert(double(summaryT.ConfigOnlyMetricCount(1)) == sum(string(coverage.Availability) == "config_only"), ...
    "Per-scenario config-only count must match the coverage summary.");
assert(double(summaryT.DisabledMetricCount(1)) == sum(string(coverage.Availability) == "disabled"), ...
    "Per-scenario disabled count must match the coverage summary.");
assert(double(summaryT.PlaceholderMetricCount(1)) == sum(string(coverage.Availability) == "placeholder"), ...
    "Per-scenario placeholder count must match the coverage summary.");

assert(contains(autoMd, "Observed metrics"), ...
    "Automatic markdown summary must report observed metric counts explicitly.");
assert(contains(execMd, "Config-only metrics"), ...
    "Executive summary must distinguish config-only metrics.");
assert(contains(execMd, "Placeholder artifacts/metrics"), ...
    "Executive summary must distinguish placeholder artifacts.");
assert(contains(techMd, "covered,") && contains(techMd, "config-only"), ...
    "Technical report must summarize category coverage using the semantic states.");

assert(any(string(detail.MetricKey) == "ai_confidence_traces" & string(detail.Availability) == "not_supported"), ...
    "Detail rows must preserve not_supported for suppressed AI confidence traces.");
assert(any(string(detail.MetricKey) == "curves_access_delay_cdf" & string(detail.Availability) == "not_available"), ...
    "Detail rows must preserve not_available for an omitted access-delay plot.");

paprRows=detail(string(detail.MetricKey)=="low_papr_gain",:);
assert(height(paprRows)==1 && string(paprRows.Statistic)=="feature_enabled" && ...
    string(paprRows.Availability)=="config_only" && ~paprRows.CountsTowardCoverage, ...
    'A failed run without UL samples must not publish observed NaN PAPR statistics.');
assert(~localCoverageCredit(coverage,"low_papr_gain"));

% Explicit report-only numeric fixtures, not PHY qualification observations.
% NaN-only and finite-with-NaN inputs exercise the producer's evidence guard.
for paprFixture = {nan(3,1),[3;6;9;NaN]}
    source=table(paprFixture{1},'VariableNames',{'PAPR_dB'});
    sixgr.util.csvWriteTable(fullfile(runFolder,'air_interface','csv','ul_pusch_trials.csv'),source);
    sixgr.truth.exportLLSReportingBundle(runFolder, scfg, cfg, ...
        struct("Ok", false), manifest, ...
        struct("StartedUTC", "test", "ElapsedSeconds", 0), ...
        struct("RunCompletion", "failed", "ResultOk", false));
    refreshed=readtable(fullfile(runFolder,'reports','csv','lls_output_metric_rows.csv'), ...
        'TextType','string','VariableNamingRule','preserve');
    rows=refreshed(string(refreshed.MetricKey)=="low_papr_gain",:);
    observed=rows(logical(rows.CountsTowardCoverage),:);
    values=paprFixture{1}; values=values(isfinite(values));
    if isempty(values)
        assert(isempty(observed) && height(rows)==1, ...
            'NaN-only UL evidence was promoted to measured PAPR coverage.');
    else
        assert(height(observed)==2 && all(string(observed.Availability)=="observed") && ...
            all(isfinite(observed.ValueNumeric)));
        assert(abs(observed.ValueNumeric(observed.Statistic=="mean_papr_db")-mean(values))<1e-12);
        assert(abs(observed.ValueNumeric(observed.Statistic=="p95_papr_db")-prctile(values,95))<1e-12);
        assert(all(contains(observed.Notes,"not a measured PAPR reduction or gain")));
    end
end
disp('UL_PAPR_MEASUREMENT_AVAILABILITY_PASS');
% Positive report-only lifecycle fixture: incomplete and explicitly proxy
% rows must not enter the plotted CDF, even if their delays are finite.
% Provide the real lifecycle schema and causal event clock; let the
% production reducer derive the terminal duration rather than supplying a
% precomputed CompleteFlag/delay that would bypass that calculation.
life=table();
for ue=1:5
    events=["SSB_DETECTED";"PBCH_DECODED";"PRACH_MSG1_DETECTED"; ...
        "MSG2_RAR_DECODED";"MSG3_PUSCH_COMPLETED";"MSG4_PDSCH_COMPLETED"];
    terminalSlots=[4,8,7,12,20];
    slots=[0;0;1;2;3;terminalSlots(ue)];
    if ue==3
        events(end)="MSG4_PENDING";
    end
    part=table(repmat(ue,6,1),events,slots,slots*.001,repmat(.001,6,1), ...
        repmat(ue==4,6,1),repmat(ue==5,6,1),'VariableNames', ...
        {'UEIndex','EventName','Slot','Time_s','SlotDuration_s', ...
        'PlaceholderFlag','FallbackFlag'});
    life=[life;part]; %#ok<AGROW>
end
sixgr.util.csvWriteTable(fullfile(runFolder,'control','csv','initial_access_lifecycle_trace.csv'),life);
rrcData=scfg.toStruct();
rrcData.initial_access.rrc.require_setup_complete=true;
rrcScfg=sixgr.lls6g.config.ScenarioConfig(rrcData);
rrcCfg=cfg;
rrcCfg.initial_access.rrc.require_setup_complete=true;
sixgr.truth.exportLLSReportingBundle(runFolder,rrcScfg,rrcCfg,struct('Ok',false),manifest, ...
    struct('StartedUTC','test','ElapsedSeconds',0), ...
    struct('RunCompletion','failed','ResultOk',false));
assert(~isfile(fullfile(runFolder,'reports','csv','access_delay_cdf_plot.csv')), ...
    'Msg4 alone must not count as completed access when RRCSetupComplete is required.');
% Reset the declared raw fixture before testing the four-step-only policy.
sixgr.util.csvWriteTable(fullfile(runFolder,'control','csv','initial_access_lifecycle_trace.csv'),life);
sixgr.truth.exportLLSReportingBundle(runFolder,scfg,cfg,struct('Ok',false),manifest, ...
    struct('StartedUTC','test','ElapsedSeconds',0), ...
    struct('RunCompletion','failed','ResultOk',false));
plotted=readtable(fullfile(runFolder,'reports','csv','access_delay_cdf_plot.csv'), ...
    'TextType','string','VariableNamingRule','preserve');
assert(isequal(plotted.latency_ms,[5;9]) && isequal(plotted.cdf_probability,[.5;1]) && ...
    all(plotted.source_table=="control/csv/initial_access_lifecycle_trace.csv"));
% Stale-producer-artifact fixture, not a measured plot: even with MATLAB
% raster rendering disabled, loss of eligible evidence must retire it.
stalePath=fullfile(runFolder,'reports','image','access_delay_cdf.png');
imwrite(uint8([0,255;255,0]),stalePath);
life.FallbackFlag(:)=true;
sixgr.util.csvWriteTable(fullfile(runFolder,'control','csv','initial_access_lifecycle_trace.csv'),life);
sixgr.truth.exportLLSReportingBundle(runFolder,scfg,cfg,struct('Ok',false),manifest, ...
    struct('StartedUTC','test','ElapsedSeconds',0), ...
    struct('RunCompletion','failed','ResultOk',false));
assert(~isfile(fullfile(runFolder,'reports','csv','access_delay_cdf_plot.csv')) && ~isfile(stalePath), ...
    'No eligible lifecycle evidence must leave no stale access-CDF data or PNG.');
ok = true;
end

function state = localCoverageState(T, metricKey)
mask = string(T.MetricKey) == string(metricKey);
assert(any(mask), "Coverage table is missing metric %s.", metricKey);
state = string(T.Availability(find(mask, 1, "first")));
end

function tf = localCoverageCredit(T, metricKey)
mask = string(T.MetricKey) == string(metricKey);
assert(any(mask), "Coverage table is missing metric %s.", metricKey);
tf = logical(T.CountsTowardCoverage(find(mask, 1, "first")));
end

function state = localInventoryState(T, relPath)
mask = string(T.RelativePath) == string(relPath);
assert(any(mask), "Artifact inventory is missing %s.", relPath);
state = string(T.SemanticState(find(mask, 1, "first")));
end
