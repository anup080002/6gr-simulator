classdef SimRunner < handle
% sixgr.core.SimRunner
% Top-level orchestrator. Runs Link/System/Hybrid modules under one context.
%
% This runner is intentionally flexible about module function signatures to
% support gradual migration from older code:
%  - Preferred (new):    out = ModuleFcn(ctx, params)
%  - Legacy (old):       out = ModuleFcn(params, cfg, runFolder, logger)
%
% Keep this file ASCII-only.

    properties
        Ctx sixgr.core.SimContext
        Results sixgr.core.SimResults
        FailFast (1,1) logical = true
    end

    methods
        function obj = SimRunner(ctx, varargin)
            if nargin < 1 || isempty(ctx)
                error('sixgr:SimRunner:NoContext','SimRunner requires a SimContext.');
            end
            obj.Ctx = ctx;
            obj.Results = sixgr.core.SimResults(ctx.RunFolder);

            if ~isempty(varargin)
                for i = 1:2:numel(varargin)
                    key = varargin{i};
                    val = varargin{i+1};
                    if isstring(key), key = char(key); end
                    switch lower(char(key))
                        case 'failfast'
                            obj.FailFast = logical(val);
                    end
                end
            end
        end

        function results = run(obj, varargin)
            % run('Mode','full','Module','sixgr_run_3gpp_full_campaign','Params',struct())
            mode = '';
            module = '';
            params = struct();

            if ~isempty(varargin)
                for i = 1:2:numel(varargin)
                    key = varargin{i};
                    val = varargin{i+1};
                    if isstring(key), key = char(key); end
                    switch lower(char(key))
                        case 'mode'
                            mode = char(val);
                        case 'module'
                            module = char(val);
                        case 'params'
                            params = val;
                        case 'failfast'
                            obj.FailFast = logical(val);
                    end
                end
            end

            if isempty(mode)
                try
                    mode = char(sixgr.util.structGet(obj.Ctx.Cfg,'run.mode','both'));
                catch
                    mode = 'both';
                end
            end
            if isempty(module)
                try
                    module = char(sixgr.util.structGet(obj.Ctx.Cfg,'run.module',''));
                catch
                    module = '';
                end
            end

            obj.Ctx.Logger.info(['SimRunner start: mode=' mode ', module=' module]);

            ok = true;
            try
                if ~isempty(module)
                    out = obj.runModule(module, params);
                    obj.Results.addOutput(module, out);
                else
                    % Minimal default behavior: run mode-specific module lists if present
                    list = {};
                    try
                        list = sixgr.util.structGet(obj.Ctx.Cfg,'run.modules',{});
                    catch
                    end
                    if isstring(list), list = cellstr(list); end
                    if ischar(list), list = {list}; end

                    if isempty(list)
                        obj.Ctx.Logger.warn('No modules specified. Nothing to run.');
                    else
                        for k = 1:numel(list)
                            m = char(list{k});
                            out = obj.runModule(m, params);
                            obj.Results.addOutput(m, out);
                        end
                    end
                end
            catch ME
                ok = false;
                obj.Ctx.Logger.error(['Run failed: ' ME.message]);
                if obj.FailFast
                    rethrow(ME);
                end
            end

            obj.Results.finalize(ok);
            results = obj.Results;
        end

        function out = runModule(obj, moduleName, params)
            if nargin < 3, params = struct(); end
            moduleName = char(moduleName);

            obj.Ctx.Logger.info(['Running module: ' moduleName]);

            if exist(moduleName,'file') ~= 2 && exist(moduleName,'class') ~= 8
                % Also allow package-qualified names like sixgr.link.Foo
                try
                    f = str2func(moduleName); %#ok<NASGU>
                catch
                    error('sixgr:SimRunner:ModuleNotFound','Module not found: %s', moduleName);
                end
            end

            f = str2func(moduleName);

            % Try new signature first: (ctx, params)
            try
                out = f(obj.Ctx, params);
                return;
            catch ME1
                if ~obj.isSignatureError_(ME1)
                    % Could be a real runtime error in module. Re-throw.
                    rethrow(ME1);
                end
            end

            % Try legacy signature: (params, cfg, runFolder, logger)
            try
                out = f(params, obj.Ctx.Cfg, obj.Ctx.RunFolder, obj.Ctx.Logger);
                return;
            catch ME2
                if obj.isSignatureError_(ME2)
                    % Give a helpful diagnostic
                    error('sixgr:SimRunner:BadSignature', ...
                        'Module %s has an unsupported signature. Try (ctx,params) or (params,cfg,runFolder,logger).', moduleName);
                else
                    rethrow(ME2);
                end
            end
        end
    end

    methods(Access=private)
        function tf = isSignatureError_(obj, ME) %#ok<INUSL>
            tf = false;
            if strcmp(ME.identifier,'MATLAB:TooManyInputs') || strcmp(ME.identifier,'MATLAB:TooManyOutputs')
                tf = true;
                return;
            end
            if contains(ME.message,'Too many input arguments') || contains(ME.message,'Not enough input arguments')
                tf = true;
                return;
            end
        end
    end
end
