function info = setupPythonYamlFor6GRSim(varargin)
%SETUPPYTHONYAMLFOR6GRSIM Configure and verify MATLAB YAML parsing support.
% Keep this file ASCII-only.

p = inputParser;
p.addParameter("Verbose", true, @(x) islogical(x) && isscalar(x));
p.addParameter("RequireYAML", true, @(x) islogical(x) && isscalar(x));
p.addParameter("ForceRefresh", true, @(x) islogical(x) && isscalar(x));
p.parse(varargin{:});
opt = p.Results;

if exist("setup6GRSimToolkit", "file") == 2
    setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false, "CheckYAMLRuntime", false);
end

info = sixgr.lls6g.config.ensureYAMLRuntime( ...
    "Verbose", logical(opt.Verbose), ...
    "RequireYAML", false, ...
    "ConfigurePyEnv", true, ...
    "ForceRefresh", logical(opt.ForceRefresh));

if logical(opt.RequireYAML) && ~logical(info.CanParseYAML)
    error("sixgr:setup:PyYAMLUnavailable", ...
        "PyYAML is not available for MATLAB YAML parsing. Python executable: %s. Install with: %s", ...
        char(string(info.PythonExecutable)), char(string(info.RecommendedInstallCommand)));
end
end
