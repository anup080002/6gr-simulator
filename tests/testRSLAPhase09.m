function tests = testRSLAPhase09
%TESTRSLAPHASE09 Focused Release-18 RSLA production and evidence suite.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = fileparts(fileparts(mfilename("fullpath")));
root = fullfile(repoRoot,"tests","vectors","rsla");
contract = sixgr.phy.rsla.RSLAUtil.readStrings( ...
    fullfile(root,"desired_rsla_csv_contract.csv"));
warningState = warning;
warningCleanup = onCleanup(@() warning(warningState)); %#ok<NASGU>
warning("off","all");
[tables,summary] = sixgr.phy.rsla.RSLABaseEvidenceBuilder.build( ...
    root,contract,"RSLA_TEST09",[11 23 47 89],0.95);
testCase.TestData.VectorRoot = root;
testCase.TestData.RepoRoot = repoRoot;
testCase.TestData.Tables = tables;
testCase.TestData.Summary = summary;
end

function testRSLACapabilityPlanning(testCase)
localEvidence(testCase,"rsla_capability_resolution",180);
localMasterAuthority(testCase);
end

function testRSLAUnsupportedTupleRejection(testCase)
localEvidence(testCase,"rsla_negative_tests",1);
end

function testRSLAResourceOwnership(testCase)
localEvidence(testCase,"rsla_resource_ownership",500);
end

function testRSLACollisionResolution(testCase)
localEvidence(testCase,"rsla_collision_resolution",120);
end

function testSharedDMRSDL(testCase)
localDirectionEvidence(testCase,"rsla_dmrs_matrix","DL");
end

function testSharedDMRSUL(testCase)
localDirectionEvidence(testCase,"rsla_dmrs_matrix","UL");
end

function testDMRSSequences(testCase)
localHashEvidence(testCase,"rsla_dmrs_matrix","SequenceSHA256");
end

function testDMRSPortsOCC(testCase)
localEvidence(testCase,"rsla_dmrs_matrix",192);
end

function testDMRSFrequencySelectiveRoundTrip(testCase)
localEvidence(testCase,"rsla_dmrs_matrix",192);
end

function testCSIRSResourceRows(testCase)
localEvidence(testCase,"rsla_csirs_matrix",114);
end

function testCSIRSNZPZP(testCase)
localTokenEvidence(testCase,"rsla_csirs_matrix","ResourceType",["NZP","ZP"]);
end

function testCSIRSCSIIM(testCase)
localTokenEvidence(testCase,"rsla_csirs_matrix","ResourceType","CSI-IM_ASSOCIATED");
end

function testCSIRSTriggering(testCase)
localTokenEvidence(testCase,"rsla_csirs_matrix","TriggerType", ...
    ["periodic","semiPersistent","aperiodic"]);
end

function testCSIRSMuting(testCase)
localEvidence(testCase,"rsla_csirs_matrix",114);
end

function testCSIRSMeasurementAssociation(testCase)
localEvidence(testCase,"rsla_measurement_results",120);
end

function testSRSPeriodic(testCase)
localTokenEvidence(testCase,"rsla_srs_matrix","ResourceType","periodic");
end

function testSRSSemiPersistent(testCase)
localTokenEvidence(testCase,"rsla_srs_matrix","ResourceType","semiPersistent");
end

function testSRSAperiodic(testCase)
localTokenEvidence(testCase,"rsla_srs_matrix","ResourceType","aperiodic");
end

function testSRSMultiPort(testCase)
localEvidence(testCase,"rsla_srs_matrix",162);
end

function testSRSCombCyclicShift(testCase)
localEvidence(testCase,"rsla_srs_matrix",162);
end

function testSRSFrequencyHopping(testCase)
localEvidence(testCase,"rsla_srs_matrix",162);
end

function testSRSChannelEstimation(testCase)
localHashEvidence(testCase,"rsla_srs_matrix","REIndexSHA256");
end

function testSRSSchedulerAuthority(testCase)
localEvidence(testCase,"rsla_srs_scheduler_consumption",1);
end

function testTRSResourceMapping(testCase)
localEvidence(testCase,"rsla_trs_tracking",100);
end

function testTRSNoOracleDetection(testCase)
localEvidence(testCase,"rsla_trs_tracking",100);
end

function testTRSCFOTracking(testCase)
localEvidence(testCase,"rsla_trs_tracking",100);
end

function testTRSTimingTracking(testCase)
localEvidence(testCase,"rsla_trs_tracking",100);
end

function testTRSCorrectionApplication(testCase)
localEvidence(testCase,"rsla_trs_tracking",100);
end

function testPTRSDL(testCase)
localDirectionEvidence(testCase,"rsla_ptrs_tracking","DL");
end

function testPTRSUL(testCase)
localDirectionEvidence(testCase,"rsla_ptrs_tracking","UL");
end

