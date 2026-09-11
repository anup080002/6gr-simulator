function [carrier,native]=writeObservedREAllocationArtifacts(T,cfg,layout)
% Publish executed grid domains with their actual run-context identity.
% This adds no rows, changes no measurement/source label and infers no RF
% parameter. Missing identity remains missing; conflicting identity fails.
assert(istable(T),'sixgr:truth:InvalidObservedRETable','Executed RE evidence must be a table.');
if ~isempty(T)
    T=localBind(T,cfg,'ScenarioID',["run.scenarioID","meta.lls6gScenarioID"]);
    T=localBind(T,cfg,'ConfigHash',"meta.configHash");
end
[carrier,native]=sixgr.truth.splitREAllocationDomains(T);
carrierPaths=[string(fullfile(layout.ComponentCSVDirs.frame_grid,'observed_re_allocation.csv')), ...
    string(fullfile(layout.ReportCSVDir,'live_re_allocation_snapshot.csv'))];
nativePaths=[string(fullfile(layout.ComponentCSVDirs.frame_grid,'observed_prach_native_allocation.csv')), ...
    string(fullfile(layout.ReportCSVDir,'live_prach_native_allocation_snapshot.csv'))];
localWrite(carrier,carrierPaths);
localWrite(native,nativePaths);
end

function T=localBind(T,cfg,name,paths)
value=""; source="";
for path=paths
    raw=sixgr.util.structGet(cfg,path,"");
    assert((ischar(raw) && (isrow(raw) || isempty(raw))) || (isstring(raw) && isscalar(raw)), ...
        'sixgr:truth:InvalidREContextIdentity','Run-context identity %s must be scalar text.',path);
    candidate=string(raw);
    if ~ismissing(candidate) && strlength(strtrim(candidate))>0
        value=candidate; source="CfgMobility."+path; break;
    end
end
if strlength(value)==0, return; end
if ismember(name,T.Properties.VariableNames)
    existing=string(T.(name));
    assert(size(existing,1)==height(T) && size(existing,2)==1, ...
        'sixgr:truth:InvalidREContextIdentity','Each RE row requires one %s identity.',name);
    known=~ismissing(existing) & strlength(strtrim(existing))>0;
    assert(all(existing(known)==value),'sixgr:truth:REContextIdentityMismatch', ...
        'Existing %s evidence belongs to a different runtime configuration.',name);
end
T.(name)=repmat(value,height(T),1);
T.([name 'ContextSource'])=repmat(source,height(T),1);
end

function localWrite(T,paths)
for path=paths
    if ~isempty(T)
        sixgr.util.csvWriteTable(path,T,'PreserveSchema',true);
    elseif isfile(path)
        % Exact checkpoint artifact only; never recursively clear a run.
        delete(path);
    end
end
end
