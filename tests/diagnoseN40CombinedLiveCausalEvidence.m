function report=diagnoseN40CombinedLiveCausalEvidence(original,output)
% Current live reducer chain over original rows, never a native run pass.
report=diagnoseN40CompactCausalEvidence(original,output);
copyfile(report.Path,fullfile(output,'compact_projection_receipt.json'));
assert(report.Ok,'test:CompactReplayFailed','Keep the original failed diagnostic receipt.');
report.Ok=false; report.Scope="original_retained_rows_current_receiver_and_causal_publication_no_RF_no_checkpoint";
try
    scfg=jsondecode(fileread(fullfile(output,'meta','scenario_config_resolved.json')));
    identity=jsondecode(fileread(fullfile(output,'meta','scenario_config_identity.json')));
    execution=jsondecode(fileread(fullfile(output,'meta','execution_identity.json')));
    cfg=sixgr.lls6g.buildInternalConfig(scfg,output);
    cfg.meta.configHash=char(identity.ConfigHash); cfg.run.runTag=char(execution.RunID);
    cfg.run.executionID=char(execution.ExecutionID); cfg.meta.executionID=char(execution.ExecutionID);
    raw=struct('DL',sixgr.util.csvReadTable(fullfile(output,'air_interface','csv','dl_pdsch_trials.csv'),'TextType','string'), ...
        'UL',sixgr.util.csvReadTable(fullfile(output,'air_interface','csv','ul_pusch_trials.csv'),'TextType','string'));
    before=rng;
    published=sixgr.truth.exportLLSLiveDerivedTables(cfg,output,raw,struct(),struct(),struct(),'receiver_observations');
    assert(isequal(before,rng),'test:PublicationChangedRNG');
    L=published.LinkAdaptationInput;
    report.LinkAdaptationRows=height(L);
    report.AppliedFeedbackRows=nnz(L.LinkAdaptationApplied);
    report.UnappliedFeedbackRows=nnz(~L.LinkAdaptationApplied);
    assert(height(L)==13&&report.AppliedFeedbackRows==5&&report.UnappliedFeedbackRows==8, ...
        'test:OriginalAdaptationPopulation','Keep original applied/unapplied populations.');
    gate=sixgr.truth.exportCausalPHYChainAudit(output,scfg,cfg,'RunId',string(execution.RunID));
    audit=sixgr.util.csvReadTable(fullfile(output,'reports','csv','causal_phy_chain_audit.csv'),'TextType','string');
    report.CausalGateOk=gate.Ok;
    report.CausalStageChecks=table2struct(audit(:,{'StageID','StageOutcome','StrictPass','EvidenceRows','FailureReason'}));
    report.Ok=gate.Ok;
catch cause
    report.ErrorIdentifier=string(cause.identifier); report.Error=string(cause.message);
end
for k=1:numel(report.OriginalFiles)
    report.OriginalFiles(k).AfterSHA256=sixgr.util.sha256File(report.OriginalFiles(k).Path);
end
report.OriginalsUnchanged=all(string({report.OriginalFiles.BeforeSHA256})==string({report.OriginalFiles.AfterSHA256}));
report.Ok=report.Ok&&report.OriginalsUnchanged;
sixgr.util.jsonWrite(report.Path,report);
end
