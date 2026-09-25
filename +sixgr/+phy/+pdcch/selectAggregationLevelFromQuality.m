function [aggregationLevel, evidence] = selectAggregationLevelFromQuality(cfg, measuredControlSINR_dB, varargin)
%SELECTAGGREGATIONLEVELFROMQUALITY Select an executable PDCCH aggregation level.
%   The decision uses receiver-visible control-link quality only. Missing
%   quality fails toward the most robust level installed by the active
%   CORESET/SearchSpace; configured scenario SNR is never used as an oracle.

ip = inputParser;
ip.addParameter("ReceivedCQI", NaN, @(x) isnumeric(x) && isscalar(x));
ip.parse(varargin{:});
receivedCQI = double(ip.Results.ReceivedCQI);

configuredLevels = double(sixgr.util.structGet(cfg, "phy.pdcch.aggregationLevels", ...
    sixgr.util.structGet(cfg, "control.aggregation_levels", ...
    sixgr.util.structGet(cfg, "ctrl6gr.StudyAggregationLevels", ...
    sixgr.util.structGet(cfg, "phy.pdcch.aggregationLevel", 4)))));
configuredLevels = unique(configuredLevels(ismember(configuredLevels, [1 2 4 8 16])), "stable");
if isempty(configuredLevels)
    configuredLevels = 4;
end
[levels, executableEvidence] = sixgr.phy.pdcch.resolveExecutableAggregationLevels( ...
    cfg, configuredLevels);

policy = lower(strtrim(string(sixgr.util.structGet(cfg, ...
    "phy.pdcch.aggregationSelectionPolicy", "snr_threshold"))));
configuredLevel = double(sixgr.util.structGet(cfg, ...
    "phy.pdcch.schedulerAggregationLevel", NaN));
qualitySource = "measured_control_sinr";

if policy == "configured_scheduler_level" && isfinite(configuredLevel)
    target = configuredLevel;
    qualitySource = "configured_scheduler_level_policy";
elseif policy == "most_robust"
    target = max(levels);
    qualitySource = "configured_most_robust_policy";
else
    measuredControlSINR_dB = double(measuredControlSINR_dB);
    if ~isfinite(measuredControlSINR_dB)
        % A received CQI can prove outage, but it is not a calibrated PDCCH
        % SINR. In either the CQI-0 or unknown-quality case, fail toward the
        % most robust executable control channel rather than assuming AL4.
        target = max(levels);
        if isfinite(receivedCQI) && receivedCQI <= 0
            qualitySource = "received_cqi_zero_outage_most_robust";
        elseif isfinite(receivedCQI)
            qualitySource = "received_cqi_without_control_sinr_most_robust";
        else
            qualitySource = "missing_control_quality_most_robust";
        end
    elseif measuredControlSINR_dB < 0
        target = 16;
    elseif measuredControlSINR_dB < 5
        target = 8;
    elseif measuredControlSINR_dB < 10
        target = 4;
    elseif measuredControlSINR_dB < 15
        target = 2;
    else
        target = 1;
    end
end

[~, nearest] = min(abs(double(levels(:)) - double(target)));
aggregationLevel = double(levels(nearest));
evidence = struct( ...
    "AggregationLevel", aggregationLevel, ...
    "TargetAggregationLevel", double(target), ...
    "MeasuredControlSINR_dB", double(measuredControlSINR_dB), ...
    "ReceivedCQI", double(receivedCQI), ...
    "QualitySource", char(qualitySource), ...
    "Policy", char(policy), ...
    "ConfiguredLevels", configuredLevels, ...
    "ExecutableLevels", levels, ...
    "ExecutableLevelSource", char(string(executableEvidence.Source)));
end
