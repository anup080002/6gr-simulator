classdef CalculationTracer
%SIXGR.TRACE.CALCULATIONTRACER Build normalized runtime calculation traces.

    methods (Static)
        function T = generate(runFolder, runId, scfg)
            layout = sixgr.report.resultLayout(runFolder);
            rows = repmat(localEmptyRow(), 0, 1);
            calcId = 0;

            chanPath = fullfile(layout.ReportCSVDir, "live_channel_state_tti.csv");
            if exist(chanPath, "file") == 2
                chan = readtable(chanPath, "VariableNamingRule", "preserve");
                idxList = localRepresentativeIndices(chan, 16);
                fcHz = double(localScenarioGet(scfg, "frequency.center_frequency_hz", NaN));
                for idx = idxList(:).'
                    calcId = calcId + 1;
                    rows(end+1, 1) = localCalcRow(runId, calcId, chan, idx, "geometry", "distance", ... %#ok<AGROW>
                        "distance_m", "PropagationDistance_m", "m", "geometry_distance", "", "", "", fcHz, scfg);
                    calcId = calcId + 1;
                    rows(end+1, 1) = localCalcRow(runId, calcId, chan, idx, "channel", "doppler", ... %#ok<AGROW>
                        "doppler_hz", "DopplerHz", "Hz", "fc_hz * v_mps / c", "distance", "", "", fcHz, scfg);
                    calcId = calcId + 1;
                    rows(end+1, 1) = localCalcRow(runId, calcId, chan, idx, "channel", "pathloss", ... %#ok<AGROW>
                        "pathloss_db", "Pathloss_dB", "dB", "runtime_pathloss", "", "", "", fcHz, scfg);
                    calcId = calcId + 1;
                    rows(end+1, 1) = localCalcRow(runId, calcId, chan, idx, "rf", "cfo", ... %#ok<AGROW>
                        "estimated_cfo_hz", "EstimatedCFO_Hz", "Hz", "runtime_cfo_tracker", "InjectedCFO_Hz", "", "", fcHz, scfg);
                    calcId = calcId + 1;
                    rows(end+1, 1) = localCalcRow(runId, calcId, chan, idx, "timing", "propagation_delay", ... %#ok<AGROW>
                        "propagation_delay_s", "GeometricPropagationDelay_s", "s", "distance_m / c", "PropagationDistance_m", "", "", fcHz, scfg);
                end
            end

            rows = [rows; localTrialRows(runId, scfg, fullfile(layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv"), "dl", "PDSCH")]; %#ok<AGROW>
            rows = [rows; localTrialRows(runId, scfg, fullfile(layout.AirInterfaceCSVDir, "ul_pusch_trials.csv"), "ul", "PUSCH")]; %#ok<AGROW>

            if isempty(rows)
                T = struct2table(repmat(localEmptyRow(), 0, 1), "AsArray", true);
            else
                T = struct2table(rows, "AsArray", true);
            end
            outPath = fullfile(layout.ReportCSVDir, "runtime_calculation_trace.csv");
            sixgr.util.csvWriteTable(outPath, T);
        end
    end
end

function rows = localTrialRows(runId, scfg, pathStr, subsystem, prefix)
rows = repmat(localEmptyRow(), 0, 1);
if exist(pathStr, "file") ~= 2
    return;
end
T = readtable(pathStr, "VariableNamingRule", "preserve");
idxList = localRepresentativeIndices(T, 12);
calcId = 100000 * double(strcmpi(prefix, "PUSCH"));
for idx = idxList(:).'
    if localHasVar(T, "TBSize_bits")
        calcId = calcId + 1;
        rows(end+1, 1) = localTrialCalc(runId, calcId, T, idx, subsystem, prefix + "_tbs", "TBSize_bits", "bits", "nrTBS", scfg); %#ok<AGROW>
    end
    if localHasVar(T, "PostEqSINR_dB")
        calcId = calcId + 1;
        rows(end+1, 1) = localTrialCalc(runId, calcId, T, idx, subsystem, prefix + "_posteq_sinr", "PostEqSINR_dB", "dB", "receiver_posteq_sinr", scfg); %#ok<AGROW>
    end
    if localHasVar(T, "EVM_rms")
        calcId = calcId + 1;
        rows(end+1, 1) = localTrialCalc(runId, calcId, T, idx, subsystem, prefix + "_evm", "EVM_rms", "ratio", "receiver_evm", scfg); %#ok<AGROW>
    end
    if localHasVar(T, "LLRMeanAbs")
        calcId = calcId + 1;
        rows(end+1, 1) = localTrialCalc(runId, calcId, T, idx, subsystem, prefix + "_llr", "LLRMeanAbs", "abs", "decoder_llr", scfg); %#ok<AGROW>
    end
    if localHasVar(T, "BLER")
        calcId = calcId + 1;
        rows(end+1, 1) = localTrialCalc(runId, calcId, T, idx, subsystem, prefix + "_bler", "BLER", "ratio", "trial_bler", scfg); %#ok<AGROW>
    end
    if localHasVar(T, "BER")
        calcId = calcId + 1;
        rows(end+1, 1) = localTrialCalc(runId, calcId, T, idx, subsystem, prefix + "_ber", "BER", "ratio", "trial_ber", scfg); %#ok<AGROW>
    end
end
end

function row = localTrialCalc(runId, calcId, T, idx, subsystem, calcName, outputField, unit, formula, scfg)
row = localEmptyRow();
row.RunId = string(runId);
row.CalcId = double(calcId);
row.Timestamp = string(idx);
row.Slot = localNumber(T, idx, ["Slot","SlotNumber"], NaN);
row.UEId = localNumber(T, idx, ["UEID","UEId"], NaN);
row.CellId = localNumber(T, idx, ["CellID","CellId"], NaN);
row.Subsystem = string(subsystem);
row.FunctionName = string(calcName);
row.CalculationName = string(calcName);
row.InputNames = "";
row.InputValues = "";
row.InputUnits = "";
row.OutputName = string(outputField);
row.OutputValue = localNumber(T, idx, outputField, NaN);
row.OutputUnit = string(unit);
row.Formula = string(formula);
row.ConfigSourcePath = string(localConfigSource(calcName, scfg));
row.ArtifactSource = string(outputField);
row.ReferenceValue = NaN;
row.Delta = NaN;
row.Tolerance = NaN;
row.Pass = true;
row.FailureReason = "";
end

function row = localCalcRow(runId, calcId, T, idx, subsystem, calcName, outputName, fieldName, unit, formula, refField, refUnit, refFormula, fcHz, scfg)
row = localEmptyRow();
lightSpeed = 299792458;
row.RunId = string(runId);
row.CalcId = double(calcId);
row.Timestamp = string(idx);
row.Slot = localNumber(T, idx, ["Slot","SlotNumber"], NaN);
row.UEId = localNumber(T, idx, ["UEID","UEId"], NaN);
row.CellId = localNumber(T, idx, ["CellID","CellId"], NaN);
row.Subsystem = string(subsystem);
row.FunctionName = string(calcName);
row.CalculationName = string(calcName);
row.InputNames = string(refField);
row.InputValues = string(localNumber(T, idx, refField, NaN));
row.InputUnits = string(refUnit);
row.OutputName = string(outputName);
row.OutputValue = localNumber(T, idx, fieldName, NaN);
row.OutputUnit = string(unit);
row.Formula = string(formula);
row.ConfigSourcePath = string(localConfigSource(calcName, scfg));
row.ArtifactSource = string(fieldName);

switch lower(string(calcName))
    case "doppler"
        speedKmh = double(localScenarioGet(scfg, "mobility.ue_speed_kmh", NaN));
        if isfinite(fcHz) && isfinite(speedKmh)
            row.ReferenceValue = (fcHz * (speedKmh / 3.6)) / lightSpeed;
            row.Delta = row.OutputValue - row.ReferenceValue;
            row.Tolerance = 25;
        end
    case "propagation_delay"
        distanceM = localNumber(T, idx, "PropagationDistance_m", NaN);
        if isfinite(distanceM)
            row.ReferenceValue = distanceM / lightSpeed;
            row.Delta = row.OutputValue - row.ReferenceValue;
            row.Tolerance = 2e-7;
        end
    otherwise
        row.ReferenceValue = NaN;
        row.Delta = NaN;
        row.Tolerance = NaN;
end

row.Pass = ~(isfinite(row.Tolerance) && isfinite(row.Delta) && abs(row.Delta) > row.Tolerance);
if ~row.Pass
    row.FailureReason = "reference_delta_exceeds_tolerance";
else
    row.FailureReason = "";
end
end

function idxList = localRepresentativeIndices(T, maxCount)
n = height(T);
if n < 1
    idxList = zeros(0, 1);
    return;
end
maxCount = max(1, round(double(maxCount)));
idxList = unique(round(linspace(1, n, min(n, maxCount))));
idxList = idxList(:);
end

function tf = localHasVar(T, name)
tf = ismember(string(name), string(T.Properties.VariableNames));
end

function value = localScenarioGet(scfg, pathStr, defaultValue)
if isa(scfg, "sixgr.lls6g.config.ScenarioConfig")
    value = scfg.get(pathStr, defaultValue);
else
    value = sixgr.util.structGet(scfg, pathStr, defaultValue);
end
end

function sourcePath = localConfigSource(calcName, scfg)
switch lower(string(calcName))
    case {"distance","propagation_delay"}
        sourcePath = "mobility.user_paths";
    case "doppler"
        sourcePath = "channels.doppler_hz|mobility.ue_speed_kmh";
    otherwise
        sourcePath = string(localScenarioGet(scfg, "meta.scenario_id", ""));
end
end

function value = localNumber(T, idx, names, defaultValue)
names = string(names(:));
for i = 1:numel(names)
    if ismember(names(i), string(T.Properties.VariableNames))
        raw = T.(names(i))(idx);
        try
            value = double(raw);
        catch
            value = defaultValue;
        end
        if ~isscalar(value) || ~isfinite(value)
            value = defaultValue;
        end
        return;
    end
end
value = defaultValue;
end

function row = localEmptyRow()
row = struct( ...
    "RunId", "", ...
    "CalcId", NaN, ...
    "Timestamp", "", ...
    "Slot", NaN, ...
    "UEId", NaN, ...
    "CellId", NaN, ...
    "Subsystem", "", ...
    "FunctionName", "", ...
    "CalculationName", "", ...
    "InputNames", "", ...
    "InputValues", "", ...
    "InputUnits", "", ...
    "OutputName", "", ...
    "OutputValue", NaN, ...
    "OutputUnit", "", ...
    "Formula", "", ...
    "ConfigSourcePath", "", ...
    "ArtifactSource", "", ...
    "ReferenceValue", NaN, ...
    "Delta", NaN, ...
    "Tolerance", NaN, ...
    "Pass", false, ...
    "FailureReason", "");
end
