function report=diagnoseN40CompactCausalEvidence(original,output)
% Original raw-row publication/re-audit, not native execution or recovery.
assert(isfolder(original)&&~isfolder(output),'test:DiagnosticFolderExists');
mkdir(output); paths=strings(0,1); hashes=strings(0,1);
configPath=copyOriginal('meta/scenario_config_resolved.json');
identity=jsondecode(fileread(copyOriginal('meta/scenario_config_identity.json')));
execution=jsondecode(fileread(copyOriginal('meta/execution_identity.json')));
assert(string(sixgr.util.sha256File(configPath))==string(identity.ResolvedJSONSHA256)&& ...
    string(execution.ConfigHash)==string(identity.ConfigHash),'test:OriginalConfigHash');
scfg=jsondecode(fileread(configPath)); cfg=sixgr.lls6g.buildInternalConfig(scfg,output);
cfg.meta.configHash=char(identity.ConfigHash); cfg.run.runTag=char(execution.RunID);
cfg.run.executionID=char(execution.ExecutionID); cfg.meta.executionID=char(execution.ExecutionID);
old=sixgr.util.csvReadTable(fullfile(original,'reports','csv','causal_phy_chain_audit.csv'),'TextType','string');
for relative=unique([string(old.MeasurementArtifact);"reports/csv/runtime_call_ledger.csv"; ...
        "reports/csv/runtime_function_profile.csv";"reports/csv/causal_phy_parameter_authority.csv"; ...
        "control/csv/pdcch_trials.csv"], 'stable').'
    if isfile(fullfile(original,relative)), copyOriginal(relative); end
end
raw=struct();
for pair={"DL","dl_pdsch_trials";"UL","ul_pusch_trials"}.'
    raw.(pair{1})=sixgr.util.csvReadTable(fullfile(output,'air_interface','csv',pair{2}+".csv"),'TextType','string');
end
report=struct('Ok',false,'Scope',"original_retained_rows_compact_publication_no_RF_no_checkpoint", ...
    'PrimaryStudyEligible',false,'FullRunQualified',false,'OriginalsUnchanged',false);
try
    rngBefore=rng;
    result=sixgr.truth.exportCompactCausalStageEvidence(output,cfg,raw);
    assert(isequal(rngBefore,rng),'test:PublicationChangedRNG');
    full=sixgr.mimo.resolveNominalVsEffectiveMIMO(cfg,raw,'RunId',string(execution.RunID), ...
        'ScenarioName',string(sixgr.util.structGet(cfg,'run.scenarioID',"")));
    assert(isequaln(full.PrecoderEvidence,result.PrecoderEvidence),'test:CompactFinalMismatch');
    gate=sixgr.truth.exportCausalPHYChainAudit(output,scfg,cfg,'RunId',string(execution.RunID));
    audit=sixgr.util.csvReadTable(fullfile(output,'reports','csv','causal_phy_chain_audit.csv'),'TextType','string');
    target=ismember(string(audit.StageID),["connected_pdcch_grant_binding","beam_precoder_application"]);
    assert(nnz(target)==2&&all(audit.StrictPass(target)),'test:BaseStagePublicationFailed');
    report.Ok=true; report.BindingRows=height(result.Binding.Rows);
    report.BindingGateOk=result.Binding.BindingGateOk;
    report.PrecoderRows=height(result.PrecoderEvidence); report.CausalGateOk=gate.Ok;
    report.CausalStageChecks=table2struct(audit(:,{'StageID','StageOutcome','StrictPass','EvidenceRows','FailureReason'}));
    report.RNGUnchanged=true;
catch cause
    report.ErrorIdentifier=string(cause.identifier); report.Error=string(cause.message);
end
after=strings(size(hashes));
for k=1:numel(paths), after(k)=sixgr.util.sha256File(paths(k)); end
report.OriginalsUnchanged=isequal(hashes,after); report.Ok=report.Ok&&report.OriginalsUnchanged;
report.OriginalFiles=table2struct(table(paths,hashes,after,'VariableNames',{'Path','BeforeSHA256','AfterSHA256'}));
report.Path=string(fullfile(output,'receipt.json'));
sixgr.util.jsonWrite(report.Path,report);
    function destination=copyOriginal(relative)
        source=fullfile(original,relative); destination=fullfile(output,relative);
        paths(end+1,1)=string(source); hashes(end+1,1)=sixgr.util.sha256File(source);
        sixgr.util.ensureFolder(fileparts(destination)); copyfile(source,destination);
        assert(sixgr.util.sha256File(destination)==hashes(end),'test:OriginalCopyHash');
    end
end