function testPTRSIndexVectors(testCase)
input = sixgr.phy.rsla.RSLAUtil.readStrings(fullfile( ...
    testCase.TestData.VectorRoot,"rsla_ptrs_tracking_test_vectors.csv"));
plan = sixgr.phy.rsla.PTRSResourceEngine.planVector(input(1,:));
verifyEqual(testCase,strlength(plan.IndexSHA256),64);
verifyGreaterThan(testCase,numel(plan.IndicesZeroBased),0);
end

function testPTRSPhaseCorrection(testCase)
localEvidence(testCase,"rsla_ptrs_tracking",96);
end

function testPTRSBenefitBoundaries(testCase)
localEvidence(testCase,"rsla_ptrs_tracking",96);
end

function testMeasurementRegistry(testCase)
localEvidence(testCase,"rsla_measurement_registry",8);
end

function testRSRPAnalytical(testCase)
localQuantityEvidence(testCase,"RSRP");
end

function testRSRQAnalytical(testCase)
localQuantityEvidence(testCase,"RSRQ");
end

function testSINRAnalytical(testCase)
localQuantityEvidence(testCase,"SINR");
end

function testRSSIAnalytical(testCase)
localQuantityEvidence(testCase,"RSSI");
end

function testSRSRSRPAnalytical(testCase)
localQuantityEvidence(testCase,"SRS-RSRP");
end

function testMeasurementInvalidResources(testCase)
localEvidence(testCase,"rsla_negative_tests",1);
end

function testCSIReportConfiguration(testCase)
localEvidence(testCase,"rsla_csi_report_resolution",1);
end

function testCSIPart1Serialization(testCase)
localEvidence(testCase,"rsla_csi_bit_ownership",200);
end

function testCSIPart2Serialization(testCase)
localEvidence(testCase,"rsla_csi_bit_ownership",200);
end

function testCSIReportPUCCH(testCase)
localTokenEvidence(testCase,"rsla_csi_uci_roundtrip","Transport","PUCCH");
end

function testCSIReportPUSCH(testCase)
localTokenEvidence(testCase,"rsla_csi_uci_roundtrip","Transport","PUSCH");
end

function testCSIWrongLength(testCase)
localEvidence(testCase,"rsla_negative_tests",1);
end

function testCSIDecodedSchedulerAuthority(testCase)
localEvidence(testCase,"rsla_link_adaptation_decisions",1);
end

function testMeasuredOnlyGuard(testCase)
localEvidence(testCase,"rsla_measured_state_validity",160);
end

function testMeasurementAgeIdentity(testCase)
localEvidence(testCase,"rsla_measured_state_validity",160);
end

function testBootstrapTransition(testCase)
localEvidence(testCase,"rsla_bootstrap_transition",1);
end

function testCQIMCSCalibrationSchema(testCase)
localEvidence(testCase,"rsla_cqi_mcs_calibration",1);
end

function testCQIMCSCalibrationCampaign(testCase)
localEvidence(testCase,"rsla_cqi_mcs_calibration",1);
end

function testCQIMCSHoldoutValidation(testCase)
localEvidence(testCase,"rsla_effective_sinr_trials",120);
end

function testEESMFormula(testCase)
localTokenEvidence(testCase,"rsla_effective_sinr_trials","Method","EESM");
end

function testMIESMMapping(testCase)
result = sixgr.phy.rsla.MIESMMapper.map([-3 -1 2 5],1.2, ...
    "RSLA-MIESM-TEST");
verifyTrue(testCase,isfinite(result.EffectiveSINRDb));
verifyEqual(testCase,result.Method,"MIESM");
verifyEqual(testCase,strlength(result.InputSHA256),64);
end

function testEffectiveSINRCalibrationMissing(testCase)
localEvidence(testCase,"rsla_negative_tests",1);
end

function testEffectiveSINRHoldoutValidation(testCase)
localEvidence(testCase,"rsla_effective_sinr_trials",120);
end

function testOLLAStepBalance(testCase)
localEvidence(testCase,"rsla_olla_state",1);
end

function testOLLAConvergence(testCase)
localEvidence(testCase,"rsla_olla_convergence",1);
end

function testOLLASaturationReset(testCase)
localEvidence(testCase,"rsla_olla_state",1);
end

function testOLLAMultiUEIsolation(testCase)
localEvidence(testCase,"rsla_olla_state",1);
end

function testL3Filtering(testCase)
localEvidence(testCase,"rsla_measurement_filter_trace",40);
end

function testMeasurementGaps(testCase)
localEvidence(testCase,"rsla_measurement_gap_trace",1);
end

function testRRMEventA1A2(testCase)
localEventEvidence(testCase,["A1","A2"]);
end

function testRRMEventA3A4(testCase)
localEventEvidence(testCase,["A3","A4"]);
end

function testRRMEventA5A6(testCase)
localEventEvidence(testCase,["A5","A6"]);
end

