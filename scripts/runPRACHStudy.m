function out = runPRACHStudy(varargin)
%RUNPRACHSTUDY Execute the waveform-accurate PRACH LLS study matrix.
%
% Example:
%   out = runPRACHStudy;
%   out = runPRACHStudy("ScenarioMatrix", customMatrix, "Verbose", true);

setup6GRSimToolkit("Verbose", false);

p = inputParser;
p.FunctionName = "runPRACHStudy";
addParameter(p, "BaseConfig", sixgr.config.defaultConfig(), @(x) isstruct(x) || isobject(x));
addParameter(p, "ScenarioMatrix", struct([]), @(x) isstruct(x));
addParameter(p, "WriteOutputs", true, @(x) islogical(x) || isnumeric(x));
addParameter(p, "Verbose", true, @(x) islogical(x) || isnumeric(x));
parse(p, varargin{:});

out = sixgr.rach.runPRACHLLS(p.Results.BaseConfig, ...
    "ScenarioMatrix", p.Results.ScenarioMatrix, ...
    "WriteOutputs", p.Results.WriteOutputs, ...
    "Verbose", p.Results.Verbose);

fprintf("PRACH LLS study complete. OutputDir: %s\n", string(out.OutputDir));
end
