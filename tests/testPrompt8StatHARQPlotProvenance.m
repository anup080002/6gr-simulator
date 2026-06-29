function ok = testPrompt8StatHARQPlotProvenance()
%TESTPROMPT8STATHARQPLOTPROVENANCE Verify Prompt 8 post-run evidence exports.

setup6GRSimToolkit("Verbose", false);
tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

layout = sixgr.report.resultLayout(tmp);
sixgr.util.ensureFolder(layout.AirInterfaceCSVDir);
sixgr.util.ensureFolder(layout.ControlCSVDir);
sixgr.util.ensureFolder(layout.HARQCSVDir);
sixgr.util.ensureFolder(layout.RFCSVDir);
sixgr.util.ensureFolder(layout.ReportCSVDir);

n = 500;
slot = (0:n-1).';
ue = mod(slot, 2) + 1;
snrPoints = [-6 -3 0 3 6].';
snr = repelem(snrPoints, n / numel(snrPoints));
crcPass = true(n, 1);
crcPass(1:50:end) = false;
dl = table( ...
    floor(slot / 20), slot, ue, 4660 + ue, repmat(10, n, 1), repmat(40, n, 1), ...
    repmat(2048, n, 1), repmat(2, n, 1), repmat("16QAM", n, 1), crcPass, ...
    snr, repmat(0.0, n, 1), double(crcPass) .* 2048, ...
    repmat(8640, n, 1), repmat(17280, n, 1), snr, repmat(8, n, 1), repmat(40, n, 1), ...
    'VariableNames', {'Frame','Slot','UEIndex','RNTI','MCS','AllocatedPRBCount','TBSize_bits','Layers', ...
    'Modulation','CRCPass','PostEqSINR_dB','RawBER','GoodBits','DataRECount','RateMatchedBits','SNR_dB', ...
    'DecoderIterations','Goodput_Mbps'});
ul = dl(1:50:end, :);
ul.Slot = ul.Slot + 1;
ul.TBSize_bits(:) = 960;
ul.GoodBits(:) = 960;

pdcch = table(0, 1, 1, 4660, true, "PDCCH", 32, 4, ...
    'VariableNames', {'Frame','Slot','UEIndex','RNTI','CRCPass','Status','Payload_bits','AggregationLevel'});
pucch = table(0, 5, 1, 4660, true, "PUCCH", 2, ...
    'VariableNames', {'Frame','Slot','UEIndex','RNTI','CRCPass','Status','Payload_bits'});
prach = table(0, 0, 1, 65520, true, "PRACH", 8, 2.5, ...
    'VariableNames', {'Frame','Slot','UEIndex','RNTI','PreambleDetected','Status','Payload_bits','TimingAdvance_us'});
summary = table(0.5, 30, 'VariableNames', {'SlotDuration_ms','SCS_kHz'});
energy = table(slot(1:50:end), repmat(0.02, numel(slot(1:50:end)), 1), ...
    'VariableNames', {'Slot','Energy_J'});
harq = table( ...
    [0;1;2], [0;2;3], [false;true;true], [0;1024;2048], [1024;1024;1024], [1024;2048;3072], ...
    [false;true;true], [false;false;true], [false;true;true], [NaN;3.1;4.7], ...
    'VariableNames', {'HARQProcessID','RV','IsRetransmission','PreviousLLRCount','CurrentLLRCount','CombinedLLRCount', ...
    'HARQCombiningApplied','CurrentDecodeOK','CombinedDecodeOK','LLRCombiningGain_dB'});
ia = table([1;2;1], [7.5;11.0;8.25], ...
    'VariableNames', {'UEIndex','ProcedureDelay_ms'});
prof = table(["run_analysis";"sixgr.analytics.buildScenarioAnalyticsTables"], [1;1], [0.32;0.11], [0.05;0.08], ...
    'VariableNames', {'FunctionName','NumCalls','TotalTime_s','SelfTimeApprox_s'});

