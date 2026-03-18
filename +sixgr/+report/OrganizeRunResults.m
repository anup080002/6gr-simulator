function out = OrganizeRunResults(runFolder, varargin)
% sixgr.report.OrganizeRunResults
% Build a block-wise analysis tree from one campaign run folder.
%
% Input:
%   runFolder: campaign folder, e.g. results/full3gpp_YYYYMMDD_HHMMSS
%
% Name-value:
%   "ResultsRoot"           : root results path (used for mirror folder)
%   "StructuredFolderName"  : subfolder created under runFolder
%   "MirrorToResultsRoot"   : copy structured tree to resultsRoot/by_block/<runName>
%
% Output:
%   out struct with paths to generated manifests and folders.

ip = inputParser;
ip.addRequired("runFolder", @(x)ischar(x) || isstring(x));
ip.addParameter("ResultsRoot", "", @(x)ischar(x) || isstring(x));
ip.addParameter("StructuredFolderName", "analysis_by_block", @(x)ischar(x) || isstring(x));
ip.addParameter("MirrorToResultsRoot", true, @(x)islogical(x) || (isnumeric(x) && isscalar(x)));
ip.parse(runFolder, varargin{:});
opt = ip.Results;

runFolder = char(string(opt.runFolder));
if ~isfolder(runFolder)
    error("sixgr:report:OrganizeRunResults:BadRunFolder", ...
        "Run folder does not exist: %s", runFolder);
end
runFolder = localCanonicalPath(runFolder);

resultsRoot = char(string(opt.ResultsRoot));
if strlength(string(resultsRoot)) == 0
    resultsRoot = fileparts(runFolder);
end
resultsRoot = localCanonicalPath(resultsRoot);

[~, runName] = fileparts(runFolder);
structuredRoot = fullfile(runFolder, char(string(opt.StructuredFolderName)));

blockDirs = { ...
    "run/meta", ...
    "logs", ...
    "phy/channel", ...
    "phy/sync", ...
    "phy/dl/pdsch", ...
    "phy/dl/pdcch", ...
    "phy/dl/ssb_pbch", ...
    "phy/ul/pusch", ...
    "phy/ul/pucch", ...
    "phy/ul/prach", ...
    "phy/ul/srs", ...
    "phy/harq", ...
    "phy/mimo_beamforming", ...
    "phy/waveform_numerology", ...
    "phy/rf_impairments", ...
    "protocol/mac", ...
    "protocol/rlc", ...
    "protocol/pdcp", ...
    "protocol/sdap", ...
    "protocol/rrc", ...
    "system/mobility", ...
    "system/interference", ...
    "system/mmtc", ...
    "system/v2x", ...
    "system/ntn", ...
    "cross_layer/e2e", ...
    "cross_layer/e2e/validation" ...
    };

for i = 1:numel(blockDirs)
    sixgr.util.ensureDir(fullfile(structuredRoot, char(blockDirs{i}), ".keep"));
end

records = repmat(struct( ...
    "Block", "", ...
    "Kind", "", ...
    "SourceRelPath", "", ...
    "TargetRelPath", "", ...
    "Notes", ""), 0, 1);

% -------------------------------------------------------------------------
% Base copies (raw campaign artifacts -> block folders)
% -------------------------------------------------------------------------
localCopy("config_resolved_full_campaign.json", "run/meta", "config_resolved_full_campaign.json", "json", "Resolved run config");
localCopy("full_campaign_report.md", "run/meta", "full_campaign_report.md", "md", "Campaign summary report");
localCopy("mat/full_campaign_report.mat", "run/meta", "full_campaign_report.mat", "mat", "Campaign MAT payload");
localCopy("csv/full_3gpp_category_audit.csv", "run/meta", "full_3gpp_category_audit.csv", "csv", "25-category audit");
localCopy("meta/run_manifest.json", "run/meta", "run_manifest.json", "json", "Run-level reproducibility manifest");
localCopy("meta/environment.json", "run/meta", "environment.json", "json", "MATLAB/host/toolbox environment snapshot");
localCopy("meta/seeds.csv", "run/meta", "seeds.csv", "csv", "Per-component seed table");
localCopy("meta/approximations_used.csv", "run/meta", "approximations_used.csv", "csv", "Approximations/proxy modes used");
localCopy("meta/calibration_source.json", "run/meta", "calibration_source.json", "json", "Calibration provenance metadata");

