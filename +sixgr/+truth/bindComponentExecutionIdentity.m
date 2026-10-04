function T = bindComponentExecutionIdentity(T, cfg, signalName)
%BINDCOMPONENTEXECUTIONIDENTITY Bind fresh isolated waveform evidence.
% Lifecycle ownership does not confer connected-runtime eligibility. Call
% this at the component producer boundary, never on retained external files.
if ~istable(T) || isempty(T)
    return;
end
if ismember("EvidenceScope",string(T.Properties.VariableNames))
    scope = lower(strtrim(string(T.EvidenceScope)));
    populated = ~ismissing(scope) & strlength(scope)>0 & scope~="nan";
    assert(~any(populated & scope~="component_anchor"), ...
        'sixgr:truth:ComponentEvidenceScopeConflict', ...
        'Component %s contains a different declared evidence scope.',signalName);
end
if ismember("SameScenarioInPathEligible",string(T.Properties.VariableNames))
    assert(all(T.SameScenarioInPathEligible==false), ...
        'sixgr:truth:ComponentEvidenceScopeConflict', ...
        'Component %s cannot contain in-path-eligible rows.',signalName);
end
% This existing binder owns only immutable run/config fields. It neither
% invents a lifecycle for low-level callers nor changes receiver outcomes.
T = sixgr.truth.bindCoupledExecutionIdentity(T,cfg,signalName);
T.EvidenceScope = repmat("component_anchor",height(T),1);
T.SameScenarioInPathEligible = false(height(T),1);
% Some standalone RS collectors do not set a source classification. The
% fresh producer boundary knows this scope; leaving it blank lets the
% generic canonicalizer later default to an integrated-runtime label.
% Preserve explicit proxy/failure/other labels and all physical outcomes.
if ~ismember("SourceClassification",string(T.Properties.VariableNames))
    T.SourceClassification = strings(height(T),1);
end
classification=string(T.SourceClassification);
missing=ismissing(classification) | strlength(strtrim(classification))==0;
classification(missing)="isolated_component_waveform";
T.SourceClassification=classification;
end
