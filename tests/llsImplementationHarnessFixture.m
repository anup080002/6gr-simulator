function ctx = llsImplementationHarnessFixture(caseName)
%LLSIMPLEMENTATIONHARNESSFIXTURE Build compact run folders for validation-harness tests.

caseName = lower(strtrim(string(caseName)));
tmp = tempname;
mkdir(tmp);
layout = sixgr.report.resultLayout(tmp);
folders = [ ...
    string(layout.ReportCSVDir); ...
    string(layout.AirInterfaceCSVDir); ...
    string(layout.ControlCSVDir); ...
    string(layout.HARQCSVDir); ...
    string(layout.BeamformingCSVDir); ...
    string(fullfile(layout.Root, "reference_signals", "csv"))];
for i = 1:numel(folders)
    sixgr.util.ensureDir(fullfile(char(folders(i)), ".keep"));
end

[scfg, cfg, spec] = localScenario(caseName);
localWriteScenarioSummary(layout, scfg, spec);
localWriteRuntimeOperatingMode(layout, spec);
if spec.WriteProfiler
    localWriteRuntimeFunctionProfile(layout, spec);
end
if spec.IncludeDL
    sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv"), ...
        localDataTrials("DL", spec));
end
if spec.IncludeUL
    sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, "ul_pusch_trials.csv"), ...
        localDataTrials("UL", spec));
end
if spec.WriteKPI
    sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "live_error_rate_summary.csv"), ...
        localKPIRows(spec));
end

ctx = struct();
ctx.RunFolder = tmp;
ctx.Layout = layout;
ctx.ScenarioConfig = scfg;
ctx.InternalConfig = cfg;
ctx.Spec = spec;
ctx.Cleanup = onCleanup(@() localCleanup(tmp));
end

function [scfg, cfg, spec] = localScenario(caseName)
spec = struct();
spec.CaseName = caseName;
spec.ScenarioId = "actual_lls_" + matlab.lang.makeValidName(char(caseName));
spec.Direction = "both";
spec.ResultOk = true;
spec.WriteProfiler = true;
spec.WriteKPI = true;
spec.IncludeDL = true;
spec.IncludeUL = true;
spec.GridRB = 273;
spec.SampleRateHz = 122.88e6;
spec.BandwidthHz = 100e6;
spec.SCSkHz = 30;
spec.CenterFrequencyHz = 4e9;
spec.SpeedKmh = 0;
spec.LLRMeanAbs = 1.25;
spec.SNRdB = 20;
spec.TBMismatchDirection = "";
spec.ProfilerDirections = ["DL","UL"];

switch caseName
    case "partial_actual"
        % Default case: DL and UL data paths execute, KPI remains incomplete.
    case "label_only"
        spec.IncludeDL = false;
        spec.IncludeUL = false;
        spec.WriteKPI = false;
        spec.ProfilerDirections = strings(0, 1);
    case "bypass_dl"
        spec.Direction = "dl";
        spec.IncludeUL = false;
        spec.WriteProfiler = false;
        spec.ProfilerDirections = strings(0, 1);
    case "reference_mismatch"
        spec.Direction = "dl";
        spec.IncludeUL = false;
        spec.TBMismatchDirection = "DL";
        spec.ProfilerDirections = "DL";
    case "llr_low"
        spec.LLRMeanAbs = 1e-4;
    case "grid_mismatch"
        spec.Direction = "dl";
        spec.IncludeUL = false;
        spec.GridRB = 66;
    otherwise
        error("sixgr:test:UnknownLLSFixtureCase", ...
            "Unsupported llsImplementationHarnessFixture case '%s'.", caseName);
end

scfg = struct();
scfg = sixgr.util.structSet(scfg, "meta.scenario_id", spec.ScenarioId);
scfg = sixgr.util.structSet(scfg, "scenario_id", spec.ScenarioId);
scfg = sixgr.util.structSet(scfg, "simulation.link_direction", spec.Direction);
scfg = sixgr.util.structSet(scfg, "frequency.center_frequency_hz", spec.CenterFrequencyHz);
scfg = sixgr.util.structSet(scfg, "frequency.bandwidth_hz", spec.BandwidthHz);
scfg = sixgr.util.structSet(scfg, "frequency.n_size_grid", spec.GridRB);
scfg = sixgr.util.structSet(scfg, "waveform.sample_rate_hz", spec.SampleRateHz);
scfg = sixgr.util.structSet(scfg, "frame.scs_khz", spec.SCSkHz);
scfg = sixgr.util.structSet(scfg, "channels.mobility_kmph", spec.SpeedKmh);

cfg = struct();
cfg = sixgr.util.structSet(cfg, "frequency.center_frequency_hz", spec.CenterFrequencyHz);
cfg = sixgr.util.structSet(cfg, "frequency.bandwidth_hz", spec.BandwidthHz);
cfg = sixgr.util.structSet(cfg, "frequency.n_size_grid", spec.GridRB);
cfg = sixgr.util.structSet(cfg, "waveform.sample_rate_hz", spec.SampleRateHz);
cfg = sixgr.util.structSet(cfg, "frame.scs_khz", spec.SCSkHz);
end

function localWriteScenarioSummary(layout, scfg, spec)
T = table( ...
    repmat(string(scfg.meta.scenario_id), 1, 1), ...
    repmat("Actual LLS fixture", 1, 1), ...
    repmat(logical(spec.ResultOk), 1, 1), ...
    repmat(logical(spec.ResultOk), 1, 1), ...
    repmat("fixture_config_hash", 1, 1), ...
    'VariableNames', {'ScenarioID','ScenarioName','Ok','ResultOk','ConfigHash'});
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "scenario_summary.csv"), T);
end

