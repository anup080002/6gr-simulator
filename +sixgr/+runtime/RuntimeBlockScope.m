classdef RuntimeBlockScope < handle
%RUNTIMEBLOCKSCOPE Guaranteed enter/exit/fail pairing for runtime blocks.

    properties
        Bus sixgr.runtime.RuntimeEvidenceBus
        BlockId (1,1) string
        CallId (1,1) string
        ParentCallId (1,1) string = ""
        FunctionName (1,1) string = ""
        SourceFile (1,1) string = ""
        SourceLine (1,1) double = NaN
        StartTic
        Closed (1,1) logical = false
    end

    methods
        function obj = RuntimeBlockScope(bus, blockId, varargin)
            p = inputParser;
            p.addRequired("bus", @(x)isa(x, "sixgr.runtime.RuntimeEvidenceBus"));
            p.addRequired("blockId", @(x)ischar(x) || isstring(x));
            p.addParameter("CallId", "", @(x)ischar(x) || isstring(x));
            p.addParameter("ParentCallId", "", @(x)ischar(x) || isstring(x));
            p.addParameter("FunctionName", "", @(x)ischar(x) || isstring(x));
            p.addParameter("SourceFile", "", @(x)ischar(x) || isstring(x));
            p.addParameter("SourceLine", NaN, @(x)isnumeric(x));
            p.addParameter("Message", "", @(x)ischar(x) || isstring(x));
            p.parse(bus, blockId, varargin{:});

            obj.Bus = bus;
            obj.BlockId = string(blockId);
            obj.CallId = string(p.Results.CallId);
            if strlength(obj.CallId) == 0
                obj.CallId = localUUID();
            end
            obj.ParentCallId = string(p.Results.ParentCallId);
            obj.FunctionName = string(p.Results.FunctionName);
            obj.SourceFile = string(p.Results.SourceFile);
            obj.SourceLine = double(p.Results.SourceLine);
            obj.StartTic = tic;
            obj.Bus.emit("BLOCK_ENTER", "BlockId", obj.BlockId, "CallId", obj.CallId, ...
                "ParentCallId", obj.ParentCallId, "FunctionName", obj.FunctionName, ...
                "SourceFile", obj.SourceFile, "SourceLine", obj.SourceLine, ...
                "Status", "entered", "Message", p.Results.Message);
        end

        function success(obj, varargin)
            if obj.Closed
                return;
            end
            obj.Closed = true;
            obj.Bus.emit("BLOCK_EXIT", "BlockId", obj.BlockId, "CallId", obj.CallId, ...
                "ParentCallId", obj.ParentCallId, "FunctionName", obj.FunctionName, ...
                "SourceFile", obj.SourceFile, "SourceLine", obj.SourceLine, ...
                "Status", "completed", "Message", localMessageWithDuration("block completed", toc(obj.StartTic)), ...
                varargin{:});
        end

        function fail(obj, ME, varargin)
            if obj.Closed
                return;
            end
            obj.Closed = true;
            obj.Bus.emit("BLOCK_FAIL", "BlockId", obj.BlockId, "CallId", obj.CallId, ...
                "ParentCallId", obj.ParentCallId, "FunctionName", obj.FunctionName, ...
                "SourceFile", obj.SourceFile, "SourceLine", obj.SourceLine, ...
                "Status", "failed", "ReasonCode", localExceptionId(ME), ...
                "Message", localMessageWithDuration(localExceptionMessage(ME), toc(obj.StartTic)), ...
                varargin{:});
        end

        function closeIfUnfinished(obj)
            if obj.Closed
                return;
            end
            obj.Closed = true;
            obj.Bus.emit("BLOCK_FAIL", "BlockId", obj.BlockId, "CallId", obj.CallId, ...
                "ParentCallId", obj.ParentCallId, "FunctionName", obj.FunctionName, ...
                "SourceFile", obj.SourceFile, "SourceLine", obj.SourceLine, ...
                "Status", "failed", "ReasonCode", "scope_unfinished", ...
                "Message", localMessageWithDuration("block scope closed without success/fail", toc(obj.StartTic)));
        end
    end
end

function id = localUUID()
try
    id = string(char(java.util.UUID.randomUUID()));
catch
    id = "call_" + string(round(posixtime(datetime("now")) * 1e6)) + "_" + string(randi(1e9));
end
end

function id = localExceptionId(ME)
id = "";
if isa(ME, "MException")
    id = string(ME.identifier);
end
end

function msg = localExceptionMessage(ME)
msg = "";
if isa(ME, "MException")
    msg = string(ME.message);
end
if strlength(msg) == 0
    msg = "block failed";
end
end

function msg = localMessageWithDuration(msg, elapsed)
msg = string(msg) + " elapsed_s=" + string(elapsed);
end