localCopy("logs/full_campaign.log", "logs", "full_campaign.log", "log", "Top-level campaign log");
localCopy("link/logs/run.log", "logs", "link_run.log", "log", "Link runner log");
localCopy("detailed_lls/logs/run.log", "logs", "detailed_lls_run.log", "log", "Detailed LLS log");
localCopy("system/logs/run.log", "logs", "system_run.log", "log", "System runner log");
localCopy("system_mmtc/logs/run.log", "logs", "system_mmtc_run.log", "log", "mMTC runner log");

localCopy("link/csv/lls_snr_sweep.csv", "phy/channel", "lls_snr_sweep.csv", "csv", "PHY SNR sweep");
localCopy("link/csv/lls_kpi_summary.csv", "phy/channel", "lls_kpi_summary.csv", "csv", "Link KPI summary");
localCopy("detailed_lls/csv/detailed_lls_summary.csv", "phy/channel", "detailed_lls_summary.csv", "csv", "Detailed PHY diagnostics");
localCopy("link/mat/link_results.mat", "phy/channel", "link_results.mat", "mat", "Link-level MAT");
localCopy("detailed_lls/mat/link_results.mat", "phy/channel", "detailed_link_results.mat", "mat", "Detailed link MAT");
localCopy("detailed_lls/mat/detailed_lls_summary.mat", "phy/channel", "detailed_lls_summary.mat", "mat", "Detailed diagnostics MAT");

localCopy("csv/probe_sync_control.csv", "phy/sync", "probe_sync_control.csv", "csv", "Sync/control probe");
localCopy("control/csv/cell_search_trials.csv", "phy/dl/ssb_pbch", "cell_search_trials.csv", "csv", "Control-plane cell search trial trace");
localCopy("control/csv/pbch_recovery_trials.csv", "phy/dl/ssb_pbch", "pbch_recovery_trials.csv", "csv", "Control-plane PBCH recovery trial trace");
localCopy("control/csv/prach_trials.csv", "phy/ul/prach", "prach_trials.csv", "csv", "Control-plane PRACH trial trace");
localCopy("control/csv/pdcch_trials.csv", "phy/dl/pdcch", "pdcch_trials.csv", "csv", "Control-plane PDCCH trial trace");
localCopy("control/csv/pucch_trials.csv", "phy/ul/pucch", "pucch_trials.csv", "csv", "Control-plane PUCCH trial trace");
localCopy("control/csv/attach_state_trace.csv", "protocol/rrc", "attach_state_trace.csv", "csv", "Attach state transition trace");
localCopy("control/csv/rrc_message_trace.csv", "protocol/rrc", "rrc_message_trace.csv", "csv", "RRC message trace");
localCopy("csv/probe_harq_packets.csv", "phy/harq", "probe_harq_packets.csv", "csv", "HARQ packet outcomes");
localCopy("csv/probe_harq_summary.csv", "phy/harq", "probe_harq_summary.csv", "csv", "HARQ summary");
localCopy("csv/probe_beam_mimo.csv", "phy/mimo_beamforming", "probe_beam_mimo.csv", "csv", "Beam and MIMO probe");
localCopy("csv/probe_numerology.csv", "phy/waveform_numerology", "probe_numerology.csv", "csv", "Numerology probe");
localCopy("csv/probe_rf_energy.csv", "phy/rf_impairments", "probe_rf_energy.csv", "csv", "RF impairment + energy probe");

localCopy("csv/probe_interference_sir_bler.csv", "system/interference", "probe_interference_sir_bler.csv", "csv", "Interference probe");
localCopy("csv/probe_mmtc_kpis.csv", "system/mmtc", "probe_mmtc_kpis.csv", "csv", "mMTC KPIs");
localCopy("csv/probe_v2x_sidelink.csv", "system/v2x", "probe_v2x_sidelink.csv", "csv", "V2X sidelink probe");
localCopy("csv/probe_ntn_delay_doppler.csv", "system/ntn", "probe_ntn_delay_doppler.csv", "csv", "NTN delay/doppler probe");

