function out = evaluateConfiguredControlEvidence(cfg, rawTrials, policy)
%EVALUATECONFIGUREDCONTROLEVIDENCE Evaluate declared scope, never infer from rows.
families=["PDCCH","PUCCH","PUSCH_UCI"];
enableFields=["EnablePDCCH","EnablePUCCH","EnablePUSCHUCI"];
scopeFields=["PDCCHScope","PUCCHScope","PUSCHUCIScope"];
out=struct("PDCCH",struct(),"PUCCH",struct(),"PUSCH_UCI",struct());
rows=repmat(struct("SignalFamily","","StrictOk",false,"TrialRows",0, ...
    "FailureReason","","EvidenceScope",""),0,1);
for k=1:numel(families)
    if ~policy.(enableFields(k)), continue; end
    component=lower(families(k));
    scope=policy.(scopeFields(k));
    if scope=="component_anchor"
        result=sixgr.truth.evaluateComponentControlEvidence(cfg,rawTrials,component);
    elseif scope=="in_path"
        result=sixgr.truth.evaluateInPathComponentEvidence(cfg,rawTrials,component);
    else
        error("sixgr:truth:InvalidControlEvidenceScope","Unknown control evidence scope.");
    end
    out.(families(k))=result;
    rows(end+1,1)=struct("SignalFamily",families(k), ...
        "StrictOk",logical(result.StrictOk), ...
        "TrialRows",height(result.ArtifactTables.(component+"_trials")), ...
        "FailureReason",string(result.FailureReason),"EvidenceScope",scope); %#ok<AGROW>
end
out.SummaryTable=struct2table(rows,"AsArray",true);
out.Ok=~isempty(rows) && all([rows.StrictOk]);
out.StrictOk=out.Ok;
bad=out.SummaryTable(~out.SummaryTable.StrictOk,:);
out.FailureReason=strjoin(bad.SignalFamily+":"+bad.FailureReason,"; ");
out.EvidenceScope=strjoin(unique(out.SummaryTable.EvidenceScope,"stable"),"+");
out.SameScenarioInPathEligible=out.Ok && all(out.SummaryTable.EvidenceScope=="in_path");
out.LaunchedSupplementalWaveform=false;
end
