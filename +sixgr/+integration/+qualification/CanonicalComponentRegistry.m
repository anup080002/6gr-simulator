classdef CanonicalComponentRegistry
    %CANONICALCOMPONENTREGISTRY Hash-bind components to production sources.
    methods (Static)
        function [T, registryHash] = build(profile)
            C = profile.Components;
            n = height(C);
            implementationID = strings(n,1);
            sourcePath = strings(n,1);
            sourceSHA = strings(n,1);
            sourcePresent = false(n,1);
            for index = 1:n
                subcase = string(C.SubcaseID(index));
                relative = localSourceForComponent(profile.RepositoryRoot, ...
                    subcase, string(C.Component(index)));
                absolute = fullfile(profile.RepositoryRoot, relative);
                implementationID(index) = "CANONICAL-" + ...
                    erase(subcase, "-") + "-" + string(C.ComponentID(index));
                sourcePath(index) = string(relative);
                sourcePresent(index) = isfile(absolute);
                if sourcePresent(index)
                    sourceSHA(index) = ...
                        sixgr.integration.qualification.FullStackRunContext. ...
                        fileHash(absolute);
                else
                    sourceSHA(index) = "";
                end
            end
            status = repmat("FAIL", n, 1);
            status(sourcePresent & strlength(sourceSHA) == 64) = "PASS";
            T = table(string(C.ComponentID), string(C.Domain), ...
                string(C.Component), string(C.SubcaseID), ...
                implementationID, sourcePath, sourceSHA, sourcePresent, ...
                status, 'VariableNames', {'ComponentID','Domain', ...
                'Component','SubcaseID','ImplementationID','SourcePath', ...
                'SourceSHA256','SourcePresent','Status'});
            bytes = uint8(unicode2native(char(jsonencode(table2struct(T))), ...
                "UTF-8"));
            registryHash = lower(string(sixgr.util.sha256Hex(bytes)));
        end
    end
end

function path = localSourceForComponent(root,id,component)
if id=="SC-29"
    path="apps/lls_web_dashboard.py";
    return;
elseif id=="SC-30"
    path="tests/testAll.m";
    return;
end
[scope,fallback]=localScope(id);
candidates=strings(0,1);
for scopeIndex=1:numel(scope)
    listing=dir(fullfile(root,scope(scopeIndex),"**","*.m"));
    listing=listing(~[listing.isdir]);
    candidates=[candidates;string(fullfile({listing.folder}, ...
        {listing.name}))']; %#ok<AGROW>
end
candidates=unique(candidates,"stable");
if isempty(candidates)
    path=fallback;
    return;
end
componentToken=localToken(component);
scores=zeros(numel(candidates),1);
for index=1:numel(candidates)
    [~,stem]=fileparts(candidates(index));
    stemToken=localToken(stem);
    componentWords=unique(split(componentToken));
    stemWords=unique(split(stemToken));
    scores(index)=10*numel(intersect(componentWords,stemWords));
    if contains(componentToken,stemToken)||contains(stemToken,componentToken)
        scores(index)=scores(index)+100;
    end
    lowerStem=lower(stem);
    if contains(lowerStem,["artifact","export","impact","validation"]) && ...
            ~contains(componentToken,["artifact","export","validation", ...
            "completeness","publication"])
        scores(index)=scores(index)-8;
    end
end
[best,bestIndex]=max(scores);
if best<=0
    path=fallback;
else
    absolute=string(candidates(bestIndex));
    prefix=string(root)+filesep;
    path=erase(absolute,prefix);
    path=replace(path,"\","/");
end
end

function [scope,fallback] = localScope(id)
switch id
    case "SC-00"
        scope=["+sixgr/+lls6g/+config","+sixgr/+rng"];
        fallback="+sixgr/+lls6g/+config/loadScenarioConfig.m";
    case "SC-01"
        scope="+sixgr/+phy/+frame";
        fallback="+sixgr/+phy/+frame/exportFrameGridArtifacts.m";
    case {"SC-02","SC-03"}
        scope="+sixgr/+phy/+waveform";
        fallback="+sixgr/+phy/+waveform/CanonicalOFDMModulator.m";
    case {"SC-04","SC-08"}
        scope=["+sixgr/+pdsch","+sixgr/+phy/+dl"];
        fallback="+sixgr/+phy/+dl/PDSCH_Tx.m";
    case {"SC-05","SC-09"}
        scope=["+sixgr/+phy/+ul/+pusch","+sixgr/+phy/+ul"];
        fallback="+sixgr/+phy/+ul/PUSCH_Tx.m";
    case "SC-06"
        scope=["+sixgr/+phy/+ia","+sixgr/+phy/+broadcast", ...
            "+sixgr/+phy/+ra"];
        fallback="+sixgr/+phy/+ia/runInitialAccessPhaseValidation.m";
    case "SC-07"
        scope="+sixgr/+phy/+pdcch";
        fallback="+sixgr/+phy/+pdcch/PDCCHTransmitter.m";
    case "SC-10"
        scope=["+sixgr/+phy/+pucch","+sixgr/+phy/+ul"];
        fallback="+sixgr/+phy/+ul/PUCCH_Tx.m";
    case {"SC-11","SC-12"}
        scope=["+sixgr/+phy/+rsla","+sixgr/+phy/+dl"];
        fallback="+sixgr/+phy/+rsla/runRSLAPhaseValidation.m";
    case {"SC-13","SC-14"}
        scope="+sixgr/+phy/+mimo";
        fallback="+sixgr/+phy/+mimo/runMIMOCSIBeamformingPhaseValidation.m";
    case {"SC-15","SC-16","SC-17","SC-18"}
        scope="+sixgr/+channel";
        fallback="+sixgr/+channel/+runtime/runChannelGeometryPhaseValidation.m";
    case {"SC-19","SC-20","SC-21"}
        scope=["+sixgr/+rf","+sixgr/+phy/+ul/+pusch", ...
            "+sixgr/+phy/+pucch"];
        fallback="+sixgr/+rf/+runtime/runRFFrontEndPhaseValidation.m";
    case "SC-22"
        scope="+sixgr/+l2/+mac";
        fallback="+sixgr/+l2/+mac/runMACHARQSchedulingPhaseValidation.m";
    case {"SC-23","SC-24","SC-25"}
        scope="+sixgr/+protocol";
        fallback="+sixgr/+protocol/ProtocolRuntime.m";
    case {"SC-26","SC-27"}
        scope="+sixgr/+validation";
        fallback="+sixgr/+validation/runValidationPhaseValidation.m";
    case "SC-28"
        scope="+sixgr/+integration/+qualification";
        fallback="+sixgr/+integration/+qualification/ArtifactCompletenessEngine.m";
    otherwise
        scope=strings(0,1);
        fallback="";
end
end

function token=localToken(value)
token=lower(regexprep(string(value),'[^a-zA-Z0-9]+',' '));
token=strip(regexprep(token,'\s+',' '));
end