localCopy("system/csv/system_kpis.csv", "system/mobility", "system_kpis.csv", "csv", "System KPIs");
localCopy("system/csv/system_ue_summary.csv", "system/mobility", "system_ue_summary.csv", "csv", "UE summary");
localCopy("system/csv/system_time_series.csv", "system/mobility", "system_time_series.csv", "csv", "Time-series KPIs");
localCopy("system/csv/system_algo_processing.csv", "system/mobility", "system_algo_processing.csv", "csv", "Algorithm processing counters");
localCopy("system/csv/system_scheduler_grants.csv", "system/mobility", "system_scheduler_grants.csv", "csv", "Per-grant scheduler trace");
localCopy("system/csv/system_harq_processes.csv", "system/mobility", "system_harq_processes.csv", "csv", "HARQ process timeline");
localCopy("system/csv/system_cell_load.csv", "system/mobility", "system_cell_load.csv", "csv", "Per-cell load and queue trace");
localCopy("system/csv/system_handover_events.csv", "system/mobility", "system_handover_events.csv", "csv", "Handover event trace");
localCopy("system/csv/system_beam_events.csv", "system/mobility", "system_beam_events.csv", "csv", "Beam switch event trace");
localCopy("system/csv/system_interference_detail.csv", "system/interference", "system_interference_detail.csv", "csv", "Per-UE interference detail");
localCopy("system/mat/system_results.mat", "system/mobility", "system_results.mat", "mat", "System MAT");
localCopy("system/run_replay_system.m", "system/mobility", "run_replay_system.m", "m", "Replay script");
localCopyPattern("system/fig/*.png", "system/mobility", "", "fig", "System mobility figures");

localCopy("system_mmtc/csv/system_kpis.csv", "system/mmtc", "system_kpis.csv", "csv", "mMTC system KPIs");
localCopy("system_mmtc/csv/system_ue_summary.csv", "system/mmtc", "system_ue_summary.csv", "csv", "mMTC UE summary");
localCopy("system_mmtc/csv/system_time_series.csv", "system/mmtc", "system_time_series.csv", "csv", "mMTC time-series KPIs");
localCopy("system_mmtc/csv/system_algo_processing.csv", "system/mmtc", "system_algo_processing.csv", "csv", "mMTC algorithm counters");
localCopy("system_mmtc/csv/system_scheduler_grants.csv", "system/mmtc", "system_scheduler_grants.csv", "csv", "mMTC per-grant scheduler trace");
localCopy("system_mmtc/csv/system_harq_processes.csv", "system/mmtc", "system_harq_processes.csv", "csv", "mMTC HARQ process timeline");
localCopy("system_mmtc/csv/system_cell_load.csv", "system/mmtc", "system_cell_load.csv", "csv", "mMTC per-cell load trace");
localCopy("system_mmtc/csv/system_handover_events.csv", "system/mmtc", "system_handover_events.csv", "csv", "mMTC handover events");
localCopy("system_mmtc/csv/system_beam_events.csv", "system/mmtc", "system_beam_events.csv", "csv", "mMTC beam events");
localCopy("system_mmtc/csv/system_interference_detail.csv", "system/mmtc", "system_interference_detail.csv", "csv", "mMTC interference detail");
localCopy("system_mmtc/mat/system_results.mat", "system/mmtc", "system_results.mat", "mat", "mMTC MAT");
localCopy("system_mmtc/run_replay_system.m", "system/mmtc", "run_replay_system.m", "m", "mMTC replay script");
localCopyPattern("system_mmtc/fig/*.png", "system/mmtc", "mmtc_", "fig", "mMTC figures");

