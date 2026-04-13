classdef SimContext < handle
%SIXGR.CORE.SIMCONTEXT Shared run context for all simulator modes.
%
% This class centralizes:
%   - cfg (full config struct)
%   - tool capabilities (toolbox presence)
%   - runFolder + results subfolders
%   - logger
%   - RNG initialization
%
% Design notes:
% - SimContext is NOT intended for MATLAB Coder (it is a handle class and
%   contains file-system/logging state). For code generation, use
%   sixgr.config.toCoderConfig().
%
% See also: sixgr.core.Logger, sixgr.core.SimRunner

    properties
        Cfg struct
        Capabilities struct
        RootDir (1,:) char
        RunFolder (1,:) char
        Logger sixgr.core.Logger
        RngState struct
    end

    methods
        function obj = SimContext(cfg, varargin)
            % SimContext(cfg, "RunFolder", <path>, "RootDir", <path>, "Logger", <logger>)
            arguments
                cfg struct
            end
            arguments (Repeating)
                varargin
            end

            rootDir = '';
            runFolder = '';

            % Parse name/value overrides (keep char outputs)
            for i = 1:2:numel(varargin)
                key = lower(char(string(varargin{i})));
                val = varargin{i+1};
                switch key
                    case 'rootdir'
                        rootDir = char(val);
                    case 'runfolder'
                        runFolder = char(val);
                    case 'logger'
                        % allow injection (handled below)
                    otherwise
                        % ignore unknown
                end
            end

            if isempty(rootDir)
                here = fileparts(mfilename("fullpath"));              % .../+sixgr/+core
                projRoot = fileparts(fileparts(fileparts(here)));     % project root
                rootDir = char(sixgr.util.structGet(cfg, "paths.rootDir", projRoot));
            end

            if isempty(runFolder)
                resultsRoot = char(string(sixgr.util.structGet(cfg, "run.resultsRoot", "results")));
                resultsRoot = sixgr.report.resolveResultsRoot(resultsRoot);
                runFolder = sixgr.report.defaultRunFolder(resultsRoot, ...
                    "Bucket", localDefaultBucket(cfg), ...
                    "Profile", localDefaultProfile(cfg), ...
                    "Leaf", "current", ...
                    "CleanExisting", true);
            end

            obj.Cfg = cfg;
            obj.RootDir = char(rootDir);
            obj.RunFolder = char(runFolder);

            % Ensure the requested run folder exists without auto-spawning
            % legacy csv/mat/fig/logs trees under structured result roots.
            sixgr.util.ensureFolder(obj.RunFolder);

            % Capabilities
            obj.Capabilities = sixgr.util.getToolboxStatus();

            % Logger (create default if not provided)
            logLevel = sixgr.util.structGet(cfg, "run.logLevel", "info");
            logFile = fullfile(obj.RunFolder, 'logs', 'run.log');
            obj.Logger = sixgr.core.Logger(logFile, "Level", logLevel);

            % RNG init
            seed = double(sixgr.util.structGet(cfg, "run.seed", 1));
            obj.RngState = sixgr.util.rngInit(seed);
        end
    end
end

function bucket = localDefaultBucket(cfg)
mode = lower(strtrim(char(string(sixgr.util.structGet(cfg, "run.mode", "both")))));
switch mode
    case "link"
        bucket = "lls";
    case {"system", "both"}
        bucket = "sls";
    otherwise
        bucket = "sls";
end
end

function profile = localDefaultProfile(cfg)
mode = lower(strtrim(char(string(sixgr.util.structGet(cfg, "run.mode", "both")))));
switch mode
    case "link"
        profile = "session";
    otherwise
        profile = "session";
end
end
