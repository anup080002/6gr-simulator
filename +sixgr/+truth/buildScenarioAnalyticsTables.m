function report = buildScenarioAnalyticsTables(runDir, trialData, scenarioCfg)
%BUILDSCENARIOANALYTICSTABLES Compatibility wrapper for analysis exports.
%
% The implementation lives in +sixgr/+analytics so these derived artifacts
% are clearly separated from primary truth-runtime tables.

if nargin < 2
    trialData = [];
end
if nargin < 3
    scenarioCfg = struct();
end
report = sixgr.analytics.buildScenarioAnalyticsTables(runDir, trialData, scenarioCfg);
end