localCopy("csv/probe_e2e_slot_metrics.csv", "cross_layer/e2e", "probe_e2e_slot_metrics.csv", "csv", "E2E per-slot metrics");
localCopy("csv/probe_e2e_component_io.csv", "cross_layer/e2e", "probe_e2e_component_io.csv", "csv", "E2E per-component TX/RX byte counters");
localCopy("csv/probe_e2e_component_checks.csv", "cross_layer/e2e", "probe_e2e_component_checks.csv", "csv", "E2E component-level pass/fail checks");
localCopy("csv/probe_e2e_packet_integrity.csv", "cross_layer/e2e", "probe_e2e_packet_integrity.csv", "csv", "E2E packet integrity and deadline checks");
localCopy("csv/probe_e2e_component_io.csv", "cross_layer/e2e/validation", "probe_e2e_component_io.csv", "csv_primary", "PRIMARY E2E validation table: per-component TX/RX byte counters");
localCopy("csv/probe_e2e_component_checks.csv", "cross_layer/e2e/validation", "probe_e2e_component_checks.csv", "csv_primary", "PRIMARY E2E validation table: component-level pass/fail checks");
localCopy("csv/probe_e2e_packet_integrity.csv", "cross_layer/e2e/validation", "probe_e2e_packet_integrity.csv", "csv_primary", "PRIMARY E2E validation table: packet integrity and deadlines");
localCopy("csv/probe_e2e_summary.csv", "cross_layer/e2e", "probe_e2e_summary.csv", "csv", "E2E summary metrics");
localCopy("csv/probe_e2e_ai_metrics.csv", "cross_layer/e2e", "probe_e2e_ai_metrics.csv", "csv", "E2E AI probe metrics");
localCopy("end_to_end/csv/e2e_packet_trace.csv", "cross_layer/e2e", "e2e_packet_trace.csv", "csv", "E2E per-packet trace");
localCopy("end_to_end/csv/e2e_flow_summary.csv", "cross_layer/e2e", "e2e_flow_summary.csv", "csv", "E2E per-flow packet summary");
localCopy("end_to_end/csv/e2e_bearer_summary.csv", "cross_layer/e2e", "e2e_bearer_summary.csv", "csv", "E2E per-bearer packet summary");
localCopy("end_to_end/csv/e2e_attach_trace.csv", "cross_layer/e2e", "e2e_attach_trace.csv", "csv", "Attach control-plane trace");
localCopy("end_to_end/csv/e2e_harq_trace.csv", "cross_layer/e2e", "e2e_harq_trace.csv", "csv", "E2E HARQ trace");
localCopy("end_to_end/csv/e2e_scheduler_trace.csv", "cross_layer/e2e", "e2e_scheduler_trace.csv", "csv", "E2E scheduler grant trace");
localCopy("end_to_end/csv/e2e_drop_causes.csv", "cross_layer/e2e", "e2e_drop_causes.csv", "csv", "E2E packet drop causes");
localCopy("end_to_end/mat/e2e_probe.mat", "cross_layer/e2e", "e2e_probe.mat", "mat", "E2E MAT");
localCopyPattern("end_to_end/fig/*.png", "cross_layer/e2e", "", "fig", "E2E figures");
localCopyPattern("end_to_end/fig/*.pdf", "cross_layer/e2e", "", "fig", "E2E figures");

% -------------------------------------------------------------------------
% Derived per-block CSV extraction
% -------------------------------------------------------------------------
localExtractSyncControl();
localExtractLinkCases("link/csv/link_kpis.csv", "link");
localExtractLinkCases("detailed_lls/csv/link_kpis.csv", "detailed_lls");
localExtractE2EProtocols();
localWriteMessageFlow();
localWriteStructureReadme();
localWriteCoverageStatus();

manifestRel = fullfile("run", "meta", "structured_manifest.csv");
manifestAbs = fullfile(structuredRoot, manifestRel);
if isempty(records)
    manifestTable = table(string.empty(0,1), string.empty(0,1), string.empty(0,1), string.empty(0,1), string.empty(0,1), ...
        'VariableNames', {'Block','Kind','SourceRelPath','TargetRelPath','Notes'});
else
    manifestTable = struct2table(records);
end
sixgr.util.csvWriteTable(manifestAbs, manifestTable);

manifestJson = fullfile(structuredRoot, "run", "meta", "structured_manifest.json");
try
    sixgr.util.jsonWrite(manifestJson, table2struct(manifestTable));
catch
end

