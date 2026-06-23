classdef RuntimeArtifactTransaction < handle
%RUNTIMEARTIFACTTRANSACTION Journal-backed artifact write transaction.

    properties
        RunFolder (1,1) string
        RelativePath (1,1) string
        ArtifactId (1,1) string
        ProducerStage (1,1) string
        ProducerBlock (1,1) string
        TemporaryPath (1,1) string = ""
        Closed (1,1) logical = false
    end

    methods
        function obj = RuntimeArtifactTransaction(runFolder, relativePath, varargin)
            p = inputParser;
            p.addRequired("runFolder", @(x)ischar(x) || isstring(x));
            p.addRequired("relativePath", @(x)ischar(x) || isstring(x));
            p.addParameter("ProducerStage", "", @(x)ischar(x) || isstring(x));
            p.addParameter("ProducerBlock", "", @(x)ischar(x) || isstring(x));
            p.addParameter("TemporaryPath", "", @(x)ischar(x) || isstring(x));
            p.parse(runFolder, relativePath, varargin{:});

            obj.RunFolder = string(runFolder);
            obj.RelativePath = string(relativePath);
            obj.ArtifactId = localUUID();
            obj.ProducerStage = string(p.Results.ProducerStage);
            obj.ProducerBlock = string(p.Results.ProducerBlock);
            obj.TemporaryPath = string(p.Results.TemporaryPath);
            sixgr.runtime.RuntimeEvidenceBus.appendStandaloneEvent(obj.RunFolder, "ARTIFACT_BEGIN", ...
                "ArtifactId", obj.ArtifactId, "RelativePath", obj.RelativePath, ...
                "TemporaryPath", obj.TemporaryPath, "StageName", obj.ProducerStage, ...
                "BlockId", obj.ProducerBlock, "Status", "begin", ...
                "EvidenceClass", "LIVE_RUNTIME_BOUNDARY");
        end

        function commit(obj, absolutePath, validationStatus)
            if nargin < 3
                validationStatus = "validated";
            end
            if obj.Closed
                return;
            end
            obj.Closed = true;
            [byteCount, sha] = localFileStats(absolutePath);
            sixgr.runtime.RuntimeEvidenceBus.appendStandaloneEvent(obj.RunFolder, "ARTIFACT_COMMIT", ...
                "ArtifactId", obj.ArtifactId, "RelativePath", obj.RelativePath, ...
                "TemporaryPath", obj.TemporaryPath, "ByteCount", byteCount, ...
                "SHA256", sha, "ValidationStatus", validationStatus, ...
                "CommitStatus", "committed", "StageName", obj.ProducerStage, ...
                "BlockId", obj.ProducerBlock, "Status", "committed", ...
                "EvidenceClass", "LIVE_RUNTIME_BOUNDARY");
        end

        function fail(obj, ME)
            if obj.Closed
                return;
            end
            obj.Closed = true;
            sixgr.runtime.RuntimeEvidenceBus.appendStandaloneEvent(obj.RunFolder, "ARTIFACT_FAIL", ...
                "ArtifactId", obj.ArtifactId, "RelativePath", obj.RelativePath, ...
                "TemporaryPath", obj.TemporaryPath, "ValidationStatus", "failed", ...
                "CommitStatus", "failed", "FailureReason", localExceptionText(ME), ...
                "StageName", obj.ProducerStage, "BlockId", obj.ProducerBlock, ...
                "Status", "failed", "ReasonCode", localExceptionId(ME), ...
                "Message", localExceptionText(ME), "EvidenceClass", "LIVE_RUNTIME_BOUNDARY");
        end
    end

    methods (Static)
        function writeTextAtomic(runFolder, relativePath, textValue, varargin)
            p = inputParser;
            p.addRequired("runFolder", @(x)ischar(x) || isstring(x));
            p.addRequired("relativePath", @(x)ischar(x) || isstring(x));
            p.addRequired("textValue", @(x)ischar(x) || isstring(x));
            p.addParameter("ProducerStage", "", @(x)ischar(x) || isstring(x));
            p.addParameter("ProducerBlock", "", @(x)ischar(x) || isstring(x));
            p.parse(runFolder, relativePath, textValue, varargin{:});

            finalPath = fullfile(string(runFolder), string(relativePath));
            tmpPath = string(finalPath) + ".tmp." + localUUID();
            tx = sixgr.runtime.RuntimeArtifactTransaction(runFolder, relativePath, ...
                "ProducerStage", p.Results.ProducerStage, ...
                "ProducerBlock", p.Results.ProducerBlock, ...
                "TemporaryPath", tmpPath);
            try
                localEnsureFolder(fileparts(char(finalPath)));
                fid = fopen(char(tmpPath), "w");
                if fid < 0
                    error("sixgr:runtime:ArtifactOpenFailed", "Unable to open temporary artifact: %s", char(tmpPath));
                end
                cleanupObj = onCleanup(@() localSafeFclose(fid)); %#ok<NASGU>
                fprintf(fid, "%s", char(string(textValue)));
                localSafeFclose(fid);
                clear cleanupObj;
                movefile(char(tmpPath), char(finalPath), "f");
                tx.commit(finalPath, "atomic_text_readback_pending");
            catch ME
                tx.fail(ME);
                rethrow(ME);
            end
        end
    end
end

function [byteCount, sha] = localFileStats(pathStr)
byteCount = NaN;
sha = "";
if exist(pathStr, "file") ~= 2
    return;
end
info = dir(pathStr);
byteCount = double(info.bytes);
fid = fopen(pathStr, "r");
if fid < 0
    return;
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
data = fread(fid, Inf, "*uint8");
sha = sixgr.util.sha256Hex(data);
end

function id = localUUID()
try
    id = string(char(java.util.UUID.randomUUID()));
catch
    id = "artifact_" + string(round(posixtime(datetime("now")) * 1e6)) + "_" + string(randi(1e9));
end
end

function localEnsureFolder(folder)
folder = char(string(folder));
if ~isempty(folder) && ~isfolder(folder)
    mkdir(folder);
end
end

function localSafeFclose(fid)
try
    fclose(fid);
catch
end
end

function id = localExceptionId(ME)
id = "";
if isa(ME, "MException")
    id = string(ME.identifier);
end
end

function text = localExceptionText(ME)
text = "";
if isa(ME, "MException")
    text = string(ME.message);
end
end
