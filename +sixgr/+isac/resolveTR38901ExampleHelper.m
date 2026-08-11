function evidence = resolveTR38901ExampleHelper(cfg)
%RESOLVETR38901EXAMPLEHELPER Resolve the official example-local helper.
%
% h38901ISACChannel is shipped as a supporting file of the MathWorks
% R2026a live example, not as a public Toolbox class on the default path.
% This resolver either finds that exact file or, when explicitly enabled
% in YAML, asks openExample to populate a deterministic cache.  It never
% substitutes another channel under the TR 38.901 evidence label.

backend=cfg.channel.tr38901Backend;
className=string(backend.className);
candidate=which(char(className));
cacheDirectory=string(sixgr.util.structGet(backend,"exampleCacheDirectory", ...
    fullfile(tempdir,"sixgr_mathworks_examples","tr38901")));
cacheDirectory=localExpandEnvironment(cacheDirectory);
if strlength(candidate)==0
    configured=string(sixgr.util.structGet(backend,"helperSearchPaths",strings(0,1)));
    configured=[configured(:);cacheDirectory];
    for i=1:numel(configured)
        folder=localExpandEnvironment(configured(i));
        path=fullfile(folder,className+".m");
        if exist(path,"file")==2
            addpath(folder);
            candidate=which(char(className));
            break;
        end
    end
end
if strlength(candidate)==0 && logical(sixgr.util.structGet(backend, ...
        "autoAcquireMathWorksExample",false))
    if exist(cacheDirectory,"dir")~=7, mkdir(cacheDirectory); end
    try
        % In -batch mode openExample can throw after successfully copying
        % the supporting file because no Editor is present.  File presence,
        % not the Editor side effect, is the acquisition success criterion.
        openExample("pre6g/IntroductionToTR38901ISACChannelModelExample", ...
            "workDir",cacheDirectory,"supportingFile",className+".m");
    catch exception
        path=fullfile(cacheDirectory,className+".m");
        if exist(path,"file")~=2
            error("sixgr:isac:TR38901ExampleAcquisitionFailed", ...
                "Unable to acquire the official MathWorks helper %s: %s", ...
                className,exception.message);
        end
    end
    addpath(cacheDirectory);
    candidate=which(char(className));
end
if strlength(candidate)==0
    error("sixgr:isac:TR38901ExampleHelperUnavailable", ...
        "The selected TR 38.901 backend requires official example helper %s.",className);
end
candidate=string(candidate);
evidence=struct("ClassName",className,"HelperPath",candidate, ...
    "HelperSHA256",localFileHash(candidate), ...
    "ExampleId","pre6g/IntroductionToTR38901ISACChannelModelExample", ...
    "EvidenceClass","official_mathworks_example_helper_execution");
end

function value=localExpandEnvironment(value)
value=string(value);
tokens=regexp(char(value),'%([^%]+)%','tokens');
for i=1:numel(tokens)
    replacement=string(getenv(tokens{i}{1}));
    value=replace(value,"%"+string(tokens{i}{1})+"%",replacement);
end
end

function digest=localFileHash(path)
fid=fopen(path,"rb");
if fid<0, error("sixgr:isac:FileHashReadFailed","Cannot read %s.",path); end
cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
digest=string(sixgr.util.sha256Hex(fread(fid,Inf,"*uint8")));
end
