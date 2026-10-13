function ok=testStandalonePHYCalibrationEvidenceScope()
% Missing rows never grant a reporting exemption to connected execution.
scfg=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/fixtures/lls_result_richness.yaml');
cfg=sixgr.lls6g.buildInternalConfig(scfg,tempname(fullfile(pwd,'logs')));
scope=sixgr.truth.standalonePHYCalibrationEvidenceScope(scfg,cfg);
assert(scope.IndependentPHY && numel(scope.ConnectedFields)==7);
for name=["pbchRequired","prachRequired","pdcchRequired","pucchRequired", ...
        "puschUCIRequired","srsRequired","trsRequired"]
    for value={true,NaN,[],"false"}
        changed=sixgr.util.structSet(cfg,"run.controlGating."+name,value{1});
        actual=sixgr.truth.standalonePHYCalibrationEvidenceScope(scfg,changed);
        assert(~actual.IndependentPHY);
    end
end
for path=["run.pdschExecutionProfile","phy.pdsch.executionProfile", ...
        "phy.pusch.executionProfile"]
    changed=sixgr.util.structSet(cfg,path,"scheduler_truth");
    actual=sixgr.truth.standalonePHYCalibrationEvidenceScope(scfg,changed);
    assert(~actual.IndependentPHY);
end
changed=sixgr.util.structSet(cfg,"lls6g.users.execution_model","slot_coupled_truth");
actual=sixgr.truth.standalonePHYCalibrationEvidenceScope(scfg,changed);
assert(~actual.IndependentPHY);
source=scfg.toStruct();
source=sixgr.util.structSet(source,"users.execution_model","slot_coupled_truth");
actual=sixgr.truth.standalonePHYCalibrationEvidenceScope(source,cfg);
assert(~actual.IndependentPHY);
actual=sixgr.truth.standalonePHYCalibrationEvidenceScope(struct(),struct());
assert(~actual.IndependentPHY);
fprintf('STANDALONE_PHY_SCOPE_PASS explicit_profiles_and_all_causal_gates=1\n');
ok=true;
end
