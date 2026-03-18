classdef Logger < handle
% sixgr.core.Logger
% Simple, robust logger used across the toolkit.
%
% Design goals:
%  - Single API: info/warn/error/debug
%  - Backward compatible aliases: logInfo/logWarn/logError/logDebug
%  - Writes to file and optionally echoes to command window
%  - Optional callback sinks (e.g., GUI text area appender)
%
% NOTE: Keep this file ASCII-only (avoid non-ASCII punctuation) to prevent
% "Invalid text character" errors when copying across environments.

    properties
        Level (1,1) double = 2              % 0=ERROR,1=WARN,2=INFO,3=DEBUG
        EchoToConsole (1,1) logical = true
        LogFile (1,:) char = ''
    end

    properties(Access=private)
        Fid (1,1) double = -1
        Sinks cell = {}                     % cell array of function handles
        StartTic (1,1) double = 0
    end

    methods
        function obj = Logger(logFile, varargin)
            % Logger(logFile, 'Level',2, 'EchoToConsole',true)
            if nargin < 1 || isempty(logFile)
                logFile = '';
            end
            obj.LogFile = char(logFile);
            obj.StartTic = tic;

            % Parse name-value pairs (ASCII keys)
            if ~isempty(varargin)
                for i = 1:2:numel(varargin)
                    key = varargin{i};
                    val = varargin{i+1};
                    if isstring(key), key = char(key); end
                    switch lower(char(key))
                        case 'level'
                            obj.Level = double(val);
                        case 'echotoconsole'
                            obj.EchoToConsole = logical(val);
                        case 'logfile'
                            obj.LogFile = char(val);
                    end
                end
            end

            if ~isempty(obj.LogFile)
                obj.openFile();
            end
        end

        function delete(obj)
            obj.close();
        end

        function close(obj)
            if obj.Fid > 0
                try
                    fclose(obj.Fid);
                catch
                end
            end
            obj.Fid = -1;
        end

        function addSink(obj, fcn)
            % addSink(@(levelStr,timeStr,msgStr) ...)
            if nargin < 2 || isempty(fcn)
                return;
            end
            if ~isa(fcn,'function_handle')
                error('sixgr:Logger:InvalidSink','Sink must be a function_handle.');
            end
            obj.Sinks{end+1} = fcn;
        end

        function info(obj, msg)
            obj.log_(2, msg);
        end

        function warn(obj, msg)
            obj.log_(1, msg);
        end

        function debug(obj, msg)
            obj.log_(3, msg);
        end

        function error(obj, msg, varargin)
            % error(msg) logs an error message.
            % error(msg,true) also throws a MATLAB error after logging.
            doThrow = false;
            if nargin >= 3
                doThrow = logical(varargin{1});
            end
            obj.log_(0, msg);
            if doThrow
                builtin('error', 'sixgr:Logger:RaisedError', '%s', obj.toChar_(msg));
            end
        end

        % Backward-compatible aliases used by older modules
        function logInfo(obj, msg), obj.info(msg); end
        function logWarn(obj, msg), obj.warn(msg); end
        function logDebug(obj, msg), obj.debug(msg); end
        function logError(obj, msg, varargin), obj.error(msg, varargin{:}); end

        function tf = isDebug(obj)
            tf = obj.Level >= 3;
        end

        function s = elapsed(obj)
            s = toc(obj.StartTic);
        end
    end

    methods(Access=private)
        function openFile(obj)
            % Ensure parent folder exists
            try
                p = fileparts(obj.LogFile);
                if ~isempty(p) && ~exist(p,'dir')
                    mkdir(p);
                end
            catch
            end

            try
                obj.Fid = fopen(obj.LogFile,'a');
            catch
                obj.Fid = -1;
            end
        end

        function log_(obj, lvl, msg)
            if lvl > obj.Level
                return;
            end

            [lvlStr, tStr] = obj.levelAndTime_(lvl);
            mStr = obj.toChar_(msg);
            line = sprintf('[%s] %-5s %s', tStr, lvlStr, mStr);

            if obj.EchoToConsole
                fprintf('%s\n', line);
            end

            if obj.Fid > 0
                try
                    fprintf(obj.Fid, '%s\n', line);
                catch
                end
            end

            % Fan-out to sinks (GUI, etc.)
            if ~isempty(obj.Sinks)
                for i = 1:numel(obj.Sinks)
                    try
                        obj.Sinks{i}(lvlStr, tStr, mStr);
                    catch
                        % Never let a sink break the simulation
                    end
                end
            end
        end

        function [lvlStr, tStr] = levelAndTime_(obj, lvl)
            %#ok<INUSD>
            switch lvl
                case 0, lvlStr = 'ERROR';
                case 1, lvlStr = 'WARN';
                case 2, lvlStr = 'INFO';
                otherwise, lvlStr = 'DEBUG';
            end
            try
                t = datetime('now','Format','yyyy-MM-dd HH:mm:ss.SSS');
                tStr = char(t);
            catch
                tStr = datestr(now,'yyyy-mm-dd HH:MM:SS.FFF');
            end
        end

        function s = toChar_(obj, x) %#ok<INUSL>
            if isstring(x)
                if isscalar(x)
                    s = char(x);
                else
                    s = char(strjoin(x, " "));
                end
                return;
            end
            if ischar(x)
                s = x;
                return;
            end
            if isnumeric(x) || islogical(x)
                s = mat2str(x);
                return;
            end
            try
                s = char(string(x));
            catch
                s = '<unprintable>';
            end
        end
    end
end
