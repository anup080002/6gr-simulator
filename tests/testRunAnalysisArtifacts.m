function ok = testRunAnalysisArtifacts()
%TESTRUNANALYSISARTIFACTS Verify post-run analysis outputs and schemas.

setup6GRSimToolkit("Verbose", false);
tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

layout = sixgr.report.resultLayout(tmp);
sixgr.util.ensureFolder(layout.AirInterfaceCSVDir);
sixgr.util.ensureFolder(layout.ControlCSVDir);
sixgr.util.ensureFolder(layout.PacketFlowCSVDir);
sixgr.util.ensureFolder(layout.ReportCSVDir);

dl = table( ...
    [0;0], [1;2], [1;2], [4660;2], [10;12], [40;36], [2048;1904], [1;1], ...
    ["QPSK";"16QAM"], [true;false], [9.5;7.2], [0.0;0.03], [2048;0], ...
    [8640;7776], [17280;31104], [12;12], [8;100], ...
    'VariableNames', {'Frame','Slot','UEIndex','RNTI','MCS','AllocatedPRBCount','TBSize_bits','Layers', ...
    'Modulation','CRCPass','PostEqSINR_dB','RawBER','GoodBits','DataRECount','RateMatchedBits','SNR_dB','DecoderIterations'});
ul = table( ...
    0, 3, 1, 4660, 4, 24, 960, 1, "QPSK", true, 6.1, 0.0, 960, 5040, 10080, 12, 7, ...
    'VariableNames', {'Frame','Slot','UEIndex','RNTI','MCS','AllocatedPRBCount','TBSize_bits','Layers', ...
    'Modulation','CRCPass','PostEqSINR_dB','RawBER','GoodBits','DataRECount','RateMatchedBits','SNR_dB','DecoderIterations'});
pdcch = table(0, 1, 1, 4660, true, "PDCCH", 32, 4, ...
    'VariableNames', {'Frame','Slot','UEIndex','RNTI','CRCPass','Status','Payload_bits','AggregationLevel'});
pucch = table(0, 5, 1, 4660, true, "PUCCH", 2, ...
    'VariableNames', {'Frame','Slot','UEIndex','RNTI','CRCPass','Status','Payload_bits'});
prach = table(0, 0, 1, 65520, true, "PRACH", 8, 2.5, ...
    'VariableNames', {'Frame','Slot','UEIndex','RNTI','PreambleDetected','Status','Payload_bits','TimingAdvance_us'});
summary = table(0.5, 30, 'VariableNames', {'SlotDuration_ms','SCS_kHz'});
edges = table("run_analysis", 0.25, 1, 'VariableNames', {'CalleeFunctionName','TotalTime_s','EdgeRank'});

writetable(dl, fullfile(layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv"));
writetable(ul, fullfile(layout.AirInterfaceCSVDir, "ul_pusch_trials.csv"));
writetable(pdcch, fullfile(layout.ControlCSVDir, "pdcch_trials.csv"));
writetable(pucch, fullfile(layout.ControlCSVDir, "pucch_trials.csv"));
writetable(prach, fullfile(layout.AirInterfaceCSVDir, "prach_trials.csv"));
writetable(summary, fullfile(layout.ReportCSVDir, "scenario_summary.csv"));
writetable(edges, fullfile(layout.ReportCSVDir, "runtime_function_call_edges.csv"));

cfg = struct();
cfg.global_radio_scope = struct("channel_bandwidth_hz", 100e6);
report = run_analysis(tmp, cfg);
if ~report.Validation.Ok
    missing = report.Validation.Table(~logical(report.Validation.Table.Exists), :);
    disp(missing(:, intersect(["Artifact","Status"], string(missing.Properties.VariableNames), "stable")));
end
assert(report.Validation.Ok, "run_analysis validation failed.");

validationPath = fullfile(layout.ReportCSVDir, "analysis_output_validation.csv");
assert(exist(validationPath, "file") == 2, "Missing analysis_output_validation.csv");
V = readtable(validationPath, "VariableNamingRule", "preserve");
assert(all(logical(V.Exists)), "One or more expected analysis artifacts are missing.");

perSlotHeader = localHeader(fullfile(layout.ReportCSVDir, "per_slot_kpi_table.csv"));
assert(any(perSlotHeader == "TDDPattern"), "per_slot_kpi_table dropped all-blank TDDPattern column.");
assert(any(perSlotHeader == "HARQ_ACK_Received"), "per_slot_kpi_table dropped all-blank HARQ_ACK_Received column.");

perUEHeader = localHeader(fullfile(layout.ReportCSVDir, "per_ue_slot_kpi_table.csv"));
assert(any(perUEHeader == "HARQ_RV"), "per_ue_slot_kpi_table dropped all-blank HARQ_RV column.");
assert(any(perUEHeader == "TBSize_Reference"), "per_ue_slot_kpi_table dropped all-blank TBSize_Reference column.");

controlHeader = localHeader(fullfile(layout.ReportCSVDir, "control_plane_timeline.csv"));
assert(any(controlHeader == "CCE_Index"), "control_plane_timeline dropped all-blank CCE_Index column.");
assert(any(controlHeader == "Msg4_Pass"), "control_plane_timeline dropped all-blank Msg4_Pass column.");

assert(exist(fullfile(tmp, "reports", "html", "master_dashboard.html"), "file") == 2, "Missing master dashboard.");
ok = true;
end

function vars = localHeader(path)
txt = fileread(path);
lines = regexp(txt, "\r\n|\n|\r", "split");
vars = string(strsplit(lines{1}, ","));
end
