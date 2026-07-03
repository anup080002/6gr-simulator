function ok = testMeasuredSINRCurveArtifacts()
%TESTMEASUREDSINRCURVEARTIFACTS Guard geometry-driven measured-SINR outputs.

setup6GRSimToolkit("Verbose", false);
tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

legacyFiles = {
    fullfile(tmp, "air_interface", "csv", "lls_snr_sweep.csv")
    fullfile(tmp, "air_interface", "csv", "live_link_snr_sweep.csv")
    fullfile(tmp, "reports", "csv", "per_sweep_comparison_tables.csv")
    };
for i = 1:numel(legacyFiles)
    sixgr.util.ensureDir(legacyFiles{i});
    writetable(table(1, 'VariableNames', {'Deprecated'}), legacyFiles{i});
end
localWriteLegacyAnalyticsFiles(tmp);

trialData = struct();
trialData.dl = localTrialTable("DL");
trialData.ul = localTrialTable("UL");
trialData.pbch = localPBCHTrialTable();
trialData.prach = localPRACHTrialTable();
trialData.srs = localSRSTrialTable();

res = sixgr.analytics.generateMeasuredSINRCurves(tmp, "unit", ...
    "TrialData", trialData, ...
    "ScenarioConfig", struct("global_radio_scope", struct("channel_bandwidth_hz", 100e6)), ...
    "BinCount", 6, ...
    "WriteKPISummary", true, ...
    "UpdateAnchorKPIs", true);
assert(logical(res.Ok), "Measured SINR curve generation did not report Ok=true.");

csvs = [
    "air_interface/csv/dl_measured_sinr_bler_curve.csv"
    "air_interface/csv/ul_measured_sinr_bler_curve.csv"
    "air_interface/csv/dl_measured_sinr_throughput_curve.csv"
    "air_interface/csv/ul_measured_sinr_throughput_curve.csv"
    "air_interface/csv/measured_sinr_distribution.csv"
    "air_interface/csv/distance_vs_sinr.csv"
    "air_interface/csv/lls_measured_sinr_summary.csv"
    "air_interface/csv/live_measured_sinr_summary.csv"
    "air_interface/csv/lls_kpi_summary.csv"
    "air_interface/csv/link_anchor_kpis.csv"
    "reports/csv/throughput_reconciliation.csv"
    "reports/csv/blerber_reconciliation.csv"
    "reports/csv/access_kpi_reconciliation.csv"
    "reports/csv/scheduler_kpi_reconciliation.csv"
    "reports/csv/latency_reconciliation.csv"
    "reports/csv/canonical_kpi_ledger.csv"
    ];
for i = 1:numel(csvs)
    p = fullfile(tmp, strrep(csvs(i), "/", filesep));
    assert(exist(p, "file") == 2, "Missing measured SINR CSV: %s", csvs(i));
    T = readtable(p, "VariableNamingRule", "preserve");
    assert(height(T) >= 1, "Measured SINR CSV is empty: %s", csvs(i));
    if contains(csvs(i), "measured_sinr") || contains(csvs(i), "distance_vs_sinr") || contains(csvs(i), "lls_kpi_summary")
        vars = string(T.Properties.VariableNames);
        assert(~any(vars == "ConfiguredSNR_dB"), "ConfiguredSNR_dB leaked into %s", csvs(i));
        assert(~any(vars == "AppliedAWGNSNR_dB"), "AppliedAWGNSNR_dB leaked into %s", csvs(i));
    end
end

for i = 1:numel(legacyFiles)
    assert(exist(legacyFiles{i}, "file") ~= 2, "Deprecated sweep artifact survived: %s", legacyFiles{i});
end

summary = readtable(fullfile(tmp, "air_interface", "csv", "lls_measured_sinr_summary.csv"), "VariableNamingRule", "preserve");
assert(all(isfinite(double(summary.SINR_median_dB))), "Measured SINR summary contains non-finite median SINR.");
assert(all(string(summary.KPIFormulaVersion) == "measured_sinr_geometry_v1"), "Unexpected measured SINR formula version.");

kpi = readtable(fullfile(tmp, "air_interface", "csv", "lls_kpi_summary.csv"), "VariableNamingRule", "preserve");
assert(all(logical(kpi.KPIReconciliationPass)), "KPI reconciliation did not pass for measured SINR summary.");

anchor = readtable(fullfile(tmp, "air_interface", "csv", "link_anchor_kpis.csv"), "VariableNamingRule", "preserve");
assert(~any(contains(string(anchor.Notes), "deferred")), "Anchor KPI notes still contain deferred status.");
requiredCases = ["CellSearch_MIB_SIB1","PRACH_Detection","DL_PDSCH_Throughput", ...
    "UL_PUSCH_Throughput","UL_SRS_ChannelEst","UL_LowPAPR"];
