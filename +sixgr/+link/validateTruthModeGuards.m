function report = validateTruthModeGuards(cfg, varargin)
%VALIDATETRUTHMODEGUARDS Validate shortcut gating against the active truth mode.

ip = inputParser;
ip.addParameter("FastAWGNPath", false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter("SkipTimingEstimate", false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter("Context", "LLS truth guard", @(x) ischar(x) || isstring(x));
ip.addParameter("FailOnError", true, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.parse(varargin{:});
opt = ip.Results;

mode = sixgr.link.resolveTruthMode(cfg);
issues = strings(0, 1);
if mode == "full_waveform" && logical(opt.FastAWGNPath)
    issues(end+1, 1) = "FastAWGNPath is forbidden in TruthMode='full_waveform'.";
end
if mode == "full_waveform" && logical(opt.SkipTimingEstimate)
    issues(end+1, 1) = "SkipTimingEstimate is forbidden in TruthMode='full_waveform'.";
end

report = struct( ...
    "Context", char(string(opt.Context)), ...
    "Mode", char(mode), ...
    "Valid", isempty(issues), ...
    "FastAWGNPathRequested", logical(opt.FastAWGNPath), ...
    "SkipTimingEstimateRequested", logical(opt.SkipTimingEstimate), ...
    "Issues", issues);

if logical(opt.FailOnError) && ~logical(report.Valid)
    error("sixgr:link:TruthModeGuardViolation", ...
        "%s", char("Truth-mode guard failed for " + string(report.Context) + ": " + strjoin(issues, " | ")));
end
end
