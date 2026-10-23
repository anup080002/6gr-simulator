function T = bindCoupledExecutionIdentity(T, cfg, signalName, bindInPathScope)
%BINDCOUPLEDEXECUTIONIDENTITY Bind lifecycle identity before live persistence.
% Database primary keys are not logical run identifiers. No lifecycle is
% invented for low-level callers, and conflicting provenance fails closed.
% Scope may be bound only by the active coupled producer, never by generic
% recovered-file readers or isolated component producers.
if nargin<4, bindInPathScope=false; end
assert(islogical(bindInPathScope) && isscalar(bindInPathScope), ...
    'sixgr:truth:CoupledRuntimeEvidenceEligibilityInvalid', ...
    'Producer scope binding must be an explicit logical scalar.');
if ~istable(T) || isempty(T)
    return;
end
values = [string(sixgr.util.structGet(cfg,"run.scenarioID", ...
    sixgr.util.structGet(cfg,"meta.scenarioID",""))), ...
    lower(string(sixgr.util.structGet(cfg,"meta.configHash",""))), ...
    string(sixgr.util.structGet(cfg,"run.runTag","")), ...
    string(sixgr.util.structGet(cfg,"run.executionID", ...
    sixgr.util.structGet(cfg,"meta.executionID","")))];
values = strtrim(values);
if numel(values) ~= 4 || any(ismissing(values) | strlength(values) == 0)
    return; % No complete scenario lifecycle: keep evidence visibly unbound.
end
if isempty(regexp(char(values(2)), '^[0-9a-f]{64}$', 'once'))
    error("sixgr:truth:CoupledControlIdentityInvalid", ...
        "Coupled %s requires a SHA-256 scenario configuration identity.",signalName);
end
names = ["ScenarioID","ConfigHash","RunTag","RunID","ExecutionID"];
expected = values([1 2 3 3 4]);
for k=1:numel(names)
    matches = find(strcmpi(string(T.Properties.VariableNames),names(k)));
    if numel(matches)>1
        error("sixgr:truth:CoupledControlIdentityMismatch", ...
            "Coupled %s has duplicate identity columns for %s.",signalName,names(k));
    end
    name=names(k);
    if ~isempty(matches)
        name=string(T.Properties.VariableNames{matches});
        actual=strtrim(string(T.(name)));
        populated=~ismissing(actual) & strlength(actual)>0 & lower(actual)~="nan";
        if any(populated & actual~=expected(k),'all')
            error("sixgr:truth:CoupledControlIdentityMismatch", ...
                "Coupled %s %s conflicts with the active runtime identity.",signalName,name);
        end
    end
    T.(name)=repmat(expected(k),height(T),1);
end
T=sixgr.kpi.bindTransportGoodputPublicationScope(T, ...
    struct('RunID',values(3),'ExecutionID',values(4),'ConfigHash',values(2)));
if ~bindInPathScope, return; end
if ismember("EvidenceScope",string(T.Properties.VariableNames))
    actual=strtrim(string(T.EvidenceScope));
    populated=~ismissing(actual) & strlength(actual)>0 & lower(actual)~="nan";
    assert(~any(populated & actual~="in_path"), ...
        'sixgr:truth:CoupledRuntimeEvidenceScopeMismatch', ...
        'Coupled %s cannot promote non-runtime evidence into in-path rows.',signalName);
end
if ismember("SameScenarioInPathEligible",string(T.Properties.VariableNames))
    eligible=T.SameScenarioInPathEligible;
    assert((isnumeric(eligible) || islogical(eligible)) && ...
        all(isfinite(eligible) & eligible==1,'all'), ...
        'sixgr:truth:CoupledRuntimeEvidenceEligibilityInvalid', ...
        'Coupled %s cannot overwrite invalid or explicitly ineligible evidence.',signalName);
end
T.EvidenceScope=repmat("in_path",height(T),1);
T.SameScenarioInPathEligible=true(height(T),1);
end