assert(all(ismember(requiredCases, string(anchor.Case))), "Measured SINR anchor KPIs must cover all six Prompt 7 cases.");
for caseName = requiredCases
    mask = strcmp(string(anchor.Case), caseName);
    assert(any(mask) && localAsLogical(anchor.Ok(find(mask, 1))), "Anchor case did not pass from runtime evidence: %s", caseName);
end
assert(all(string(anchor.KPIFormulaVersion) == "measured_sinr_geometry_v1"), "Anchor KPI formula version must be measured_sinr_geometry_v1.");

localAssertGateOk(tmp, "throughput_reconciliation.csv", "ThroughputReconciliationOk");
localAssertGateOk(tmp, "blerber_reconciliation.csv", "BlerBerReconciliationOk");
localAssertGateOk(tmp, "access_kpi_reconciliation.csv", "AccessKpiReconciliationOk");
localAssertGateOk(tmp, "scheduler_kpi_reconciliation.csv", "SchedulerKpiReconciliationOk");
localAssertGateOk(tmp, "latency_reconciliation.csv", "LatencyReconciliationOk");
localAssertGateOk(tmp, "canonical_kpi_ledger.csv", "CanonicalKpiLedgerOk");

plots = sixgr.analytics.generateMeasuredSINRPlots(tmp, "unit");
if usejava("jvm")
    assert(logical(plots.Ok), "Measured SINR plot generation did not report Ok=true.");
    for p = string(plots.Plots(:)).'
        assert(exist(p, "file") == 2, "Missing measured SINR plot: %s", p);
    end
    lineagePath = fullfile(tmp, "reports", "csv", "measurement_sinr_plot_lineage.csv");
    assert(exist(lineagePath, "file") == 2, "Missing measured SINR plot lineage CSV.");
    lineage = readtable(lineagePath, "VariableNamingRule", "preserve");
    assert(height(lineage) == 5 && all(logical(lineage.ImageExists)) && all(logical(lineage.SourceExists)), ...
        "Measured SINR plot lineage must cover all five generated measured-SINR plots and their source CSVs.");
    assert(all(strlength(string(lineage.GeneratorFunction)) > 0), ...
        "Measured SINR plot lineage must name each plot generator function.");
end
localAssertRelabeledAnalytics(tmp);

ok = true;
end

function localAssertGateOk(tmp, fileName, flagName)
path = fullfile(tmp, "reports", "csv", fileName);
assert(exist(path, "file") == 2, "Missing KPI reconciliation gate CSV: %s", fileName);
T = readtable(path, "VariableNamingRule", "preserve");
assert(ismember(flagName, string(T.Properties.VariableNames)), ...
    "Gate CSV %s is missing flag %s.", fileName, flagName);
assert(localAsLogical(T.(flagName)(1)), "KPI reconciliation gate did not pass: %s", flagName);
assert(ismember("KPIFormulaVersion", string(T.Properties.VariableNames)) && ...
    string(T.KPIFormulaVersion(1)) == "measured_sinr_geometry_v1", ...
    "Gate CSV %s must carry measured_sinr_geometry_v1.", fileName);
end

function localWriteLegacyAnalyticsFiles(tmp)
csvDir = fullfile(tmp, "analytics", "csv");
imgDir = fullfile(tmp, "analytics", "image");
sixgr.util.ensureFolder(csvDir);
sixgr.util.ensureFolder(imgDir);
legacy = [
    "contract__error-reliability-analytics__bler-vs-snr", "BLER vs SNR";
    "contract__throughput-goodput-spectral-efficiency-analytics__throughput-vs-snr", "throughput vs SNR"
    ];
for i = 1:size(legacy, 1)
    T = table(repmat(legacy(i, 2), 2, 1), [0; 1], [0.5; 0.25], ...
        'VariableNames', {'chart_name','SNR_dB','MetricValue'});
    writetable(T, fullfile(csvDir, legacy(i, 1) + ".csv"));
    fid = fopen(fullfile(imgDir, legacy(i, 1) + ".svg"), "w");
    assert(fid > 0, "Could not create legacy analytics SVG fixture.");
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fwrite(fid, char("<svg><text>" + legacy(i, 2) + "</text><text>Applied AWGN SNR (dB)</text></svg>"));
end
end

function localAssertRelabeledAnalytics(tmp)
csvDir = fullfile(tmp, "analytics", "csv");
imgDir = fullfile(tmp, "analytics", "image");
specs = [
    "contract__error-reliability-analytics__bler-vs-snr", "contract__error-reliability-analytics__bler-vs-measured-sinr";
    "contract__throughput-goodput-spectral-efficiency-analytics__throughput-vs-snr", "contract__throughput-goodput-spectral-efficiency-analytics__throughput-vs-measured-sinr"
    ];
