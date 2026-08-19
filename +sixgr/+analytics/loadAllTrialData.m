function trialData = loadAllTrialData(runDir)
%LOADALLTRIALDATA Load completed-run LLS artifacts for analysis.
%
% Missing files become empty tables. This function never fabricates rows.

arguments
    runDir {mustBeTextScalar}
end

layout = sixgr.report.resultLayout(runDir);
trialData = struct();
trialData.RunDir = string(runDir);
trialData.Layout = layout;

trialData.dl = localReadFirstAvailableTable( ...
    fullfile(layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv"), ...
    fullfile(layout.AirInterfaceCSVDir, "dl_fixed_link_campaign_trials.csv"), ...
    fullfile(layout.ReportCSVDir, "dl_fixed_link_campaign_trials.csv"));
trialData.ul = localReadFirstAvailableTable( ...
    fullfile(layout.AirInterfaceCSVDir, "ul_pusch_trials.csv"), ...
    fullfile(layout.AirInterfaceCSVDir, "ul_fixed_link_campaign_trials.csv"), ...
    fullfile(layout.ReportCSVDir, "ul_fixed_link_campaign_trials.csv"));
trialData.srs = localReadFirstAvailableTable( ...
    fullfile(layout.AirInterfaceCSVDir, "srs_trials.csv"), ...
    fullfile(layout.ControlCSVDir, "srs_trials.csv"));
trialData.trs = localReadFirstAvailableTable( ...
    fullfile(layout.AirInterfaceCSVDir, "trs_trials.csv"), ...
    fullfile(layout.ControlCSVDir, "trs_trials.csv"));
trialData.pdcch = localReadFirstAvailableTable( ...
    fullfile(layout.ControlCSVDir, "pdcch_trials.csv"), ...
    fullfile(layout.AirInterfaceCSVDir, "pdcch_trials.csv"));
trialData.pucch = localReadFirstAvailableTable( ...
    fullfile(layout.ControlCSVDir, "pucch_trials.csv"), ...
    fullfile(layout.AirInterfaceCSVDir, "pucch_trials.csv"));
trialData.prach = localReadFirstAvailableTable( ...
    fullfile(layout.AirInterfaceCSVDir, "prach_trials.csv"), ...
    fullfile(layout.ControlCSVDir, "prach_trials.csv"));
trialData.pbch = localReadFirstAvailableTable( ...
    fullfile(layout.AirInterfaceCSVDir, "pbch_trials.csv"), ...
    fullfile(layout.ControlCSVDir, "pbch_trials.csv"));

trialData.slot = localReadFirstAvailableTable( ...
    fullfile(layout.PacketFlowCSVDir, "slot_trace.csv"), ...
    fullfile(layout.ReportCSVDir, "slot_trace.csv"));
trialData.dl_grants = localReadOptionalTable(fullfile(layout.PacketFlowCSVDir, "live_dl_scheduler_grants.csv"));
trialData.ul_grants = localReadOptionalTable(fullfile(layout.PacketFlowCSVDir, "live_ul_scheduler_grants.csv"));
trialData.pucch_grants = localReadOptionalTable(fullfile(layout.PacketFlowCSVDir, "live_pucch_grants.csv"));
trialData.harq = localReadOptionalTable(fullfile(layout.HARQCSVDir, "live_harq_observation_timeline.csv"));
trialData.harq_process = localReadOptionalTable(fullfile(layout.HARQCSVDir, "harq_process_timeline.csv"));
trialData.channel_tti = localReadFirstAvailableTable( ...
    fullfile(layout.ReportCSVDir, "live_channel_state_tti.csv"), ...
    fullfile(layout.ReportCSVDir, "live_channel_estimation_tti.csv"));
trialData.power = localReadFirstAvailableTable( ...
    fullfile(layout.ReportCSVDir, "live_power_runtime_table.csv"), ...
    fullfile(layout.RFCSVDir, "power_energy_table.csv"), ...
    fullfile(layout.RFCSVDir, "energy_timeline_trace.csv"));
trialData.scenario_summary = localReadOptionalTable(fullfile(layout.ReportCSVDir, "scenario_summary.csv"));
trialData.result_status = localReadOptionalTable(fullfile(layout.ReportCSVDir, "result_status_summary.csv"));
trialData.mimo_configured_vs_effective = localReadOptionalTable(fullfile(layout.BeamformingCSVDir, "mimo_configured_vs_effective.csv"));

trialData.ue = localBuildUEViews(trialData);
end

function views = localBuildUEViews(trialData)
ues = unique([localNumericColumn(trialData.dl, "UEIndex"); localNumericColumn(trialData.ul, "UEIndex")]);
ues = ues(isfinite(ues));
views = struct([]);
for iUE = 1:numel(ues)
    ue = ues(iUE);
    views(iUE).UEIndex = ue; %#ok<AGROW>
    views(iUE).dl = localFilterNumeric(trialData.dl, "UEIndex", ue); %#ok<AGROW>
    views(iUE).ul = localFilterNumeric(trialData.ul, "UEIndex", ue); %#ok<AGROW>
    views(iUE).channel_tti = localFilterAnyUE(trialData.channel_tti, ue); %#ok<AGROW>
end
end

function T = localFilterAnyUE(Tin, ue)
T = Tin;
if isempty(Tin) || height(Tin) == 0
    return;
end
vars = string(Tin.Properties.VariableNames);
for name = ["UEIndex","UEID","UEId"]
    if any(vars == name)
        T = localFilterNumeric(Tin, name, ue);
        return;
    end
end
end

function T = localFilterNumeric(Tin, varName, value)
T = Tin;
if isempty(Tin) || height(Tin) == 0 || ~any(string(Tin.Properties.VariableNames) == string(varName))
    return;
end
x = localToDouble(Tin.(varName));
T = Tin(x == value, :);
end

function x = localNumericColumn(T, varName)
if isempty(T) || height(T) == 0 || ~any(string(T.Properties.VariableNames) == string(varName))
    x = zeros(0, 1);
else
    x = localToDouble(T.(varName));
end
end

function T = localReadFirstAvailableTable(varargin)
T = table();
for i = 1:nargin
    T = localReadOptionalTable(varargin{i});
    if height(T) > 0 || (exist(varargin{i}, "file") == 2)
        return;
    end
end
end

function T = localReadOptionalTable(pathStr)
pathStr = char(string(pathStr));
if exist(pathStr, "file") ~= 2
    T = table();
    return;
end
try
    T = readtable(pathStr, "VariableNamingRule", "preserve", "TextType", "string");
catch
    try
        T = readtable(pathStr, "VariableNamingRule", "preserve");
    catch
        T = table();
    end
end
end

function x = localToDouble(v)
if isnumeric(v) || islogical(v)
    x = double(v);
elseif iscell(v)
    x = str2double(string(v));
else
    x = str2double(string(v));
end
x = x(:);
end

function mustBeTextScalar(x)
if ~(ischar(x) || (isstring(x) && isscalar(x)))
    error("sixgr:analytics:loadAllTrialData:BadRunDir", "runDir must be a char vector or string scalar.");
end
end
