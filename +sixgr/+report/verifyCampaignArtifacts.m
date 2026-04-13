function out = verifyCampaignArtifacts(runFolder, summary, varargin)
%VERIFYCAMPAIGNARTIFACTS Verify campaign artifacts against an enabled-module scope.

p = inputParser;
p.addParameter("ModuleContext", struct(), @(x) isstruct(x) && isscalar(x));
p.addParameter("StrictMode", false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
p.parse(varargin{:});

ctx = localNormalizeContext(p.Results.ModuleContext);
strictMode = logical(p.Results.StrictMode);
layout = sixgr.report.resultLayout(runFolder);

spec = localArtifactSpec(ctx);
n = numel(spec);
rows = repmat(struct( ...
    "Category", "", ...
    "ArtifactID", "", ...
    "Pattern", "", ...
    "Kind", "", ...
    "Required", true, ...
    "Exists", false, ...
    "FoundCount", 0, ...
    "Status", "", ...
    "Notes", ""), n, 1);

for i = 1:n
    ptn = fullfile(runFolder, char(spec(i).Pattern));
    d = dir(ptn);
    d = d(~[d.isdir]);
    found = numel(d);
    existsNow = found > 0;
    required = logical(spec(i).Required);
    if existsNow
        status = "ok";
    elseif required
        status = "missing_required";
    else
        status = "missing_optional";
    end
    rows(i) = struct( ...
        "Category", string(spec(i).Category), ...
        "ArtifactID", string(spec(i).ArtifactID), ...
        "Pattern", string(spec(i).Pattern), ...
        "Kind", string(spec(i).Kind), ...
        "Required", required, ...
        "Exists", existsNow, ...
        "FoundCount", found, ...
        "Status", status, ...
        "Notes", string(spec(i).Notes));
end

T = struct2table(rows);
reqMask = logical(T.Required);
reqCov = 1;
if any(reqMask)
    reqCov = mean(double(T.Exists(reqMask)));
end
covPct = 100 * reqCov;
missingN = sum(reqMask & ~T.Exists);

csvFile = layout.ArtifactChecklistCSV;
sixgr.util.csvWriteTable(csvFile, T);
mdFile = layout.ArtifactChecklistMD;
localWriteArtifactChecklistMD(mdFile, T, covPct, missingN);

requiredOutputs = localBuildRequiredOutputList(runFolder, summary, spec);
requiredOutputCheck = sixgr.report.checkRequiredOutputs(runFolder, requiredOutputs);
requiredOutputCovPct = 100;
if ~isempty(requiredOutputCheck.Table)
    requiredOutputCovPct = 100 * mean(double(requiredOutputCheck.Table.Exists));
end
requiredCSV = layout.RequiredOutputsCSV;
sixgr.util.csvWriteTable(requiredCSV, requiredOutputCheck.Table);

out = struct();
out.Ok = (missingN == 0) && logical(requiredOutputCheck.Ok);
out.Table = T;
out.CSV = csvFile;
out.MD = mdFile;
out.Coverage_pct = covPct;
out.MissingCount = double(missingN);
out.RequiredOutputsTable = requiredOutputCheck.Table;
out.RequiredOutputsCSV = requiredCSV;
out.RequiredOutputCoverage_pct = double(requiredOutputCovPct);
out.RequiredOutputMissingCount = double(requiredOutputCheck.MissingCount);
out.MissingRequiredOutputs = string(requiredOutputCheck.Missing);

if strictMode && ~out.Ok
    issues = strings(0,1);
    if missingN > 0
        issues(end+1,1) = "artifact_patterns_missing=" + string(missingN); %#ok<AGROW>
    end
    if requiredOutputCheck.MissingCount > 0
        issues(end+1,1) = "required_outputs_missing=" + strjoin(cellstr(string(requiredOutputCheck.Missing)), ", "); %#ok<AGROW>
    end
    error("sixgr:report:ArtifactCompletenessFailed", ...
        "Strict artifact completeness check failed: %s", strjoin(cellstr(issues), " | "));
end
end

function ctx = localNormalizeContext(in)
defaults = struct( ...
    "IncludeRun", true, ...
    "IncludeReproMeta", true, ...
    "IncludeCalibration", true, ...
    "IncludeStructuredManifest", false, ...
    "IncludeLink", true, ...
    "IncludeControl", true, ...
    "IncludeAuxiliary", false, ...
    "IncludeMMTC", false, ...
    "IncludeSystem", true, ...
    "IncludeE2E", true, ...
    "IncludeCampaignPlots", false, ...
    "IncludeSystemFigures", false, ...
    "IncludeE2EFigures", false);

ctx = defaults;
if nargin >= 1 && isstruct(in) && isscalar(in)
    fields = string(fieldnames(defaults));
    for i = 1:numel(fields)
        fn = char(fields(i));
        if isfield(in, fn)
            ctx.(fn) = logical(in.(fn));
        end
    end
end

if ~(ctx.IncludeLink || ctx.IncludeE2E)
    ctx.IncludeControl = false;
end
if ~ctx.IncludeSystem
    ctx.IncludeSystemFigures = false;
end
if ~ctx.IncludeE2E
    ctx.IncludeE2EFigures = false;
end
end

function requiredOutputs = localBuildRequiredOutputList(runFolder, summary, spec)
requiredOutputs = strings(0,1);
for i = 1:numel(spec)
    pat = string(spec(i).Pattern);
    if logical(spec(i).Required) && strlength(pat) > 0 && ~localPatternHasWildcard(pat)
        requiredOutputs(end+1,1) = string(fullfile(runFolder, char(pat))); %#ok<AGROW>
    end
end

summaryFields = [ ...
    "LogFile", "AuditCSV", ...
    "CalibrationDBMat", "CalibrationMetadataJSON", "CalibrationCoverageCSV", "CalibrationValidationCSV", ...
    "MetaRunManifestJSON", "MetaEnvironmentJSON", "MetaSeedsCSV", "MetaApproximationsCSV", "MetaCalibrationSourceJSON", ...
    "E2ESlotMetricsCSV", "E2EComponentIOCSV", "E2EComponentChecksCSV", ...
    "E2ESummaryCSV", "E2EAIMetricsCSV", "E2EPacketIntegrityCSV", ...
    "E2EPacketTraceCSV", "E2EFlowSummaryCSV", "E2EBearerSummaryCSV", "E2EAttachTraceCSV", ...
    "E2ESchedulerTraceCSV", "E2EHARQTraceCSV", "E2EDropCausesCSV", "E2EMAT"];
for i = 1:numel(summaryFields)
    fieldName = summaryFields(i);
    if isfield(summary, fieldName)
        pathValue = string(summary.(char(fieldName)));
        pathValue = strtrim(pathValue);
        if strlength(pathValue) > 0
            requiredOutputs(end+1,1) = pathValue; %#ok<AGROW>
        end
    end
end

layout = sixgr.report.resultLayout(runFolder);
requiredOutputs(end+1,1) = string(layout.ConfigResolvedJSON); %#ok<AGROW>
requiredOutputs = unique(requiredOutputs(strlength(requiredOutputs) > 0), "stable");
end

function tf = localPatternHasWildcard(pattern)
pattern = char(string(pattern));
tf = contains(pattern, "*") || contains(pattern, "?");
end

function S = localArtifactSpec(ctx)
S = repmat(struct("Category","","ArtifactID","","Pattern","","Kind","","Required",true,"Notes",""), 0, 1);

if ctx.IncludeRun
    S(end+1) = localSpec("Run", "run_log", "logs/full_campaign.log", "log", true, "Top-level campaign log");
    S(end+1) = localSpec("Run", "run_report_mat", "reports/mat/full_campaign_report.mat", "mat", true, "Top-level report MAT");
    S(end+1) = localSpec("Run", "run_report_md", "reports/full_campaign_report.md", "md", true, "Top-level report markdown");
    S(end+1) = localSpec("Run", "category_audit", "reports/csv/full_3gpp_category_audit.csv", "csv", true, "25-category audit table");
    S(end+1) = localSpec("Run", "structured_manifest", "analysis_by_block/run/meta/structured_manifest.csv", "csv", ctx.IncludeStructuredManifest, "Structured manifest (when organizer is enabled)");
    S(end+1) = localSpec("Run", "campaign_plots", "reports/image/campaign_*.png", "fig", ctx.IncludeCampaignPlots, "Campaign-level synthesized plots");
end

if ctx.IncludeReproMeta
    S(end+1) = localSpec("Run", "meta_run_manifest", "meta/run_manifest.json", "json", true, "Run-level reproducibility manifest");
    S(end+1) = localSpec("Run", "meta_environment", "meta/environment.json", "json", true, "MATLAB/host/toolbox environment snapshot");
    S(end+1) = localSpec("Run", "meta_seeds", "meta/seeds.csv", "csv", true, "Seed table for deterministic replay");
    S(end+1) = localSpec("Run", "meta_approximations", "meta/approximations_used.csv", "csv", true, "Approximations/proxy modes used in run");
end

if ctx.IncludeCalibration
    S(end+1) = localSpec("Run", "calibration_bler_db_mat", "calibration/bler_db.mat", "mat", true, "Calibration BLER DB MAT");
    S(end+1) = localSpec("Run", "calibration_bler_db_metadata", "calibration/bler_db_metadata.json", "json", true, "Calibration BLER DB metadata");
    S(end+1) = localSpec("Run", "calibration_coverage", "calibration/calibration_coverage.csv", "csv", true, "Calibration coverage summary");
    S(end+1) = localSpec("Run", "calibration_validation", "calibration/calibration_validation.csv", "csv", true, "Calibration validation metrics");
    S(end+1) = localSpec("Run", "meta_calibration_source", "meta/calibration_source.json", "json", true, "Calibration provenance snapshot");
end

if ctx.IncludeLink
    S(end+1) = localSpec("1. Error Performance Metrics", "lls_kpi", "air_interface/csv/lls_kpi_summary.csv", "csv", true, "BER/BLER summary");
    S(end+1) = localSpec("1. Error Performance Metrics", "dl_pdsch_trials", "air_interface/csv/dl_pdsch_trials.csv", "csv", true, "Per-trial DL PDSCH trace");
    S(end+1) = localSpec("1. Error Performance Metrics", "ul_pusch_trials", "air_interface/csv/ul_pusch_trials.csv", "csv", true, "Per-trial UL PUSCH trace");
    S(end+1) = localSpec("1. Error Performance Metrics", "pdcch_trials", "air_interface/csv/pdcch_trials.csv", "csv", true, "Per-trial PDCCH trace");
    S(end+1) = localSpec("1. Error Performance Metrics", "pucch_trials", "air_interface/csv/pucch_trials.csv", "csv", true, "Per-trial PUCCH trace");
    S(end+1) = localSpec("1. Error Performance Metrics", "pbch_trials", "air_interface/csv/pbch_trials.csv", "csv", true, "Per-trial PBCH trace");
    S(end+1) = localSpec("1. Error Performance Metrics", "prach_trials", "air_interface/csv/prach_trials.csv", "csv", true, "Per-trial PRACH trace");
    S(end+1) = localSpec("1. Error Performance Metrics", "srs_trials", "air_interface/csv/srs_trials.csv", "csv", true, "Per-trial SRS trace");
    S(end+1) = localSpec("2. Throughput and Rate Metrics", "lls_snr", "air_interface/csv/lls_snr_sweep.csv", "csv", true, "Throughput vs SNR");
    S(end+1) = localSpec("4. Channel Estimation and Equalization", "lls_link_results", "air_interface/mat/link_results.mat", "mat", true, "Channel/equalization artifacts");
    S(end+1) = localSpec("6. Link Adaptation", "snr_sweep", "air_interface/csv/lls_snr_sweep.csv", "csv", true, "MCS adaptation proxy");
end

if ctx.IncludeAuxiliary
    S(end+1) = localSpec("3. Signal Quality and CSI", "sync_ctrl", "control/csv/probe_sync_control.csv", "csv", true, "SNR/control quality probes");
    S(end+1) = localSpec("5. MIMO and Beamforming", "beam_mimo", "beamforming/csv/probe_beam_mimo.csv", "csv", true, "MIMO/beam probe");
    S(end+1) = localSpec("7. HARQ and Retransmissions", "harq_summary", "harq/csv/probe_harq_summary.csv", "csv", true, "HARQ summary");
    S(end+1) = localSpec("8. Latency and Timing", "harq_packets", "harq/csv/probe_harq_packets.csv", "csv", true, "RTT/processing delay proxy");
    S(end+1) = localSpec("9. Power and Energy Efficiency", "rf_energy", "rf/csv/probe_rf_energy.csv", "csv", true, "Energy/power probe");
    S(end+1) = localSpec("10. Synchronization and Timing Offsets", "sync", "control/csv/probe_sync_control.csv", "csv", true, "Sync metrics");
    S(end+1) = localSpec("11. Channel Coding and Decoding", "harq_packets_dup", "harq/csv/probe_harq_packets.csv", "csv", true, "Decoder iterations");
    S(end+1) = localSpec("12. Modulation and Waveform Quality", "rf_energy_dup", "rf/csv/probe_rf_energy.csv", "csv", true, "EVM/PAPR proxy");
    S(end+1) = localSpec("13. Interference Analysis", "sir_bler", "interference/csv/probe_interference_sir_bler.csv", "csv", true, "Interference probe");
    S(end+1) = localSpec("16. Beam Management", "beam_mimo_dup", "beamforming/csv/probe_beam_mimo.csv", "csv", true, "Beam tracking/selection proxy");
    S(end+1) = localSpec("17. Waveform and Numerology Specifics", "numerology", "numerology/csv/probe_numerology.csv", "csv", true, "Numerology sweep");
    S(end+1) = localSpec("18. Control Channel and Random Access", "sync_dup", "control/csv/probe_sync_control.csv", "csv", true, "PDCCH/PUCCH/PRACH");
    S(end+1) = localSpec("19. Hardware Impairments", "rf_dup", "rf/csv/probe_rf_energy.csv", "csv", true, "RF impairment probe");
    S(end+1) = localSpec("20. Reliability and Outage", "harq_summary_dup", "harq/csv/probe_harq_summary.csv", "csv", true, "Residual BLER/outage proxy");
    S(end+1) = localSpec("22. V2X Metrics", "v2x", "v2x/csv/probe_v2x_sidelink.csv", "csv", true, "V2X sidelink KPIs");
    S(end+1) = localSpec("23. NTN Metrics", "ntn", "ntn/csv/probe_ntn_delay_doppler.csv", "csv", true, "NTN KPIs");
end

if ctx.IncludeSystem
    S(end+1) = localSpec("13. Interference Analysis", "sys_interference_detail", "system/csv/system_interference_detail.csv", "csv", true, "Per-UE interference decomposition trace");
    S(end+1) = localSpec("14. Mobility and Time-Varying Channels", "sys_timeseries", "system/csv/system_time_series.csv", "csv", true, "Mobility time series");
    S(end+1) = localSpec("14. Mobility and Time-Varying Channels", "sys_handover_events", "system/csv/system_handover_events.csv", "csv", true, "Handover events and interruption timing");
    S(end+1) = localSpec("14. Mobility and Time-Varying Channels", "sys_beam_events", "system/csv/system_beam_events.csv", "csv", true, "Beam update/switch event log");
    S(end+1) = localSpec("15. Multi-User and Multi-Cell Metrics", "sys_kpi", "system/csv/system_kpis.csv", "csv", true, "System KPIs");
    S(end+1) = localSpec("15. Multi-User and Multi-Cell Metrics", "sys_cell_load", "system/csv/system_cell_load.csv", "csv", true, "Per-cell offered/served/queued load");
    S(end+1) = localSpec("15. Multi-User and Multi-Cell Metrics", "sys_scheduler_grants", "system/csv/system_scheduler_grants.csv", "csv", true, "Per-grant scheduler trace");
    S(end+1) = localSpec("15. Multi-User and Multi-Cell Metrics", "sys_harq_processes", "system/csv/system_harq_processes.csv", "csv", true, "HARQ process outcomes by grant");
    S(end+1) = localSpec("25. Miscellaneous Statistical Outputs", "sys_fig", "system/image/*.png", "fig", ctx.IncludeSystemFigures, "Time-series/CDF plots");
end

if ctx.IncludeMMTC
    S(end+1) = localSpec("21. Massive MTC Metrics", "mmtc", "mmtc/csv/probe_mmtc_kpis.csv", "csv", true, "mMTC KPIs");
end

if ctx.IncludeControl
    S(end+1) = localSpec("1. Error Performance Metrics", "control_cell_search_trials", "control/csv/cell_search_trials.csv", "csv", true, "Control-plane cell-search trial trace");
    S(end+1) = localSpec("1. Error Performance Metrics", "control_pbch_recovery_trials", "control/csv/pbch_recovery_trials.csv", "csv", true, "Control-plane PBCH recovery trial trace");
    S(end+1) = localSpec("1. Error Performance Metrics", "control_prach_trials", "control/csv/prach_trials.csv", "csv", true, "Control-plane PRACH trial trace");
    S(end+1) = localSpec("1. Error Performance Metrics", "control_pdcch_trials", "control/csv/pdcch_trials.csv", "csv", true, "Control-plane PDCCH trial trace");
    S(end+1) = localSpec("1. Error Performance Metrics", "control_pucch_trials", "control/csv/pucch_trials.csv", "csv", true, "Control-plane PUCCH trial trace");
    S(end+1) = localSpec("18. Control Channel and Random Access", "attach_state_trace", "control/csv/attach_state_trace.csv", "csv", true, "Attach state transition trace");
    S(end+1) = localSpec("18. Control Channel and Random Access", "rrc_message_trace", "control/csv/rrc_message_trace.csv", "csv", true, "RRC message sequence trace");
end

if ctx.IncludeE2E
    S(end+1) = localSpec("24. Protocol and Stack Interactions", "e2e_summary", "packet_flow/csv/probe_e2e_summary.csv", "csv", true, "Cross-layer KPIs");
    S(end+1) = localSpec("24. Protocol and Stack Interactions", "e2e_packet_integrity", "packet_flow/csv/probe_e2e_packet_integrity.csv", "csv", true, "Packet-level integrity and deadline checks");
    S(end+1) = localSpec("24. Protocol and Stack Interactions", "e2e_packet_trace", "packet_flow/csv/e2e_packet_trace.csv", "csv", true, "Per-packet E2E trace");
    S(end+1) = localSpec("24. Protocol and Stack Interactions", "e2e_flow_summary", "packet_flow/csv/e2e_flow_summary.csv", "csv", true, "Per-flow E2E packet summary");
    S(end+1) = localSpec("24. Protocol and Stack Interactions", "e2e_bearer_summary", "packet_flow/csv/e2e_bearer_summary.csv", "csv", true, "Per-bearer E2E packet summary");
    S(end+1) = localSpec("24. Protocol and Stack Interactions", "e2e_attach_trace", "packet_flow/csv/e2e_attach_trace.csv", "csv", true, "Attach control-plane event trace");
    S(end+1) = localSpec("24. Protocol and Stack Interactions", "e2e_harq_trace", "packet_flow/csv/e2e_harq_trace.csv", "csv", true, "HARQ transmission outcomes");
    S(end+1) = localSpec("24. Protocol and Stack Interactions", "e2e_scheduler_trace", "packet_flow/csv/e2e_scheduler_trace.csv", "csv", true, "Scheduler grant-level trace");
    S(end+1) = localSpec("24. Protocol and Stack Interactions", "e2e_drop_causes", "packet_flow/csv/e2e_drop_causes.csv", "csv", true, "Packet drop-cause summary");
    S(end+1) = localSpec("24. Protocol and Stack Interactions", "e2e_figures", "packet_flow/image/*.png", "fig", ctx.IncludeE2EFigures, "E2E figure set (when E2ESaveFigures=true)");
end
end

function r = localSpec(cat, id, pat, kind, req, notes)
r = struct();
r.Category = string(cat);
r.ArtifactID = string(id);
r.Pattern = string(pat);
r.Kind = string(kind);
r.Required = logical(req);
r.Notes = string(notes);
end

function localWriteArtifactChecklistMD(mdFile, T, covPct, missingN)
fid = fopen(mdFile, "w");
if fid < 0
    return;
end
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "# Artifact Checklist\n\n");
fprintf(fid, "- Required coverage: `%.2f%%`\n", covPct);
fprintf(fid, "- Missing required items: `%d`\n\n", missingN);
fprintf(fid, "| Category | Artifact | Pattern | Exists | FoundCount | Status |\n");
fprintf(fid, "|---|---|---|---:|---:|---|\n");
for i = 1:height(T)
    fprintf(fid, "| %s | %s | `%s` | %d | %d | %s |\n", ...
        char(T.Category(i)), char(T.ArtifactID(i)), char(T.Pattern(i)), ...
        double(T.Exists(i)), double(T.FoundCount(i)), char(T.Status(i)));
end
end
