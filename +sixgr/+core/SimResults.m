classdef SimResults < handle
% sixgr.core.SimResults
% Standardized results container:
%  - ok flag and timing
%  - module outputs (struct)
%  - KPI tables (struct of tables)
%  - artifact manifest (saved files)
%
% Keep this file ASCII-only.

    properties
        Ok (1,1) logical = false
        RunFolder (1,:) char = ''
        StartTime (1,:) char = ''
        EndTime (1,:) char = ''
        Outputs struct = struct()
        KPIs struct = struct()
        Artifacts struct = struct('mat',{{}},'csv',{{}},'fig',{{}},'other',{{}})
        StrictMode (1,1) logical = false
        ApproximationsUsed string = strings(0,1)
        CalibrationSource (1,1) string = ""
        ConfigHash (1,1) string = ""
        CodeVersion (1,1) string = ""
        MissingArtifacts string = strings(0,1)
    end

    methods
        function obj = SimResults(runFolder)
            if nargin < 1, runFolder = ''; end
            obj.RunFolder = char(runFolder);
            obj.StartTime = datestr(now,'yyyy-mm-dd HH:MM:SS');
        end

        function addOutput(obj, name, value)
            name = matlab.lang.makeValidName(char(name));
            obj.Outputs.(name) = value;
        end

        function addKPI(obj, name, tbl)
            name = matlab.lang.makeValidName(char(name));
            obj.KPIs.(name) = tbl;
        end

        function addArtifact(obj, kind, filePath)
            kind = lower(char(kind));
            if ~isfield(obj.Artifacts, kind)
                kind = 'other';
            end
            obj.Artifacts.(kind){end+1} = char(filePath);
        end

        function setManifestMeta(obj, meta)
            if nargin < 2 || ~isstruct(meta)
                return;
            end
            obj.StrictMode = logical(sixgr.util.structGet(meta, "strictMode", obj.StrictMode));
            obj.CalibrationSource = string(sixgr.util.structGet(meta, "calibrationSource", obj.CalibrationSource));
            obj.ConfigHash = string(sixgr.util.structGet(meta, "configHash", obj.ConfigHash));
            obj.CodeVersion = string(sixgr.util.structGet(meta, "codeVersion", obj.CodeVersion));
            appr = sixgr.util.structGet(meta, "approximationsUsed", obj.ApproximationsUsed);
            miss = sixgr.util.structGet(meta, "missingArtifacts", obj.MissingArtifacts);
            obj.ApproximationsUsed = string(appr(:));
            obj.MissingArtifacts = string(miss(:));
        end

        function finalize(obj, okFlag)
            if nargin < 2, okFlag = true; end
            obj.Ok = logical(okFlag);
            obj.EndTime = datestr(now,'yyyy-mm-dd HH:MM:SS');

            % Write manifest.json
            try
                m = struct();
                m.ok = obj.Ok;
                m.startTime = obj.StartTime;
                m.endTime = obj.EndTime;
                m.runFolder = obj.RunFolder;
                m.artifacts = obj.Artifacts;
                m.kpis = fieldnames(obj.KPIs);
                m.strictMode = obj.StrictMode;
                m.approximationsUsed = cellstr(obj.ApproximationsUsed);
                m.calibrationSource = char(obj.CalibrationSource);
                m.configHash = char(obj.ConfigHash);
                m.codeVersion = char(obj.CodeVersion);
                m.missingArtifacts = cellstr(obj.MissingArtifacts);
                sixgr.util.jsonWrite(fullfile(obj.RunFolder,'manifest.json'), m);
            catch
            end
        end
    end
end
