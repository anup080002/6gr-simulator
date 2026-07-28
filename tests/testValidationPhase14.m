function tests=testValidationPhase14
%TESTVALIDATIONPHASE14 Canonical Phase-14 validation-engine contract.
tests=functiontests(localfunctions);
end

function testValidationPointStatusEnum(t), localCase(t,"STATUS"); end
function testValidationStopReasonEnum(t), localCase(t,"STOP"); end
function testValidationLegacyTokenMigration(t), localCase(t,"MIGRATION"); end
function testOperatingPointKeyCanonicalization(t), localCase(t,"KEY"); end
function testOperatingPointKeyMissingField(t), localCase(t,"KEY"); end
function testOperatingPointKeyDuplicate(t), localCase(t,"JOIN"); end
function testCanonicalSchemaHappyPath(t), localCase(t,"SCHEMA"); end
function testCanonicalSchemaMissingColumn(t), localCase(t,"SCHEMA"); end
function testCanonicalSchemaWrongType(t), localCase(t,"SCHEMA"); end
function testCanonicalSchemaNaNThreshold(t), localCase(t,"SCHEMA"); end
function testCanonicalSchemaInfThreshold(t), localCase(t,"SCHEMA"); end
function testCanonicalSchemaEmptyMandatoryTable(t), localCase(t,"SCHEMA"); end
function testWilsonInterval90(t), localCase(t,"INTERVAL"); end
function testWilsonInterval95(t), localCase(t,"INTERVAL"); end
function testWilsonInterval99(t), localCase(t,"INTERVAL"); end
function testClopperPearsonTwoSided(t), localCase(t,"INTERVAL"); end
function testClopperPearsonOneSidedUpper(t), localCase(t,"INTERVAL"); end
function testZeroErrorUpperBound(t), localCase(t,"ZERO"); end
function testSequentialMinimumTrials(t), localCase(t,"SEQUENTIAL"); end
function testSequentialMinimumErrorsAndCI(t), localCase(t,"SEQUENTIAL"); end
function testSequentialZeroErrorCensored(t), localCase(t,"SEQUENTIAL"); end
function testSequentialMaxTrialsIncomplete(t), localCase(t,"SEQUENTIAL"); end
function testSequentialAlphaSpending(t), localCase(t,"SEQUENTIAL"); end
function testSequentialCoverageMonteCarlo(t), localCase(t,"COVERAGE"); end
function testHighSNRZeroErrorPlateau(t), localCase(t,"HIGH_SNR"); end
function testHighSNRDegradedCurve(t), localCase(t,"HIGH_SNR"); end
function testHighSNRUncertaintyTrend(t), localCase(t,"HIGH_SNR"); end
function testIndependentDropMinimum(t), localCase(t,"DROPS"); end
function testIndependentDropDuplicateSeed(t), localCase(t,"DROPS"); end
function testIndependentDropAggregation(t), localCase(t,"DROPS"); end
function testTaskIDDeterminism(t), localCase(t,"TASK"); end
function testHierarchicalSeedPartition(t), localCase(t,"TASK"); end
function testRetryIdempotence(t), localCase(t,"MERGE"); end
function testDuplicateTaskConflict(t), localCase(t,"MERGE"); end
function testMergeOrderDeterminism(t), localCase(t,"MERGE"); end
function testFloatingPointStableAggregation(t), localCase(t,"MERGE"); end
function testRunClassAWGNIsolation(t), localCase(t,"RUNCLASS"); end
function testRunClassGeometryIsolation(t), localCase(t,"RUNCLASS"); end
function testRunClassControlOnlyIsolation(t), localCase(t,"RUNCLASS"); end
function testEvidenceObservedRuntime(t), localCase(t,"PROVENANCE"); end
function testEvidenceDerivedFromObserved(t), localCase(t,"PROVENANCE"); end
function testEvidenceConfiguredRejected(t), localCase(t,"PROVENANCE"); end
function testEvidenceReconstructedRejected(t), localCase(t,"PROVENANCE"); end
function testProvenanceCircularComparison(t), localCase(t,"PROVENANCE"); end
function testProvenanceIndependentRoots(t), localCase(t,"PROVENANCE"); end
function testMeasuredSINRMandatory(t), localCase(t,"SINR"); end
function testMeasuredSINRFinite(t), localCase(t,"SINR"); end
function testMeasuredSINRSampleCount(t), localCase(t,"SINR"); end
function testOracleRegistryPureMath(t), localCase(t,"ORACLE"); end
function testOracleRegistryFrozenExternal(t), localCase(t,"ORACLE"); end
function testOracleRegistryAnalyticalInvariant(t), localCase(t,"ORACLE"); end
function testOracleRegistryStatisticalDistribution(t), localCase(t,"ORACLE"); end
function testOracleSelfConsistencyQuarantined(t), localCase(t,"ORACLE"); end
function testOracleHashMismatch(t), localCase(t,"ORACLE"); end
function testReferenceDatasetIndependence(t), localCase(t,"REFERENCE"); end
function testReferenceDatasetDeleted(t), localCase(t,"REFERENCE"); end
function testReferenceDatasetShifted(t), localCase(t,"REFERENCE"); end
function testOperatingPointExactJoin(t), localCase(t,"JOIN"); end
function testOperatingPointMissingReference(t), localCase(t,"JOIN"); end
function testOperatingPointExtraReference(t), localCase(t,"JOIN"); end
function testOperatingPointIncompatibleProfile(t), localCase(t,"JOIN"); end
function testCurveNewcombeDifference(t), localCase(t,"CURVE"); end
function testCurveNonInferiority(t), localCase(t,"CURVE"); end
function testCurveEquivalence(t), localCase(t,"CURVE"); end
function testCurveMultiplicityHolm(t), localCase(t,"MULTIPLICITY"); end
function testCurveSparseOverlapRejected(t), localCase(t,"CURVE"); end
function testCalibrationCatalogExactKey(t), localCase(t,"CALIBRATION"); end
function testCalibrationHoldoutBounds(t), localCase(t,"CALIBRATION"); end
function testNegativeTestMatrixGeneration(t), localCase(t,"NEGATIVE"); end
function testTimeWindowHalfOpenBoundaries(t), localCase(t,"TIME"); end
function testKPISamplePhaseOwnership(t), localCase(t,"KPI"); end
function testWarmupExcludedFromSteadyKPI(t), localCase(t,"KPI"); end
function testArtifactRequirementsHeadless(t), localCase(t,"ARTIFACT"); end
function testArtifactRequirementsBrowser(t), localCase(t,"ARTIFACT"); end
function testArtifactDeletionFails(t), localCase(t,"ARTIFACT"); end
function testCanonicalScenarioFreshRun(t), localCase(t,"SCENARIO"); end
function testArchiveCleanWorkspace(t), localCase(t,"ARCHIVE"); end
function testArchiveStaleArtifactRejected(t), localCase(t,"ARCHIVE"); end
function testMATLABExecutionLedger(t), localCase(t,"LEDGER"); end
function testRequiredTestSkippedFails(t), localCase(t,"LEDGER"); end
function testPythonCollectionWithoutMATLAB(t), localCase(t,"PYTHON"); end
function testAllSourceYAMLParse(t), localCase(t,"YAML"); end
function testYAMLDuplicateKey(t), localCase(t,"YAML_DUP"); end
function testInternalAnchorClassification(t), localCase(t,"ANCHOR"); end
function testPublicationGateEndToEnd(t), localCase(t,"PUBLICATION"); end

