function T = buildPhysicsAuditTable(runDir, scenarioCfg, trialData)
%BUILDPHYSICSAUDITTABLE Build independent physics/math audit rows.
%
% The table is derived from completed-run artifacts and simple reference
% equations. It does not rerun the simulator.

arguments
    runDir {mustBeTextScalar}
    scenarioCfg = struct()
    trialData = []
end

if isempty(trialData)
    trialData = sixgr.analytics.loadAllTrialData(runDir);
end
layout = sixgr.report.resultLayout(runDir);
sixgr.util.ensureFolder(layout.ReportCSVDir);

scsKHz = localFirstFinite([ ...
    localSummaryValue(trialData, "SCS_kHz"), ...
    localCfgValue(scenarioCfg, ["bwp.dl.scs_khz","frame.scs_khz","scs_khz"], NaN), ...
    localColumnMean(trialData.dl, "SCS_kHz"), ...
    localColumnMean(trialData.ul, "SCS_kHz")], 30);
mu = log2(scsKHz / 15);
slotDurationMs = 1 / (2 ^ round(mu));
slotCount = localObservedSlotCount(trialData);
durationS = slotCount * slotDurationMs / 1000;

fcHz = localCfgValue(scenarioCfg, ["carrier.frequency_hz","phy_carrier.carrier_frequency_hz","frequency.carrierFrequencyHz","global_radio_scope.carrier_frequency_hz"], 4e9);
speedKmh = localCfgValue(scenarioCfg, ["mobility.speed_kmh","ue_mobility.speed_kmh","scenario.mobility.speed_kmh"], 100);
vMps = speedKmh / 3.6;
lambdaM = 299792458 / fcHz;
maxDopplerHz = vMps / lambdaM;
distanceM = vMps * durationS;
bandwidthHz = localCfgValue(scenarioCfg, ["global_radio_scope.channel_bandwidth_hz","frequency.bandwidthHz","carrier.bandwidth_hz"], 100e6);
noiseFigureDb = localCfgValue(scenarioCfg, ["rf.noise_figure_db","receiver.noise_figure_db","rf_hardware.noise_figure_db"], NaN);
if isnan(noiseFigureDb)
    noiseFigureDb = 7;
    nfNote = "assumed_reference_noise_figure";
else
    nfNote = "configured_noise_figure";
end
thermalNoiseDbm = -174 + 10 * log10(bandwidthHz) + noiseFigureDb;

[dlPass, dlFail] = localPassFail(trialData.dl);
[ulPass, ulFail] = localPassFail(trialData.ul);
dlAttempts = dlPass + dlFail;
ulAttempts = ulPass + ulFail;

configuredLayers = localFirstFinite([localSummaryValue(trialData, "ConfiguredLayers"), localColumnModeNumeric(trialData.dl, "ConfiguredLayers")], 1);
snrDb = localFirstFinite([localColumnMean(trialData.dl, "AppliedAWGNSNR_dB"), localColumnMean(trialData.dl, "SNR_dB"), localColumnMean(trialData.ul, "SNR_dB")], NaN);
if isfinite(snrDb)
    snrLin = 10^(snrDb/10);
    shannonSE = configuredLayers * log2(1 + snrLin);
else
    shannonSE = NaN;
end
dlGoodputMbps = localColumnSum(trialData.dl, "GoodBits") / max(durationS, eps) / 1e6;
achievedSE = dlGoodputMbps * 1e6 / bandwidthHz;

rows = {};
rows{end+1} = localRow("OFDM-001", "Numerology_mu", "mu = log2(SCS_kHz / 15)", scsKHz, round(mu), "", "mu", "computed_from_scs", abs(mu-round(mu)) < 1e-12); %#ok<AGROW>
rows{end+1} = localRow("OFDM-002", "SlotDuration_ms", "Tslot = 1 / 2^mu", slotDurationMs, slotDurationMs, "", "ms", "computed_from_mu", true); %#ok<AGROW>
rows{end+1} = localRow("MOB-001", "Speed_mps", "speed_kmh / 3.6", vMps, vMps, "", "m/s", "configured_or_assumed_speed", true); %#ok<AGROW>
rows{end+1} = localRow("MOB-002", "Wavelength_m", "c / fc", lambdaM, lambdaM, "", "m", "computed_from_carrier", true); %#ok<AGROW>
rows{end+1} = localRow("MOB-003", "MaxDoppler_Hz", "v / lambda", maxDopplerHz, maxDopplerHz, "", "Hz", "computed_from_speed_and_fc", true); %#ok<AGROW>
rows{end+1} = localRow("MOB-004", "DistanceTravelled_m", "v * observed_duration", distanceM, distanceM, "", "m", "computed_from_observed_slots", true); %#ok<AGROW>
rows{end+1} = localRow("NOISE-001", "ThermalNoise_dBm", "-174 + 10log10(B_Hz) + NF_dB", thermalNoiseDbm, thermalNoiseDbm, "", "dBm", nfNote, true); %#ok<AGROW>
rows{end+1} = localRow("KPI-001", "DL_BLER", "failed_dl_tb / attempted_dl_tb", localSafeDivide(dlFail, dlAttempts), localSafeDivide(dlFail, dlAttempts), "", "ratio", "derived_from_dl_pdsch_trials", true); %#ok<AGROW>
rows{end+1} = localRow("KPI-002", "UL_BLER", "failed_ul_tb / attempted_ul_tb", localSafeDivide(ulFail, ulAttempts), localSafeDivide(ulFail, ulAttempts), "", "ratio", "derived_from_ul_pusch_trials", true); %#ok<AGROW>
rows{end+1} = localRow("CAP-001", "ShannonSE_bps_per_Hz", "layers * log2(1 + SNR)", shannonSE, shannonSE, "", "bps/Hz", "reference_capacity_from_observed_snr", isfinite(shannonSE)); %#ok<AGROW>
rows{end+1} = localRow("CAP-002", "AchievedDLSE_bps_per_Hz", "DL_goodput_bps / bandwidth_hz", achievedSE, shannonSE, "", "bps/Hz", "derived_from_good_bits", isfinite(achievedSE)); %#ok<AGROW>