function localWriteRuntimeOperatingMode(layout, spec)
T = table( ...
    repmat("fixture_config_hash", 1, 1), ...
    false, ...
    false, ...
    'VariableNames', {'ConfigHash','ProxyPHYActive','FallbackUsed'});
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "runtime_operating_mode.csv"), T);
end

function localWriteRuntimeFunctionProfile(layout, spec)
rows = repmat(struct( ...
    "FunctionName", "", ...
    "CompleteName", "", ...
    "NumCalls", 0, ...
    "TotalTime_s", 0, ...
    "SelfTimeApprox_s", 0), 0, 1);

    function appendFunction(name)
        rows(end + 1, 1) = struct( ... %#ok<AGROW>
            "FunctionName", string(name), ...
            "CompleteName", string(name), ...
            "NumCalls", 4, ...
            "TotalTime_s", 0.02, ...
            "SelfTimeApprox_s", 0.01);
    end

if any(spec.ProfilerDirections == "DL")
    appendFunction("sixgr.phy.dl.PDSCH_Tx");
    appendFunction("sixgr.phy.dl.PDSCH_Rx");
end
if any(spec.ProfilerDirections == "UL")
    appendFunction("sixgr.phy.ul.PUSCH_Tx");
    appendFunction("sixgr.phy.ul.PUSCH_Rx");
end
if isempty(rows)
    return;
end
sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "runtime_function_profile.csv"), ...
    struct2table(rows, "AsArray", true));
end

function T = localDataTrials(direction, spec)
prb = 52;
layers = 1;
modulation = "QPSK";
targetCodeRate = 490 / 1024;
nRePerPrb = 120;
tbRef = sixgr.validation.ReferencePath5GToolbox("tbs_bits", modulation, layers, prb, nRePerPrb, targetCodeRate, 0, NaN);
assert(logical(tbRef.Available), "Fixture requires nrTBS.");
tbBits = double(tbRef.Value);
if string(spec.TBMismatchDirection) == string(direction)
    tbBits = tbBits + 128;
end

slots = (0:2).';
snrVals = repmat(double(spec.SNRdB), numel(slots), 1);
sinrVals = localDirectionSINR(direction, numel(slots));
T = table( ...
    repmat(localDirectionUE(direction), numel(slots), 1), ...
    slots, ...
    tbBits * ones(numel(slots), 1), ...
    prb * ones(numel(slots), 1), ...
    layers * ones(numel(slots), 1), ...
    (prb * nRePerPrb) * ones(numel(slots), 1), ...
    repmat(modulation, numel(slots), 1), ...
    targetCodeRate * ones(numel(slots), 1), ...
    true(numel(slots), 1), ...
    zeros(numel(slots), 1), ...
    tbBits * ones(numel(slots), 1), ...
    true(numel(slots), 1), ...
    true(numel(slots), 1), ...
    sinrVals, ...
    repmat(double(spec.LLRMeanAbs), numel(slots), 1), ...
    snrVals, ...
    repmat(7 + (direction == "UL"), numel(slots), 1), ...
    repmat(85 + 5 * (direction == "UL"), numel(slots), 1), ...
    repmat(80 + 5 * (direction == "UL"), numel(slots), 1), ...
    repmat(1.2 + 0.1 * (direction == "UL"), numel(slots), 1), ...
    repmat("real_lls_evidence", numel(slots), 1), ...
    'VariableNames', {'UEID','Slot','TBSize_bits','AllocatedPRBCount','Layers','DataRECount', ...
    'Modulation','TargetCodeRate','CRCPass','BitErrors','BitsCompared', ...
    'DLSCHDecodeAvailable','ULSCHDecodeAvailable','PostEqSINR_dB','LLRMeanAbs', ...
    'AppliedAWGNSNR_dB','MCS','Throughput_Mbps','Goodput_Mbps','Latency_ms','TruthStatus'});
T.ChannelEstimateAvailable = true(height(T), 1);
T.Status = repmat("PASS", height(T), 1);
T.TBSInputModulation = repmat(modulation, height(T), 1);
T.TBSInputNumLayers = repmat(layers, height(T), 1);
T.TBSInputNPRB = repmat(prb, height(T), 1);
T.TBSInputNREPerPRB = repmat(nRePerPrb, height(T), 1);
T.TBSInputTargetCodeRate = repmat(targetCodeRate, height(T), 1);
T.TBSInputXOverhead = zeros(height(T), 1);
T.TBSInputSource = repmat("transmitter_resource_accounting", height(T), 1);
end

function T = localKPIRows(spec)
dirs = strings(0, 1);
if spec.IncludeDL
    dirs(end + 1, 1) = "DL"; %#ok<AGROW>
end
if spec.IncludeUL
    dirs(end + 1, 1) = "UL"; %#ok<AGROW>
end
if isempty(dirs)
    T = table();
    return;
end
T = table( ...
    dirs, ...
    (1:numel(dirs)).', ...
    repmat("OK", numel(dirs), 1), ...
    repmat("real_lls_evidence", numel(dirs), 1), ...
    zeros(numel(dirs), 1), ...
    ones(numel(dirs), 1), ...
    zeros(numel(dirs), 1), ...
    'VariableNames', {'Direction','UEID','PrimaryTruthValueStatus','TruthStatus','ErroredFrames','ObservedFrames','FER'});
end

function out = localDirectionUE(direction)
if string(direction) == "DL"
    out = 1;
else
    out = 2;
end
end

function out = localDirectionSINR(direction, nRows)
if string(direction) == "DL"
    out = [21; 23; 24];
else
    out = [13; 16; 18];
end
out = out(1:nRows);
end

function localCleanup(pathValue)
if exist(pathValue, "dir") == 7
    rmdir(pathValue, "s");
end
end
