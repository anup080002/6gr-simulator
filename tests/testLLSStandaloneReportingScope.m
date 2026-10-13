function ok=testLLSStandaloneReportingScope()
% Exercise the production exporter and truth gate, not only a scope helper.
scfg=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/fixtures/lls_result_richness.yaml');
root=tempname(fullfile(pwd,'logs')); mkdir(root);
cfg=sixgr.lls6g.buildInternalConfig(scfg,root);
scope=sixgr.truth.standalonePHYCalibrationEvidenceScope(scfg,cfg);
assert(scope.IndependentPHY);
artifacts=sixgr.truth.exportLLSConfigOwnershipArtifacts(root,scfg,cfg);
audit=sixgr.util.csvReadTable(artifacts.ValueSourceAudit,'TextType','string');
selected=ismember(string(audit.FieldName),scope.ConnectedFields);
assert(nnz(selected)==8 && all(string(audit.ConsistencyStatus(selected))=="not_applicable") && ...
    all(string(audit.NAReason(selected))==scope.Reason), ...
    'Independent PHY calibration must not claim observed connected scheduler state.');
values=string(audit.ObservedValue(selected));
assert(all(ismissing(values) | strlength(values)==0), ...
    'No synthetic connected-state values may be inserted.');
verdict=sixgr.truth.evaluateLLSRuntimeTruthContract(root,scfg,cfg);
failures=string(verdict.Failures);
assert(~verdict.Ok && verdict.RequiredRuntimeEvidenceMissingCount>0, ...
    'Reporting applicability must not accept an empty physical evidence folder.');
assert(~any(contains(failures,"live_dl_scheduler_grants")) && ...
    ~any(contains(failures,"live_ul_scheduler_grants")), ...
    'Independent PHY execution has no connected scheduler trace to fabricate.');

% A causal control requirement restores the original missing-evidence gate.
connected=sixgr.util.structSet(cfg,'run.controlGating.pdcchRequired',true);
connectedRoot=tempname(fullfile(pwd,'logs')); mkdir(connectedRoot);
artifacts=sixgr.truth.exportLLSConfigOwnershipArtifacts(connectedRoot,scfg,connected);
audit=sixgr.util.csvReadTable(artifacts.ValueSourceAudit,'TextType','string');
selected=ismember(string(audit.FieldName),scope.ConnectedFields);
assert(all(string(audit.ConsistencyStatus(selected))=="unavailable"));
verdict=sixgr.truth.evaluateLLSRuntimeTruthContract(connectedRoot,scfg,connected);
assert(~verdict.Ok && any(contains(string(verdict.Failures),"live_dl_scheduler_grants")), ...
    'A causal control request must not inherit standalone reporting exemptions.');
fprintf('LLS_STANDALONE_REPORT_SCOPE_PASS no_invented_grants_or_relaxed_connected_gate=1\n');
ok=true;
end