% -------------------------------------------------------------------------
% Mirror to central root: <resultsRoot>/by_block/<runName>
% -------------------------------------------------------------------------
mirrorFolder = "";
if logical(opt.MirrorToResultsRoot)
    mirrorFolder = fullfile(resultsRoot, "by_block", runName);
    localMirrorTree(structuredRoot, mirrorFolder);
    latestFile = fullfile(resultsRoot, "by_block", "LATEST.txt");
    sixgr.util.ensureDir(latestFile);
    fid = fopen(latestFile, "w");
    if fid >= 0
        c = onCleanup(@() fclose(fid)); %#ok<NASGU>
        fprintf(fid, "Latest structured run: %s\n", runName);
        fprintf(fid, "Run folder: %s\n", runFolder);
        fprintf(fid, "Structured folder: %s\n", structuredRoot);
        fprintf(fid, "Mirror folder: %s\n", mirrorFolder);
        fprintf(fid, "GeneratedUTC: %s\n", char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss''Z''')));
    end
end

out = struct();
out.Ok = true;
out.RunFolder = runFolder;
out.StructuredFolder = structuredRoot;
out.ManifestCSV = manifestAbs;
out.ManifestJSON = manifestJson;
out.NumRecords = height(manifestTable);
out.MirrorFolder = char(string(mirrorFolder));

% -------------------------------------------------------------------------
% nested helpers
% -------------------------------------------------------------------------
    function localCopy(relSrc, block, outName, kind, notes)
        src = fullfile(runFolder, char(relSrc));
        if exist(src, "file") ~= 2
            return;
        end
        if nargin < 3 || strlength(string(outName)) == 0
            [~, n, e] = fileparts(src);
            outName = n + e;
        end
        dst = fullfile(structuredRoot, char(block), char(string(outName)));
        localCopyFile(src, dst);
        localRecord(block, kind, relSrc, relativeToStructured(dst), notes);
    end

    function localCopyPattern(relPattern, block, prefix, kind, notes)
        absPattern = fullfile(runFolder, char(relPattern));
        files = dir(absPattern);
        for k = 1:numel(files)
            if files(k).isdir
                continue;
            end
            src = fullfile(files(k).folder, files(k).name);
            dstName = string(prefix) + string(files(k).name);
            dst = fullfile(structuredRoot, char(block), char(dstName));
            localCopyFile(src, dst);
            srcRel = relativeToRun(src);
            localRecord(block, kind, srcRel, relativeToStructured(dst), notes);
        end
    end

    function localExtractSyncControl()
        syncFile = fullfile(runFolder, "csv", "probe_sync_control.csv");
        if exist(syncFile, "file") ~= 2
            return;
        end
        try
            T = readtable(syncFile, "VariableNamingRule", "preserve");
        catch
            return;
        end
        if isempty(T)
            return;
        end

        localWriteSubset(T, ["SNR_dB","PDCCH_BLER","PDCCH_BER"], ...
            "phy/dl/pdcch/pdcch_metrics.csv", "csv", "csv/probe_sync_control.csv", "PDCCH metrics");
        localWriteSubset(T, ["SNR_dB","PUCCH_BLER","PUCCH_BER"], ...
            "phy/ul/pucch/pucch_metrics.csv", "csv", "csv/probe_sync_control.csv", "PUCCH metrics");
        localWriteSubset(T, ["SNR_dB","PRACH_DetectProb"], ...
            "phy/ul/prach/prach_detection_metrics.csv", "csv", "csv/probe_sync_control.csv", "PRACH detection metrics");
        localWriteSubset(T, ["SNR_dB","PBCH_DetectProb","TimingOffset_samples","CFO_EstError_Hz"], ...
            "phy/dl/ssb_pbch/ssb_pbch_sync_metrics.csv", "csv", "csv/probe_sync_control.csv", "SSB/PBCH sync metrics");
    end

    function localExtractLinkCases(relLinkKpi, stageTag)
        inFile = fullfile(runFolder, char(relLinkKpi));
        if exist(inFile, "file") ~= 2
            return;
        end
        try
            T = readtable(inFile, "VariableNamingRule", "preserve");
        catch
            return;
        end
        if isempty(T) || ~ismember("Case", string(T.Properties.VariableNames))
            return;
        end

        stageTag = matlab.lang.makeValidName(char(stageTag));
        T.Stage = repmat(string(stageTag), height(T), 1);

        localWriteCase(T, "DL_PDSCH_Throughput", "phy/dl/pdsch", "pdsch_case_kpis_" + stageTag + ".csv", relLinkKpi);
        localWriteCase(T, "UL_PUSCH_Throughput", "phy/ul/pusch", "pusch_case_kpis_" + stageTag + ".csv", relLinkKpi);
        localWriteCase(T, "PRACH_Detection", "phy/ul/prach", "prach_case_kpis_" + stageTag + ".csv", relLinkKpi);
        localWriteCase(T, "UL_SRS_ChannelEst", "phy/ul/srs", "srs_case_kpis_" + stageTag + ".csv", relLinkKpi);
        localWriteCase(T, "CellSearch_MIB_SIB1", "phy/dl/ssb_pbch", "cellsearch_case_kpis_" + stageTag + ".csv", relLinkKpi);
        localWriteCase(T, "UL_LowPAPR", "phy/waveform_numerology", "papr_case_kpis_" + stageTag + ".csv", relLinkKpi);
    end

    function localWriteCase(T, caseName, block, outFile, srcRel)
        rows = T(strcmp(string(T.Case), string(caseName)), :);
        if isempty(rows)
            return;
        end
        dstRel = fullfile(block, char(outFile));
        dstAbs = fullfile(structuredRoot, dstRel);
        sixgr.util.csvWriteTable(dstAbs, rows);
        localRecord(block, "csv", srcRel, dstRel, "Extracted case=" + string(caseName));
    end

    function localExtractE2EProtocols()
        sumFile = fullfile(runFolder, "csv", "probe_e2e_summary.csv");
        slotFile = fullfile(runFolder, "csv", "probe_e2e_slot_metrics.csv");
        if exist(sumFile, "file") == 2
            try
                S = readtable(sumFile, "VariableNamingRule", "preserve");
                localWriteSubset(S, ["Scheduler","HARQ_RetxProbability","ACKRate","NACKRate","NumUE","NumSlots","SlotDuration_ms"], ...
                    "protocol/mac/mac_scheduler_harq_summary.csv", "csv", "csv/probe_e2e_summary.csv", "MAC scheduler/HARQ summary");
                localWriteSubset(S, ["RLCMode","DeliveryRatio","Goodput_Mbps","Offered_Mbps"], ...
                    "protocol/rlc/rlc_summary.csv", "csv", "csv/probe_e2e_summary.csv", "RLC delivery summary");
                localWriteSubset(S, ["TrafficModel","Offered_Mbps","Goodput_Mbps","DeliveryRatio","NumUE"], ...
                    "protocol/pdcp/pdcp_summary.csv", "csv", "csv/probe_e2e_summary.csv", "PDCP throughput summary");
                localWriteSubset(S, ["TrafficModel","NumUE","Offered_Mbps","Goodput_Mbps"], ...
                    "protocol/sdap/sdap_summary.csv", "csv", "csv/probe_e2e_summary.csv", "SDAP flow summary");
                localWriteSubset(S, ["AttachSuccess","AttachSlots","AttachMessages","AttachRNTI"], ...
                    "protocol/rrc/rrc_attach_summary.csv", "csv", "csv/probe_e2e_summary.csv", "RRC attach summary");
            catch
            end
        end

        if exist(slotFile, "file") == 2
            try
                T = readtable(slotFile, "VariableNamingRule", "preserve");
                localWriteSubset(T, ["Slot","NumGrants","NumACK","NumNACK","NumRetx","MeanCQI","QueueBits"], ...
                    "protocol/mac/mac_slot_metrics.csv", "csv", "csv/probe_e2e_slot_metrics.csv", "Per-slot MAC metrics");
                localWriteSubset(T, ["Slot","OfferedBits","DeliveredBits","NumGrants","NumACK","NumNACK","QueueBits","Goodput_Mbps"], ...
                    "cross_layer/e2e/data_plane_flow.csv", "csv", "csv/probe_e2e_slot_metrics.csv", "Cross-layer data-plane flow");
            catch
            end
        end
    end

    function localWriteMessageFlow()
        mdFile = fullfile(structuredRoot, "cross_layer", "e2e", "message_flow.md");
        sixgr.util.ensureDir(mdFile);

        attachTxt = "not available";
        goodputTxt = "not available";
        deliveryTxt = "not available";
        try
            S = readtable(fullfile(runFolder, "csv", "probe_e2e_summary.csv"), "VariableNamingRule", "preserve");
            if ~isempty(S)
                if ismember("AttachSuccess", string(S.Properties.VariableNames))
                    attachTxt = string(S.AttachSuccess(1));
                end
                if ismember("Goodput_Mbps", string(S.Properties.VariableNames))
                    goodputTxt = sprintf("%.6g", S.Goodput_Mbps(1));
                end
                if ismember("DeliveryRatio", string(S.Properties.VariableNames))
                    deliveryTxt = sprintf("%.6g", S.DeliveryRatio(1));
                end
            end
        catch
        end

        fid = fopen(mdFile, "w");
        if fid < 0
            return;
        end
        c = onCleanup(@() fclose(fid)); %#ok<NASGU>
        fprintf(fid, "# E2E Message/Data Flow\n\n");
        fprintf(fid, "## Control Plane\n\n");
        fprintf(fid, "1. UE reads SI and starts random access (RACH).\n");
        fprintf(fid, "2. gNB sends RAR and temporary C-RNTI assignment.\n");
        fprintf(fid, "3. UE/gNB exchange attach signaling until RRC CONNECTED.\n");
        fprintf(fid, "- AttachSuccess: `%s`\n\n", char(attachTxt));
        fprintf(fid, "## Data Plane\n\n");
        fprintf(fid, "App SDU -> SDAP -> PDCP -> RLC -> MAC/TBAssembler -> HARQ/PHY -> RX -> deassembly -> SDU delivery\n\n");
        fprintf(fid, "- DeliveryRatio: `%s`\n", char(deliveryTxt));
        fprintf(fid, "- Goodput_Mbps: `%s`\n", char(goodputTxt));

        localRecord("cross_layer/e2e", "md", "", "cross_layer/e2e/message_flow.md", ...
            "Control-plane and data-plane chain overview");
    end

    function localWriteStructureReadme()
        rd = fullfile(structuredRoot, "run", "meta", "README_structure.md");
        fid = fopen(rd, "w");
        if fid < 0
            return;
        end
        c = onCleanup(@() fclose(fid)); %#ok<NASGU>
        fprintf(fid, "# Structured Result Layout\n\n");
        fprintf(fid, "This folder groups campaign outputs by block/layer.\n\n");
        fprintf(fid, "- `phy/channel`: channel/sweep/MAT diagnostics\n");
        fprintf(fid, "- `phy/dl/*`, `phy/ul/*`, `phy/sync`, `phy/harq`: PHY channel/control artifacts\n");
        fprintf(fid, "- `protocol/*`: MAC/RLC/PDCP/SDAP/RRC extracted summaries\n");
        fprintf(fid, "- `system/*`: mobility/interference/mMTC/V2X/NTN outputs\n");
        fprintf(fid, "- `cross_layer/e2e`: slot metrics, validation tables, AI metrics, traces, message flow\n");
        fprintf(fid, "- `cross_layer/e2e/validation`: PRIMARY validation tables (component_io, component_checks, packet_integrity)\n");
        fprintf(fid, "- `run/meta`: config, campaign report, audit, manifest\n");
        fprintf(fid, "- `logs`: stage logs\n");
        localRecord("run/meta", "md", "", "run/meta/README_structure.md", "Structured layout guide");
    end

    function localWriteCoverageStatus()
        auditFile = fullfile(runFolder, "csv", "full_3gpp_category_audit.csv");
        if exist(auditFile, "file") ~= 2
            return;
        end
        try
            T = readtable(auditFile, "VariableNamingRule", "preserve");
        catch
            return;
        end
        if isempty(T)
            return;
        end

        vars = string(T.Properties.VariableNames);
        catCol = localFindCol(vars, ["Category","Block","Name","Item"]);
        statusCol = localFindCol(vars, ["Status","Result","State"]);
        modeledCol = localFindCol(vars, ["Modeled","IsModeled","Implemented"]);
        approxCol = localFindCol(vars, ["Approximate","Approximated","Approximation","IsApproximate"]);
        artifactCol = localFindCol(vars, ["ArtifactExists","ArtifactOK","HasArtifact"]);

        n = height(T);
        category = repmat("", n, 1);
        if strlength(catCol) > 0
            category = string(T.(catCol));
        else
            category = "Category_" + string((1:n).');
        end
        state = repmat("simulated", n, 1);
        for r = 1:n
            st = "";
            if strlength(statusCol) > 0
                st = lower(strtrim(string(T.(statusCol)(r))));
            end
            modeled = true;
            if strlength(modeledCol) > 0
                modeled = localLogicalAt(T.(modeledCol), r, true);
            end
            approx = false;
            if strlength(approxCol) > 0
                approx = localLogicalAt(T.(approxCol), r, false);
            elseif strlength(st) > 0
                approx = contains(st, "approx");
            end
            hasArtifact = true;
            if strlength(artifactCol) > 0
                hasArtifact = localLogicalAt(T.(artifactCol), r, true);
            end

            if ~hasArtifact || contains(st, "missing") || contains(st, "fail")
                state(r) = "missing";
            elseif ~modeled || contains(st, "skip")
                state(r) = "skipped";
            elseif approx
                state(r) = "approximated";
            else
                state(r) = "simulated";
            end
        end

        Tout = table(category, state, 'VariableNames', {'Category','CoverageState'});
        outRel = "run/meta/coverage_state.csv";
        outAbs = fullfile(structuredRoot, outRel);
        sixgr.util.csvWriteTable(outAbs, Tout);
        localRecord("run/meta", "csv", "csv/full_3gpp_category_audit.csv", outRel, ...
            "Derived simulated/approximated/missing/skipped coverage states");
    end

    function localWriteSubset(T, cols, relOut, kind, srcRel, notes)
        v = string(T.Properties.VariableNames);
        keep = cols(ismember(cols, v));
        if isempty(keep)
            return;
        end
        S = T(:, cellstr(keep));
        absOut = fullfile(structuredRoot, char(relOut));
        sixgr.util.csvWriteTable(absOut, S);
        [blk, ~, ~] = fileparts(relOut);
        localRecord(string(blk), kind, srcRel, relOut, notes);
    end

    function localRecord(block, kind, srcRel, tgtRel, notes)
        r = struct();
        r.Block = string(block);
        r.Kind = string(kind);
        r.SourceRelPath = string(srcRel);
        r.TargetRelPath = string(tgtRel);
        r.Notes = string(notes);
        records(end+1,1) = r; %#ok<AGROW>
    end

    function name = localFindCol(vars, cands)
        name = "";
        for ii = 1:numel(cands)
            j = find(strcmpi(vars, string(cands(ii))), 1, "first");
            if ~isempty(j)
                name = vars(j);
                return;
            end
        end
    end

    function tf = localLogicalAt(v, idx, def)
        tf = def;
        try
            x = v(idx);
            if islogical(x)
                tf = logical(x);
                return;
            end
            if isnumeric(x)
                tf = logical(x ~= 0);
                return;
            end
            s = lower(strtrim(string(x)));
            if any(s == ["true","yes","y","1","ok","pass","modeled","implemented","present"])
                tf = true;
            elseif any(s == ["false","no","n","0","missing","skip","skipped","fail","notmodeled"])
                tf = false;
            end
        catch
            tf = def;
        end
    end

    function rel = relativeToRun(absPath)
        rel = string(absPath);
        pref = string(runFolder) + filesep;
        if startsWith(rel, pref)
            rel = extractAfter(rel, strlength(pref));
        end
        rel = replace(rel, "\", "/");
    end

    function rel = relativeToStructured(absPath)
        rel = string(absPath);
        pref = string(structuredRoot) + filesep;
        if startsWith(rel, pref)
            rel = extractAfter(rel, strlength(pref));
        end
        rel = replace(rel, "\", "/");
    end

    function localMirrorTree(srcRoot, dstRoot)
        srcRoot = localCanonicalPath(srcRoot);
        dstRoot = localCanonicalPath(dstRoot);
        files = dir(fullfile(srcRoot, "**", "*"));
        for k = 1:numel(files)
            if files(k).isdir
                continue;
            end
            src = fullfile(files(k).folder, files(k).name);
            if startsWith(src, [srcRoot filesep])
                rel = extractAfter(src, strlength(srcRoot) + 1);
            else
                rel = files(k).name;
            end
            dst = fullfile(dstRoot, rel);
            localCopyFile(src, dst);
        end
    end
end

function localCopyFile(src, dst)
% Overwrite-safe file copy.
sixgr.util.ensureDir(dst);
if exist(dst, "file") == 2
    try
        delete(dst);
    catch
    end
end
copyfile(src, dst);
end

function p = localCanonicalPath(pIn)
% Normalize path without Java canonicalization overhead.
p = char(string(pIn));
if strlength(string(p)) == 0
    return;
end
[isAbsWin, isAbsUnix] = deal(~isempty(regexp(p, '^[A-Za-z]:[\\/]', 'once')), startsWith(p, "/"));
if ~(isAbsWin || isAbsUnix)
    p = fullfile(pwd, p);
end
p = strrep(p, "/", filesep);
p = strrep(p, "\", filesep);
end
