classdef ScenarioConfig
%SCENARIOCONFIG Immutable resolved 6G PHY LLS scenario configuration.

    properties(SetAccess=immutable)
        Data (1,1) struct
        ScenarioID (1,1) string
        ConfigHash (1,1) string
        SourceFiles (:,1) string
        ConfigPath (1,1) string
        Kind (1,1) string
    end

    methods
        function obj = ScenarioConfig(data, varargin)
            ip = inputParser;
            ip.addRequired("data", @(x)builtin("isstruct", x) && isscalar(x));
            ip.addParameter("SourceFiles", strings(0,1), @(x)isstring(x) || iscellstr(x) || ischar(x));
            ip.addParameter("ConfigPath", "", @(x)ischar(x) || isstring(x));
            ip.addParameter("ConfigHash", "", @(x)ischar(x) || isstring(x));
            ip.addParameter("Kind", "scenario", @(x)ischar(x) || isstring(x));
            ip.parse(data, varargin{:});

            obj.Data = ip.Results.data;
            obj.ScenarioID = string(sixgr.util.structGet(data, "meta.scenario_id", ""));
            obj.ConfigHash = string(ip.Results.ConfigHash);
            obj.SourceFiles = string(ip.Results.SourceFiles(:));
            obj.ConfigPath = string(ip.Results.ConfigPath);
            obj.Kind = string(ip.Results.Kind);
        end

        function v = get(obj, pathStr, defaultValue)
            if nargin < 3
                v = sixgr.util.structGet(obj.Data, pathStr);
            else
                v = sixgr.util.structGet(obj.Data, pathStr, defaultValue);
            end
        end

        function tf = has(obj, pathStr)
            tf = localHasFieldPath(obj.Data, pathStr);
        end

        function s = toStruct(obj)
            s = obj.Data;
        end
    end
end

function tf = localHasFieldPath(s, pathStr)
parts = strsplit(char(string(pathStr)), ".");
cur = s;
tf = true;
for i = 1:numel(parts)
    p = parts{i};
    if ~(builtin("isstruct", cur) && isscalar(cur) && isfield(cur, p))
        tf = false;
        return;
    end
    cur = cur.(p);
end
end