for i = 1:size(specs, 1)
    for stem = specs(i, :)
        csvPath = fullfile(csvDir, stem + ".csv");
        assert(exist(csvPath, "file") == 2, "Missing relabeled analytics CSV: %s", stem);
        T = readtable(csvPath, "VariableNamingRule", "preserve", "TextType", "string");
        assert(contains(lower(string(T.chart_name(1))), "measured") && ...
            ismember("PostEqSINR_dB", string(T.Properties.VariableNames)) && ...
            ~ismember("SNR_dB", string(T.Properties.VariableNames)), ...
            "Analytics CSV must be relabeled to measured PostEq SINR without SNR_dB injection axis: %s", stem);
        svgPath = fullfile(imgDir, stem + ".svg");
        assert(exist(svgPath, "file") == 2, "Missing relabeled analytics SVG: %s", stem);
        txt = string(fileread(svgPath));
        assert(contains(txt, "Measured PostEq SINR (dB)") && ~contains(txt, "Applied AWGN"), ...
            "Analytics SVG must relabel the x-axis to measured PostEq SINR: %s", stem);
    end
end
end

function T = localTrialTable(direction)
n = 12;
ue = repmat([1; 2], n / 2, 1);
slot = (0:n-1).';
sinr = linspace(-2, 18, n).';
crcPass = sinr > 2 | ue == 1;
goodBits = double(crcPass) .* 1000;
bitErrors = double(~crcPass) .* 40;
distance = 80 + ue .* 100 + slot .* 3;
T = table( ...
    repmat(string(direction), n, 1), ...
    slot, ...
    floor(slot ./ 20), ...
    ue, ...
    1000 + ue, ...
    repmat(18, n, 1), ...
    repmat(18, n, 1), ...
    sinr, ...
    localPostEqStatus(direction, n), ...
    true(n, 1), ...
    false(n, 1), ...
    false(n, 1), ...
    crcPass, ...
    goodBits, ...
    repmat(1200, n, 1), ...
    repmat(1000, n, 1), ...
    bitErrors, ...
    goodBits ./ 0.5e-3 ./ 1e6, ...
    repmat(1200, n, 1) ./ 0.5e-3 ./ 1e6, ...
    repmat(0.035, n, 1), ...
    repmat(10.2, n, 1), ...
    repmat(0.5, n, 1), ...
    distance, ...
    sinr - 1, ...
    sinr - 0.5, ...
    90 + distance * 0.02, ...
    repmat(4, n, 1), ...
    4 + mod(slot, 12), ...
    repmat("16QAM", n, 1), ...
    1 + mod(ue, 2), ...
    'VariableNames', {'Direction','Slot','Frame','UEIndex','RNTI','ConfiguredSNR_dB','AppliedAWGNSNR_dB', ...
    'PostEqSINR_dB','PostEqSINRValueStatus','FinalizedFlag','IsWarmupFrame','FallbackFlag','CRCPass', ...
    'GoodBits','OfferedBits','BitsCompared','BitErrors','Goodput_Mbps','OfferedThroughput_Mbps', ...
    'EVM_rms','PAPR_dB','ProcedureDelay_ms', ...
    'PropagationDistance_m','LargeScaleSINR_dB','ReceiverHestSINR_dB','AppliedPathloss_dB', ...
    'AppliedShadowFading_dB','MCS','Modulation','Layers'});
end

function status = localPostEqStatus(direction, n)
if strcmpi(string(direction), "UL")
    status = repmat("OK_decision_residual_bounded", n, 1);
else
    status = repmat("OK", n, 1);
end
end

function T = localPBCHTrialTable()
n = 4;
T = table((0:n-1).', zeros(n,1), repmat([1;2], n/2, 1), 65520 + (1:n).', ...
    true(n,1), linspace(8, 16, n).', repmat("PASS", n, 1), ...
    'VariableNames', {'Frame','Slot','UEIndex','RNTI','SIB1StrictOk','PostEqSINR_dB','Status'});
end

function T = localPRACHTrialTable()
n = 5;
T = table(zeros(n,1), (0:n-1).', ones(n,1), 65520 + (1:n).', ...
    true(n,1), false(n,1), false(n,1), 18 + (0:n-1).', repmat("PASS", n, 1), ...
    'VariableNames', {'Frame','Slot','UEIndex','RNTI','PreambleDetected','MissedDetection', ...
    'FalseAlarm','PeakToNoiseRatio_dB','Status'});
end

function T = localSRSTrialTable()
n = 6;
T = table(zeros(n,1), (0:n-1).', repmat([1;2], n/2, 1), 4660 + (1:n).', ...
    true(n,1), -12 + (0:n-1).' * 0.25, linspace(5, 15, n).', repmat("PASS", n, 1), ...
    'VariableNames', {'Frame','Slot','UEIndex','RNTI','DetectionSuccess','NMSE_dB','PostEqSINR_dB','Status'});
end

function tf = localAsLogical(value)
if islogical(value)
    tf = logical(value(1));
elseif isnumeric(value)
    tf = double(value(1)) ~= 0;
else
    token = lower(strtrim(string(value(1))));
    tf = token == "1" || token == "true" || token == "yes" || token == "pass";
end
end
