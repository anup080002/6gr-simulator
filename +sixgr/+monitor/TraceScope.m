classdef TraceScope < handle
    %TRACESCOPE Records one ENTER/EXIT pair in a RunMonitor.

    properties
        Monitor
        EnterId double = NaN
        StartTic
        StartCpu double = NaN
        Meta struct = struct()
        Closed logical = false
    end

    methods
        function obj = TraceScope(mon, varargin)
            obj.Monitor = mon;
            if nargin < 1 || ~isa(mon, "sixgr.monitor.RunMonitor")
                obj.Closed = true;
                return;
            end
            obj.Meta = mon.parseMetaPublic(varargin{:});
            obj.StartTic = tic;
            obj.StartCpu = cputime;
            obj.EnterId = mon.enter(obj.Meta);
        end

        function close(obj, varargin)
            if obj.Closed || isempty(obj.Monitor) || ~isvalid(obj.Monitor)
                return;
            end
            meta = obj.Meta;
            if ~isempty(varargin)
                extra = obj.Monitor.parseMetaPublic(varargin{:});
                names = fieldnames(extra);
                for i = 1:numel(names)
                    meta.(names{i}) = extra.(names{i});
                end
            end
            obj.Monitor.exit(obj.EnterId, toc(obj.StartTic), cputime - obj.StartCpu, meta);
            obj.Closed = true;
        end

        function delete(obj)
            try
                obj.close();
            catch
            end
        end
    end
end