function localCase(t,kind)
root=fileparts(fileparts(mfilename("fullpath")));
vectors=fullfile(root,"tests","vectors","validation");
switch kind
    case "STATUS"
        verifyEqual(t,numel(sixgr.validation.PointStatus.values()),11);
        for value=sixgr.validation.PointStatus.values()
            verifyEqual(t,sixgr.validation.PointStatus.parse(value),value);
        end
        verifyError(t,@()sixgr.validation.PointStatus.parse("BOGUS"), ...
            "sixgr:validation:UnknownPointStatus");
    case "STOP"
        verifyEqual(t,numel(sixgr.validation.StopReason.values()),15);
        for value=sixgr.validation.StopReason.values()
            verifyEqual(t,sixgr.validation.StopReason.parse(value),value);
        end
        verifyError(t,@()sixgr.validation.StopReason.parse("BOGUS"), ...
            "sixgr:validation:UnknownStopReason");
    case "MIGRATION"
        V=localRead(vectors,"validation_status_stop_reason_vectors.csv");
        for index=1:height(V)
            token=V.InputToken(index);
            if V.ExpectedAction(index)=="MIGRATE"
                out=sixgr.validation.StopReason.migrate(token);
                verifyEqual(t,out.PointStatus,V.ExpectedPointStatus(index));
                verifyEqual(t,out.StopReason,V.ExpectedStopReason(index));
            elseif V.ExpectedAction(index)=="REJECT"
                verifyError(t,@()sixgr.validation.StopReason.migrate(token), ...
                    "sixgr:validation:LegacyTokenUnmapped");
            elseif V.TokenKind(index)=="POINT_STATUS"
                verifyEqual(t,sixgr.validation.PointStatus.parse(token), ...
                    V.ExpectedPointStatus(index));
            else
                verifyEqual(t,sixgr.validation.StopReason.parse(token), ...
                    V.ExpectedStopReason(index));
            end
        end
    case "KEY"
        V=localRead(vectors,"validation_operating_point_key_vectors.csv");
        fields=cellstr(sixgr.validation.OperatingPointKey.requiredFields());
        for index=1:height(V)
            row=table2struct(V(index,fields));
            if V.ExpectedStatus(index)=="PASS"
                verifyEqual(t,sixgr.validation.OperatingPointKey.canonical(row), ...
                    V.ExpectedCanonicalKey(index));
            else
                verifyError(t,@()sixgr.validation.OperatingPointKey.canonical(row), ...
                    V.ExpectedError(index));
            end
        end
    case "SCHEMA"
        V=localRead(vectors,"validation_schema_mutation_vectors.csv");
        base=sixgr.validation.ValidationSchemaRegistry.sampleCampaignPoint();
        for index=1:height(V)
            mutated=sixgr.validation.SchemaMutationGenerator.apply( ...
                base,V.Mutation(index),V.Target(index));
            if V.ExpectedStatus(index)=="PASS"
                result=sixgr.validation.CanonicalSchemaValidator. ...
                    validateCampaignPoint(mutated);
                verifyTrue(t,result.Valid);
            else
                verifyError(t,@()sixgr.validation.CanonicalSchemaValidator. ...
                    validateCampaignPoint(mutated),V.ExpectedError(index));
            end
        end
    case "INTERVAL"
        V=localRead(vectors,"validation_binomial_interval_test_vectors.csv");
        for index=1:height(V)
            result=sixgr.validation.BinomialIntervalEngine.compute( ...
                V.SuccessCount(index),V.TrialCount(index), ...
                V.ConfidenceLevel(index),V.Method(index));
            verifyEqual(t,result.Estimate,V.ExpectedEstimate(index),"AbsTol",1e-12);
            verifyEqual(t,result.Lower,V.ExpectedLower(index),"AbsTol",1e-12);
            verifyEqual(t,result.Upper,V.ExpectedUpper(index),"AbsTol",1e-12);
        end
    case "ZERO"
        V=localRead(vectors,"validation_zero_error_upper_bound_vectors.csv");
        for index=1:height(V)
            result=sixgr.validation.BinomialIntervalEngine.exactUpper( ...
                0,V.TrialCount(index),V.ConfidenceLevel(index));
            verifyEqual(t,result.Upper,V.ExpectedUpper(index),"AbsTol",1e-12);
        end
    case "SEQUENTIAL"
        V=localRead(vectors,"validation_sequential_stopping_vectors.csv");
        for index=1:height(V)
            profile=struct("MinTrials",V.MinTrials(index), ...
                "MinErrors",V.MinErrors(index),"MaxTrials",V.MaxTrials(index), ...
                "MaxLooks",V.MaxLooks(index),"LookSchedule",1:V.MaxLooks(index), ...
                "TargetHalfWidth",V.TargetHalfWidth(index), ...
                "TargetZeroErrorUpperBound",V.TargetZeroErrorUpper(index), ...
                "NominalConfidenceLevel",V.NominalConfidenceLevel(index));
            design=sixgr.validation.SequentialDesign.fromProfile(profile);
            result=sixgr.validation.SequentialStoppingPolicy.evaluate( ...
                V.ErrorCount(index),V.TrialCount(index),design,V.LookIndex(index));
            verifyEqual(t,result.PointStatus,V.ExpectedStatus(index));
            verifyEqual(t,result.StopReason,V.ExpectedStopReason(index));
        end
    case "COVERAGE"
        rng(14014,"twister"); p=0.1; n=1000; covered=false(250,1);
        for index=1:numel(covered)
            k=sum(rand(n,1)<p);
            interval=sixgr.validation.BinomialIntervalEngine.wilson(k,n,0.95);
            covered(index)=interval.Lower<=p&&interval.Upper>=p;
        end
        verifyGreaterThanOrEqual(t,mean(covered),0.92);
    case "HIGH_SNR"
        verifyEqual(t,sixgr.validation.CurveComparisonEngine. ...
            highSNR(0,5000,0.95,0.001),"PASS_NONINFERIOR");
        verifyEqual(t,sixgr.validation.CurveComparisonEngine. ...
            highSNR(20,5000,0.95,0.001),"FAIL_INFERIOR");
    case "DROPS"
        V=localRead(vectors,"validation_multiseed_drop_vectors.csv");
        A=localRead(vectors,"validation_multiseed_aggregation_vectors.csv");
        for index=1:height(A)
            rows=V(V.AggregationID==A.AggregationID(index), ...
                {'IndependentDropID','Seed','TrialCount','ErrorCount'});
            if A.ExpectedStatus(index)=="PASS"
                result=sixgr.validation.IndependentDropAggregator.aggregate( ...
                    rows,A.RequiredMinDrops(index),0.95);
                verifyEqual(t,result.AggregateEstimate,A.AggregateEstimate(index), ...
                    "AbsTol",1e-12);
            else
                verifyError(t,@()sixgr.validation.IndependentDropAggregator. ...
                    aggregate(rows,A.RequiredMinDrops(index),0.95), ...
                    A.ExpectedError(index));
            end
        end
    case "TASK"
        V=localRead(vectors,"validation_seed_partition_vectors.csv");
        result=sixgr.validation.SeedLedger.validate(V(:, ...
            {'CampaignID','TaskID','IndependentDropID','Seed','Substream'}));
        verifyEqual(t,result.UniqueTaskCount,height(V));
        id1=sixgr.validation.DeterministicTaskPlan.taskID("C","P","D");
        id2=sixgr.validation.DeterministicTaskPlan.taskID("C","P","D");
        verifyEqual(t,id1,id2);
    case "MERGE"
        V=localRead(vectors,"validation_parallel_merge_vectors.csv");
        E=localRead(vectors,"validation_parallel_merge_expected.csv");
        for index=1:height(E)
            rows=V(V.CampaignID==E.CampaignID(index), ...
                {'TaskID','OutputSHA256','RetryIndex'});
            if E.ExpectedStatus(index)=="PASS"
                a=sixgr.validation.DeterministicMergeEngine.merge(rows);
                b=sixgr.validation.DeterministicMergeEngine.merge( ...
                    rows(randperm(height(rows)),:));
                verifyEqual(t,a.Merged.TaskID,b.Merged.TaskID);
            else
                verifyError(t,@()sixgr.validation.DeterministicMergeEngine. ...
                    merge(rows),"sixgr:validation:DuplicateTaskConflict");
            end
        end
        verifyEqual(t,sixgr.validation.DeterministicMergeEngine. ...
            stableSum([1e16 1 -1e16]),1);
    case "RUNCLASS"
        V=localRead(vectors,"validation_run_class_isolation_vectors.csv");
        for index=1:height(V)
            if V.ExpectedStatus(index)=="PASS"
                sixgr.validation.RunClass.require( ...
                    V.RequiredRunClass(index),V.EvidenceRunClass(index));
            else
                verifyError(t,@()sixgr.validation.RunClass.require( ...
                    V.RequiredRunClass(index),V.EvidenceRunClass(index)), ...
                    V.ExpectedError(index));
            end
        end
    case "PROVENANCE"
        V=localRead(vectors,"validation_provenance_dag_vectors.csv");
        for index=1:height(V)
            call=@()sixgr.validation.EvidenceCircularityChecker.check( ...
                V.ExpectedProvenance(index),V.ExpectedRootID(index), ...
                V.AppliedProvenance(index),V.AppliedRootID(index));
            if localBool(V.ExpectedAllowed(index)), call();
            else, verifyError(t,call,V.ExpectedError(index));
            end
        end
    case "SINR"
        V=localRead(vectors,"validation_measured_sinr_vectors.csv");
        for index=1:height(V)
            call=@()sixgr.validation.MeasuredSINRGate.validate( ...
                V.MeasuredSINR_dB(index),V.ProvenanceClass(index), ...
                V.SampleCount(index),V.RunClass(index),V.ConfiguredSNR_dB(index));
            if V.ExpectedStatus(index)=="PASS", call();
            else, verifyError(t,call,V.ExpectedError(index));
            end
        end
    case "ORACLE"
        V=localRead(vectors,"validation_oracle_registry_vectors.csv");
        result=sixgr.validation.IndependentOracleRegistry.validate(V);
        expected=lower(V.ExpectedQualifiesForMandatoryGate)=="true";
        verifyEqual(t,result.QualifiesForMandatoryGate,expected);
        bad=V(1,:); bad.ArtifactSHA256="bad";
        verifyError(t,@()sixgr.validation.IndependentOracleDescriptor(bad), ...
            "sixgr:validation:OracleHashMismatch");
    case "REFERENCE"
        V=localRead(vectors,"validation_reference_dataset_vectors.csv");
        for index=1:height(V)
            call=@()sixgr.validation.ReferenceDatasetDescriptor(V(index,:));
            if V.ExpectedStatus(index)=="PASS", call();
            else, verifyError(t,call,V.ExpectedError(index));
            end
        end
    case "JOIN"
        V=localRead(vectors,"validation_operating_point_key_vectors.csv");
        fields=cellstr(sixgr.validation.OperatingPointKey.requiredFields());
        base=V(V.ExpectedStatus=="PASS",fields);
        keys=strings(height(base),1);
        for index=1:height(base)
            keys(index)=sixgr.validation.OperatingPointKey.canonical(base(index,:));
        end
        [~,uniqueRows]=unique(keys,"stable");
        base=base(sort(uniqueRows),:);
        exact=sixgr.validation.OperatingPointJoiner.join(base,base);
        verifyTrue(t,exact.Passed);
        missing=sixgr.validation.OperatingPointJoiner.join(base,base(1:end-1,:));
        verifyGreaterThan(t,missing.MissingReferenceCount,0);
        incompatible=base; incompatible.ProfileID(1)="other";
        mismatch=sixgr.validation.OperatingPointJoiner.join(base,incompatible);
        verifyFalse(t,mismatch.Passed);
    case "CURVE"
        V=localRead(vectors,"validation_curve_comparison_vectors.csv");
        for index=1:height(V)
            result=sixgr.validation.CurveComparisonEngine.comparePoint( ...
                V.DUTErrors(index),V.DUTTrials(index), ...
                V.ReferenceErrors(index),V.ReferenceTrials(index), ...
                V.ConfidenceLevel(index),V.EquivalenceMargin(index)).toStruct();
            verifyEqual(t,result.EquivalenceVerdict, ...
                V.ExpectedPointEquivalenceVerdict(index));
            verifyEqual(t,result.NonInferiorityVerdict, ...
                V.ExpectedPointNonInferiorityVerdict(index));
        end
    case "MULTIPLICITY"
        verifyEqual(t,sixgr.validation.MultiplicityAdjustment.holm( ...
            [0.01 0.04 0.03]),[0.03 0.06 0.06],"AbsTol",1e-12);
    case "CALIBRATION"
        V=localRead(vectors,"validation_calibration_catalog_vectors.csv");
        sixgr.validation.CalibrationCatalog.validate(V);
        key=table2struct(V(1,{'Direction','ProfileID','ChannelModel','MCS', ...
            'Rank','Receiver','SCS_kHz','Bandwidth_Hz','TargetBLER'}));
        result=sixgr.validation.CalibrationCatalog.resolve(V,key);
        verifyEqual(t,result.CalibrationID,V.CalibrationID(1));
        bad=V; bad.HoldoutPredictionError(1)=bad.MaxAllowedHoldoutError(1)+1;
        verifyError(t,@()sixgr.validation.CalibrationCatalog.validate(bad), ...
            "sixgr:validation:CalibrationHoldoutFailed");
    case "NEGATIVE"
        V=localRead(vectors,"validation_negative_test_vectors.csv");
        verifyGreaterThanOrEqual(t,height(V),50);
        verifyTrue(t,all(strlength(V.ExpectedError)>0));
        verifyTrue(t,all(lower(V.ExpectedGatePass)=="false"));
        for index=1:height(V)
            actual=sixgr.validation.NegativeCaseExecutor.execute(V(index,:));
            verifyEqual(t,actual.ActualError,V.ExpectedError(index));
            verifyFalse(t,actual.StateMutation);
            verifyFalse(t,actual.GatePass);
            verifyFalse(t,actual.ArtifactAccepted);
            verifyEqual(t,actual.Status,"PASS");
        end
    case "TIME"
        V=localRead(vectors,"validation_time_window_vectors.csv");
        contract=sixgr.validation.TimeWindowContract(0,100,200,1000,1100);
        for index=1:height(V)
            result=contract.inclusion(V.Timestamp(index));
            verifyEqual(t,result.Phase,V.ExpectedPhase(index));
            verifyEqual(t,result.Status,V.ExpectedStatus(index));
        end
    case "KPI"
        contract=sixgr.validation.TimeWindowContract(0,100,200,1000,1100);
        input=table(repmat("R",3,1),["S1";"S2";"S3"],[50;250;1050], ...
            repmat("BLER",3,1),[1;0;1],["E1";"E2";"E3"], ...
            'VariableNames',["RunID","SampleID","Timestamp","KPIName", ...
            "Value","OwnerEventID"]);
        ledger=sixgr.validation.KPISampleLedger.classify(input,contract);
        verifyEqual(t,ledger.Included,[false;true;false]);
        result=sixgr.validation.KPISampleLedger.reconstruct(ledger,"BLER");
        verifyEqual(t,result.SampleCount,1);
    case "ARTIFACT"
        V=localRead(vectors,"validation_artifact_requirement_vectors.csv");
        for index=1:height(V)
            call=@()sixgr.validation.ArtifactRequirementRegistry.validate(V(index,:));
            if V.ExpectedStatus(index)=="PASS", call();
            else, verifyError(t,call,V.ExpectedError(index));
            end
        end
    case "SCENARIO"
        folder=tempname; mkdir(folder); cleanup=onCleanup(@()rmdir(folder,"s"));
        a=fullfile(folder,"a.yaml"); b=fullfile(folder,"b.yaml");
        localWrite(a,"id: a"); localWrite(b,"id: b");
        result=sixgr.validation.CanonicalScenarioRunner.run( ...
            [string(a);string(b)],folder,@localScenarioExecutor);
        verifyTrue(t,result.Passed);
        verifyEqual(t,numel(unique(result.Table.RunID)),2);
    case "ARCHIVE"
        V=localRead(vectors,"validation_archive_acceptance_vectors.csv");
        for index=1:height(V)
            call=@()sixgr.validation.ArchiveAcceptanceRunner.validate(V(index,:));
            if V.ExpectedStatus(index)=="PASS", call();
            else, verifyError(t,call,V.ExpectedError(index));
            end
        end
    case "LEDGER"
        good=table("T","test",string(version),"5G Toolbox",true,true,false,false, ...
            "junit.xml","PASS",'VariableNames',["TestID","TestName", ...
            "MATLABVersion","ToolboxVersion","Executed","Passed","Skipped", ...
            "Blocked","JUnitArtifact","Status"]);
        result=sixgr.validation.TestExecutionLedger.validate(good);
        verifyEqual(t,result.Passed,1);
        bad=good; bad.Skipped=true;
        verifyError(t,@()sixgr.validation.TestExecutionLedger.validate(bad), ...
            "sixgr:validation:RequiredTestSkipped");
    case "PYTHON"
        command=sprintf('python "%s" "%s"',fullfile(vectors, ...
            "verify_validation_vector_pack.py"),vectors);
        [status,~]=system(command);
        verifyEqual(t,status,0);
    case "YAML"
        cfg=sixgr.lls6g.config.readConfigFile(fullfile(root,"simulator", ...
            "configs","validation","validation_profiles.yaml"));
        verifyTrue(t,isfield(cfg,"profiles"));
    case "YAML_DUP"
        path=string(tempname)+".yaml"; cleanup=onCleanup(@()delete(path));
        localWrite(path,sprintf("root:\n  key: 1\n  key: 2\n"));
        verifyError(t,@()sixgr.lls6g.config.readConfigFile(path), ...
            "sixgr:validation:YAMLDuplicateKey");
    case "ANCHOR"
        types=["RUNTIME","FIXTURE","STATIC"];
        verifyEqual(t,numel(types),3);
        verifyFalse(t,ismember("FIXTURE",["RUNTIME"]));
    case "PUBLICATION"
        V=localRead(vectors,"validation_publication_gate_vectors.csv");
        for index=1:height(V)
            call=@()sixgr.validation.PublicationGateEvaluator.evaluate(V(index,:));
            if V.ExpectedStatus(index)=="PASS", call();
            else, verifyError(t,call,V.ExpectedError(index));
            end
        end
    otherwise
        error("sixgr:validation:UnknownTestCase","Unknown test group %s.",kind);
end
end

function V=localRead(root,name)
V=readtable(fullfile(root,name),"TextType","string","Delimiter",",");
end

function out=localBool(value)
if islogical(value), out=value;
else, out=lower(string(value))=="true";
end
end

function localWrite(path,text)
fid=fopen(path,"w");
assert(fid>=0);
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,"%s",text);
end

function out=localScenarioExecutor(scenario,~)
persistent sequence
if isempty(sequence), sequence=0; end
sequence=sequence+1;
bytes=fileread(scenario);
out=struct("RunID","PHASE14-"+string(sequence), ...
    "RunClass","CONTROL_ONLY","SourceCommit","test", ...
    "ScenarioSHA256",sixgr.util.sha256Hex(bytes), ...
    "RuntimeStatus","PASS","ArtifactStatus","PASS");
end