function testEVMAnalytical(testCase)
localEvidence(testCase,"rsla_evm_measurements",100);
end

function testEVMPTRSDMRSContext(testCase)
localEvidence(testCase,"rsla_evm_measurements",100);
end

function testRSLAArtifactGeneration(testCase)
warningState = warning;
warningCleanup = onCleanup(@() warning(warningState)); %#ok<NASGU>
warning("off","all");
summary = sixgr.phy.rsla.runRSLAPhaseValidation( ...
    "VectorRoot",testCase.TestData.VectorRoot, ...
    "OutputDir",fullfile(testCase.TestData.RepoRoot,"artifacts","rsla_phase"), ...
    "SeedList",[11 23 47 89],"ConfidenceLevel",0.95,"Strict",true);
verifyTrue(testCase,summary.Passed);
verifyEqual(testCase,summary.CSVCount,32);
verifyEqual(testCase,summary.PNGCount,22);
end

function testRSLAImpactAnalysis(testCase)
summary = sixgr.phy.rsla.runRSLAImpactAnalysis( ...
    "ExperimentMatrix",fullfile(testCase.TestData.VectorRoot, ...
        "rsla_impact_experiment_matrix.csv"), ...
    "OutputDir",fullfile(testCase.TestData.RepoRoot,"artifacts","rsla_impact"), ...
    "SeedList",[11 23 47 89 131 197], ...
    "ConfidenceLevel",0.95,"Strict",true);
verifyTrue(testCase,summary.Passed);
verifyEqual(testCase,summary.ExperimentCount,768);
verifyEqual(testCase,summary.PairCount,384);
verifyEqual(testCase,summary.RuleCount,96);
end

function localEvidence(testCase,name,minimumRows)
value = testCase.TestData.Tables.(name);
verifyGreaterThanOrEqual(testCase,height(value),minimumRows,name);
verifyTrue(testCase,all(upper(string(value.Status))=="PASS"),name);
end

function localDirectionEvidence(testCase,name,direction)
value = testCase.TestData.Tables.(name);
rows = value(upper(string(value.Direction))==upper(string(direction)),:);
verifyGreaterThan(testCase,height(rows),0,name+" "+direction);
verifyTrue(testCase,all(upper(string(rows.Status))=="PASS"),name);
end

function localHashEvidence(testCase,name,column)
value = testCase.TestData.Tables.(name);
verifyTrue(testCase,all(strlength(string(value.(column)))==64),name);
verifyTrue(testCase,all(upper(string(value.Status))=="PASS"),name);
end

function localTokenEvidence(testCase,name,column,tokens)
value = testCase.TestData.Tables.(name);
for token = string(tokens)
    rows = value(strcmpi(string(value.(column)),token),:);
    verifyGreaterThan(testCase,height(rows),0,name+" "+token);
    verifyTrue(testCase,all(upper(string(rows.Status))=="PASS"),name);
end
end

function localQuantityEvidence(testCase,token)
value = testCase.TestData.Tables.rsla_measurement_results;
rows = value(contains(upper(string(value.Quantity)),upper(string(token))),:);
verifyGreaterThan(testCase,height(rows),0,token);
verifyTrue(testCase,all(upper(string(rows.Status))=="PASS"),token);
end

function localEventEvidence(testCase,tokens)
value = testCase.TestData.Tables.rsla_rrm_event_trace;
rows = value(ismember(upper(string(value.EventID)),upper(string(tokens))),:);
verifyGreaterThan(testCase,height(rows),0);
verifyTrue(testCase,all(upper(string(rows.Status))=="PASS"));
end

function localMasterAuthority(testCase)
paths = [
    fullfile(testCase.TestData.RepoRoot,"simulator","configs","scenarios", ...
        "master_sinr_sweep.yaml")
    fullfile(testCase.TestData.RepoRoot,"simulator","configs","scenarios", ...
        "master_geometry_based.yaml")
    ];
for path = string(paths).'
    raw = sixgr.lls6g.config.readConfigFile(path);
    block = sixgr.util.structGet(raw, ...
        "canonical_control.reference_signals.rsla_strict",[]);
    verifyTrue(testCase,isstruct(block)&&isscalar(block),path);
    verifyTrue(testCase,logical(block.strict),path);
    verifyEqual(testCase,string(block.profile_id),"nr_rel18_rsla_strict");
    scfg = sixgr.lls6g.config.loadScenarioConfig(path);
    cfg = sixgr.lls6g.buildInternalConfig(scfg,tempname);
    verifyEqual(testCase,string(sixgr.util.structGet(cfg, ...
        "phy.rsla.configuration_authority","")),"operator_master_yaml");
    verifyEqual(testCase,string(sixgr.util.structGet(cfg, ...
        "phy.rsla.validation.unsupported_tuple_policy","")), ...
        "reject_before_waveform");
end
end
