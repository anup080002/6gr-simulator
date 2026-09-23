function receipt=diagnoseAWGNMIMOReconciliation(scenarioPath,sourceRun,outputRoot)
% Re-run the production audit on retained primary rows, never in-place.
assert(~isfolder(outputRoot),'test:EvidenceExists','Preserve earlier audit receipts.');
s=sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg=sixgr.lls6g.buildInternalConfig(s,outputRoot);
raw=struct(); sources=struct('Direction',{},'Path',{},'SHA256',{});
for direction=["DL","UL"]
    stem="dl_pdsch"; if direction=="UL", stem="ul_pusch"; end
    path=fullfile(sourceRun,'air_interface','csv',stem+"_trials.csv");
    assert(isfile(path),'test:MissingRetainedTrials','Require actual retained %s trials.',direction);
    hash=sixgr.util.sha256File(path);
    raw.(direction)=readtable(path,'TextType','string','VariableNamingRule','preserve');
    assert(~isempty(raw.(direction)) && sixgr.util.sha256File(path)==hash, ...
        'test:RetainedTrialsChanged','Require a nonempty unchanged primary table during this read.');
    sources(end+1)=struct('Direction',direction,'Path',string(path),'SHA256',hash); %#ok<AGROW>
end
artifacts=sixgr.analytics.writeRFInterferenceReconciliation(cfg,outputRoot,raw,struct(),struct());
T=artifacts.Tables.MIMO;
receipt=struct('Scope',"retained_primary_rows_production_MIMO_audit_not_PHY_rerun", ...
    'Sources',sources,'OutputRoot',string(outputRoot),'Table',table2struct(T), ...
    'Ok',all(T.DL_RuntimeArrayModelOk & T.UL_RuntimeArrayModelOk & T.MimoKpiReconciliationOk));
sixgr.util.jsonWrite(fullfile(outputRoot,'receipt.json'),receipt);
disp(T(:,{'DL_RuntimeArrayModelOk','UL_RuntimeArrayModelOk', ...
    'DL_RuntimeArrayEvaluationStatus','UL_RuntimeArrayEvaluationStatus','MimoKpiReconciliationOk'}));
assert(receipt.Ok,'test:IdentityAWGNMIMOReconciliation', ...
    'The production MIMO audit rejects retained identity-AWGN execution; inspect the immutable receipt.');
end