writetable(dl, fullfile(layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv"));
writetable(ul, fullfile(layout.AirInterfaceCSVDir, "ul_pusch_trials.csv"));
writetable(pdcch, fullfile(layout.ControlCSVDir, "pdcch_trials.csv"));
writetable(pucch, fullfile(layout.ControlCSVDir, "pucch_trials.csv"));
writetable(prach, fullfile(layout.AirInterfaceCSVDir, "prach_trials.csv"));
writetable(summary, fullfile(layout.ReportCSVDir, "scenario_summary.csv"));
writetable(energy, fullfile(layout.RFCSVDir, "energy_timeline_trace.csv"));
writetable(harq, fullfile(layout.HARQCSVDir, "live_harq_observation_timeline.csv"));
writetable(ia, fullfile(layout.ControlCSVDir, "initial_access_lifecycle_trace.csv"));
writetable(prof, fullfile(layout.ReportCSVDir, "runtime_function_profile.csv"));

cfg = struct();
cfg.meta.scenario_id = "prompt8_fixture";
cfg.ConfigPath = "unit_test_prompt8.yaml";
cfg.SourceFiles = ["unit_test_base.yaml"; "unit_test_prompt8.yaml"];
cfg.ConfigHash = "unit_hash";
cfg.global_radio_scope.channel_bandwidth_hz = 100e6;
cfg.frequency.center_frequency_hz = 4e9;
cfg.frame.scs_khz = 30;
cfg.frame_timing.slot_duration_ms = 0.5;
cfg.mobility.ue_speed_kmh = 100;
cfg.run_control.total_slots = n;

report = run_analysis(tmp, cfg);
assert(report.Validation.Ok, "Prompt 8 analysis validation failed.");

mob = readtable(fullfile(layout.ReportCSVDir, "mobility_adequacy_report.csv"), "VariableNamingRule", "preserve");
assert(logical(mob.MobilityAdequate(1)), "Mobility report did not pass configured 500-slot evidence.");
assert(mob.NumCoherenceIntervals(1) >= 200, "Mobility coherence interval count is too small.");

gain = readtable(fullfile(layout.AirInterfaceCSVDir, "harq_combining_gain.csv"), "VariableNamingRule", "preserve");
assert(logical(gain.Exercised(1)), "HARQ combining was not marked exercised.");
assert(gain.CombiningAppliedCount(1) >= 2, "HARQ combining applied count not derived from source rows.");

legacySweep = fullfile(layout.AirInterfaceCSVDir, "lls_snr_sweep.csv");
assert(exist(legacySweep, "file") ~= 2, ...
    "Deprecated injected-SNR sweep artifact must not be regenerated in geometry-driven analysis.");
sinrCurve = readtable(fullfile(layout.AirInterfaceCSVDir, "dl_measured_sinr_bler_curve.csv"), ...
    "VariableNamingRule", "preserve");
assert(numel(unique(sinrCurve.PostEqSINR_dB_BinCenter)) >= 5, ...
    "Measured-SINR BLER curve did not preserve multiple measured SINR bins.");
assert(any(string(sinrCurve.Properties.VariableNames) == "BLER_CI_Low"), ...
    "Measured-SINR BLER curve missing BLER CI low column.");
assert(any(string(sinrCurve.Properties.VariableNames) == "BLER_CI_High"), ...
    "Measured-SINR BLER curve missing BLER CI high column.");

cg = readtable(fullfile(layout.ReportCSVDir, "runtime_call_graph.csv"), "VariableNamingRule", "preserve");
assert(height(cg) >= 1, "Runtime call graph did not use profiler rows.");

manifestPath = fullfile(layout.ReportDir, "json", "scenario_manifest.json");
assert(exist(manifestPath, "file") == 2, "Missing reports/json scenario manifest.");
manifest = jsondecode(fileread(manifestPath));
assert(isfield(manifest, "GitCommit") && strlength(string(manifest.GitCommit)) > 0, "Manifest missing GitCommit.");
assert(isfield(manifest, "ScenarioYAML") && string(manifest.ScenarioYAML) == "unit_test_prompt8.yaml", "Manifest missing ScenarioYAML.");
assert(isfield(manifest, "ConfigOverlay"), "Manifest missing ConfigOverlay field.");

assert(exist(fullfile(layout.ReportDir, "html", "access_delay_cdf.html"), "file") == 2, "Missing access delay CDF HTML.");
assert(exist(fullfile(layout.ReportDir, "html", "harq_combining_gain.html"), "file") == 2, "Missing HARQ combining HTML.");

ok = true;
end
