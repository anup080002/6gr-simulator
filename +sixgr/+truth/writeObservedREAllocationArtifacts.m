function [carrier,native,ssb]=writeObservedREAllocationArtifacts(T,cfg,layout)
% Publish executed grid domains with their actual run-context identity.
% This adds no rows, changes no measurement/source label and infers no RF
% parameter. Missing identity remains missing; conflicting identity fails.
assert(istable(T),'sixgr:truth:InvalidObservedRETable','Executed RE evidence must be a table.');
if ~isempty(T)
    T=localBind(T,cfg,'ScenarioID',["run.scenarioID","meta.lls6gScenarioID"]);
    T=localBind(T,cfg,'ConfigHash',"meta.configHash");
end
[carrier,native,ssb]=sixgr.truth.splitREAllocationDomains(T);
% Exact frequency/time union is independent of the existing PRB-symbol
% energy projection. Collapse mixed port domains; never add reservations.
occupiedUnion=sixgr.truth.buildObservedRETimeFrequencyUnion(carrier);
carrierPaths=[string(fullfile(layout.ComponentCSVDirs.frame_grid,'observed_re_allocation.csv')), ...
    string(fullfile(layout.ReportCSVDir,'live_re_allocation_snapshot.csv'))];
nativePaths=[string(fullfile(layout.ComponentCSVDirs.frame_grid,'observed_prach_native_allocation.csv')), ...
    string(fullfile(layout.ReportCSVDir,'live_prach_native_allocation_snapshot.csv'))];
localWrite(carrier,carrierPaths);
localWrite(native,nativePaths);
ssbPaths=[string(fullfile(layout.ComponentCSVDirs.frame_grid,'observed_ssb_native_allocation.csv')), ...
    string(fullfile(layout.ReportCSVDir,'live_ssb_native_allocation_snapshot.csv'))];
localWrite(ssb,ssbPaths);
unionPaths=[string(fullfile(layout.ComponentCSVDirs.frame_grid,'observed_re_time_frequency_union.csv')), ...
    string(fullfile(layout.ReportCSVDir,'live_re_time_frequency_union.csv'))];
localWrite(occupiedUnion,unionPaths);
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
if ~isempty(T)
    % Both destinations represent the identical executed population. Write
    % the table once; publish verified byte copies, not another serialization.
    sixgr.util.csvWriteTable(paths(1),T,'PreserveSchema',true,'MirrorPaths',paths(2:end));
else
    for path=paths
        if isfile(path)
        % Exact checkpoint artifact only; never recursively clear a run.
            delete(path);
        end
    end
end
end