T = struct2table(vertcat(rows{:}), "AsArray", true);
sixgr.analytics.writeAnalysisTable(fullfile(layout.ReportCSVDir, "physics_audit_table.csv"), T);
end

function row = localRow(id, name, formula, measured, reference, tolerance, unit, source, passFlag)
row = struct( ...
    "EquationID", string(id), ...
    "QuantityName", string(name), ...
    "Formula", string(formula), ...
    "MeasuredValue", double(measured), ...
    "ReferenceValue", double(reference), ...
    "Delta", double(measured) - double(reference), ...
    "Tolerance", string(tolerance), ...
    "Unit", string(unit), ...
    "Status", string(localStatus(passFlag, measured)), ...
    "EvidenceClass", "RUNTIME_DERIVED", ...
    "Source", string(source));
end

function status = localStatus(passFlag, value)
if ~isfinite(double(value))
    status = "UNAVAILABLE";
elseif passFlag
    status = "OK";
else
    status = "CHECK";
end
end

function value = localCfgValue(cfg, paths, defaultValue)
value = defaultValue;
for p = string(paths)
    try
        v = sixgr.util.structGet(cfg, p, NaN);
        if isnumeric(v) && isscalar(v) && isfinite(double(v))
            value = double(v);
            return;
        elseif ischar(v) || isstring(v)
            x = str2double(string(v));
            if isfinite(x)
                value = x;
                return;
            end
        end
    catch
    end
end
end

function value = localSummaryValue(trialData, name)
value = NaN;
if ~isfield(trialData, "scenario_summary") || isempty(trialData.scenario_summary) || height(trialData.scenario_summary) == 0
    return;
end
T = trialData.scenario_summary;
if any(string(T.Properties.VariableNames) == string(name))
    value = localFirstDouble(T.(name));
end
end

function value = localColumnMean(T, name)
value = NaN;
if isempty(T) || height(T) == 0 || ~any(string(T.Properties.VariableNames) == string(name))
    return;
end
x = localToDouble(T.(name));
value = mean(x(isfinite(x)), "omitnan");
end

function value = localColumnModeNumeric(T, name)
value = NaN;
if isempty(T) || height(T) == 0 || ~any(string(T.Properties.VariableNames) == string(name))
    return;
end
x = localToDouble(T.(name));
x = x(isfinite(x));
if ~isempty(x)
    value = mode(x);
end
end

function value = localColumnSum(T, name)
value = 0;
if isempty(T) || height(T) == 0 || ~any(string(T.Properties.VariableNames) == string(name))
    return;
end
x = localToDouble(T.(name));
value = sum(x(isfinite(x)), "omitnan");
end

function value = localFirstDouble(v)
x = localToDouble(v);
x = x(isfinite(x));
if isempty(x)
    value = NaN;
else
    value = x(1);
end
end

function x = localToDouble(v)
if isnumeric(v) || islogical(v)
    x = double(v);
else
    x = str2double(string(v));
end
x = x(:);
end

function [passCount, failCount] = localPassFail(T)
passCount = 0;
failCount = 0;
if isempty(T) || height(T) == 0 || ~any(string(T.Properties.VariableNames) == "CRCPass")
    return;
end
s = lower(strtrim(string(T.CRCPass)));
passCount = sum(s == "1" | s == "true" | s == "pass");
failCount = sum(s == "0" | s == "false" | s == "fail");
end

function y = localSafeDivide(a, b)
if b == 0
    y = NaN;
else
    y = a ./ b;
end
end

function value = localFirstFinite(values, defaultValue)
value = defaultValue;
for i = 1:numel(values)
    if isfinite(values(i))
        value = values(i);
        return;
    end
end
end

function n = localObservedSlotCount(trialData)
slots = [];
for field = ["dl","ul","pdcch","pucch","prach"]
    if isfield(trialData, field)
        T = trialData.(field);
        if ~isempty(T) && height(T) > 0 && any(string(T.Properties.VariableNames) == "Slot")
            slots = [slots; localToDouble(T.Slot)]; %#ok<AGROW>
        end
    end
end
slots = slots(isfinite(slots));
if isempty(slots)
    n = 0;
else
    n = max(slots) - min(slots) + 1;
end
end

function mustBeTextScalar(x)
if ~(ischar(x) || (isstring(x) && isscalar(x)))
    error("sixgr:analytics:buildPhysicsAuditTable:BadRunDir", "runDir must be a char vector or string scalar.");
end
end
