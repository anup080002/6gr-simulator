function [cfg,provenance]=loadTDocConfig(configPath)
%LOADTDOCCONFIG Resolve the CSI TDoc YAML inheritance tree.
arguments
    configPath (1,1) string = "simulator/configs/csi_tdoc/bounded_qualification.yaml"
end
root=localRepoRoot(); path=string(configPath);
if ~java.io.File(char(path)).isAbsolute(), path=string(fullfile(root,path)); end
if exist(path,"file")~=2
    error("sixgr:csi:ConfigNotFound","CSI TDoc config not found: %s.",configPath);
end
[cfg,sources]=localResolve(path,strings(0,1));
cfg=sixgr.csi.validateTDocConfig(cfg);
canonical=jsonencode(cfg);
provenance=struct("ConfigPath",char(path),"SourceFiles",sources, ...
    "ConfigSHA256",string(sixgr.util.sha256Hex(uint8(unicode2native( ...
    canonical,"UTF-8")))),"CanonicalJSON",string(canonical));
end

function [out,sources]=localResolve(path,stack)
path=string(char(java.io.File(char(path)).getCanonicalPath()));
if any(stack==path)
    error("sixgr:csi:ConfigInheritanceCycle", ...
        "CSI TDoc configuration inheritance cycles at %s.",path);
end
raw=sixgr.lls6g.config.readConfigFile(path);
parents=string(sixgr.util.structGet(raw,"inherits",strings(0,1))); parents=parents(:);
out=struct(); sources=strings(0,1);
for k=1:numel(parents)
    parent=parents(k);
    if ~java.io.File(char(parent)).isAbsolute()
        parent=string(fullfile(fileparts(path),parent));
    end
    [base,baseSources]=localResolve(parent,[stack;path]);
    out=sixgr.util.mergeStruct(out,base); sources=[sources;baseSources]; %#ok<AGROW>
end
if isfield(raw,"inherits"), raw=rmfield(raw,"inherits"); end
out=sixgr.util.mergeStruct(out,raw); sources=unique([sources;path],"stable");
end

function root=localRepoRoot()
root=fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
