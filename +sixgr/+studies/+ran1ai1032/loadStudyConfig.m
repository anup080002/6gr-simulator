function [cfg, provenance] = loadStudyConfig(configPath)
%LOADSTUDYCONFIG Load and validate the AI 10.3.2 campaign contract.
arguments
    configPath (1,1) string = ...
        "configs/tdoc/ai_10_3_2_modulation/study.yaml"
end

root = localRepoRoot();
path = configPath;
if ~java.io.File(char(path)).isAbsolute()
    path = string(fullfile(root, path));
end
[cfg,sources] = localResolve(path,strings(0,1));
cfg = sixgr.studies.ran1ai1032.validateStudyConfig(cfg);
sourceHashes=strings(size(sources));
for k=1:numel(sources)
    sourceHashes(k)=sixgr.csi.studyFileSHA256(sources(k));
end
provenance = struct( ...
    "ConfigPath", path, ...
    "SourceFiles",{sources},"SourceSHA256",{sourceHashes}, ...
    "ConfigSHA256",string(sixgr.util.sha256Hex(uint8(unicode2native( ...
        jsonencode(cfg)+join(sourceHashes,''),'UTF-8')))), ...
    "GitCommit", localGitCommit(root), ...
    "WorktreeDiffSHA256",localWorktreeDiffHash(root));
end

function [out,sources]=localResolve(path,stack)
path=string(char(java.io.File(char(path)).getCanonicalPath()));
assert(~any(stack==path),'sixgr:ran1ai1032:StudyInheritanceCycle', ...
    'AI 10.3.2 study configuration inheritance cycles at %s.',path);
raw=sixgr.lls6g.config.readConfigFile(path);
parents=string(sixgr.util.structGet(raw,'inherits',strings(0,1)));
parents=parents(:); out=struct(); sources=strings(0,1);
for k=1:numel(parents)
    parent=parents(k);
    if ~java.io.File(char(parent)).isAbsolute()
        parent=string(fullfile(fileparts(path),parent));
    end
    [base,baseSources]=localResolve(parent,[stack;path]);
    out=sixgr.util.mergeStruct(out,base);
    sources=[sources;baseSources]; %#ok<AGROW>
end
if isfield(raw,'inherits'), raw=rmfield(raw,'inherits'); end
out=sixgr.util.mergeStruct(out,raw);
sources=unique([sources;path],'stable');
end

function root = localRepoRoot()
root = fileparts(fileparts(fileparts(fileparts(mfilename("fullpath")))));
end

function value = localGitCommit(root)
[status, text] = system(sprintf('git -C "%s" rev-parse HEAD', root));
if status == 0
    value = strtrim(string(text));
else
    value = "UNKNOWN";
end
end

function value=localWorktreeDiffHash(root)
[status,diff]=system(sprintf('git -C "%s" diff --binary HEAD',root));
if status==0
    value=string(sixgr.util.sha256Hex(uint8(unicode2native(diff,'UTF-8'))));
else
    value="UNKNOWN";
end
end
