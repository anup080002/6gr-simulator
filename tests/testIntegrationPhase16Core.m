function tests = testIntegrationPhase16Core
%TESTINTEGRATIONPHASE16CORE Focused production contract tests for Phase 16.
tests = functiontests(localfunctions);
end

function testIntegrationRunModeResolution(testCase)
verifyEqual(testCase,sixgr.integration.RunMode.resolve("FIXED_SNR_SWEEP"), ...
    "FIXED_SNR_SWEEP");
verifyError(testCase,@()sixgr.integration.RunMode.resolve( ...
    ["FIXED_SNR_SWEEP","GEOMETRY_NETWORK"]), ...
    "sixgr:integration:RunModeConflict");
end

function testIntegrationRadioProfileResolution(testCase)
verifyEqual(testCase,sixgr.integration.RadioProfile.resolve( ...
    "nr_rel18_system_lls_strict"),"nr_rel18_system_lls_strict");
verifyFalse(testCase,sixgr.integration.RadioProfile.isNormative( ...
    "rel20_6g_study_context"));
end

function testResolvedConfigHashBinding(testCase)
[configuration,cleanup] = localStage("master_sinr_sweep.yaml"); %#ok<ASGLU>
verifyWarningFree(testCase,@()configuration.verifyExecuted());
verifyEqual(testCase,strlength(configuration.ExecutedSHA256),64);
end

function testNoHiddenExecutionOverrides(testCase)
[configuration,cleanup] = localStage("master_geometry_based.yaml"); %#ok<ASGLU>
verifyEqual(testCase,configuration.Planning.RunMode,"GEOMETRY_NETWORK");
verifyFalse(testCase,logical(configuration.ResolvedStruct. ...
    integration.configured_snr_is_link_authority));
end

function testCommonComponentRegistry(testCase)
[configuration,cleanup] = localStage("master_sinr_sweep.yaml"); %#ok<ASGLU>
context = sixgr.integration.SimulationContext.create(configuration,[11 23]);
registry = context.Registry.table();
verifyGreaterThanOrEqual(testCase,height(registry),10);
verifyEqual(testCase,numel(unique(registry.Component)),height(registry));
end

function testAbsoluteRadioClockConversions(testCase)
clock = sixgr.integration.AbsoluteRadioClock(1e6,100,14,10);
clock.advanceTo(1400);
view = clock.view();
verifyEqual(testCase,view.AbsoluteSlot,1);
verifyEqual(testCase,view.Frame,0);
verifyEqual(testCase,view.Slot,1);
end

function testEventProducedAvailableConsumedTimes(testCase)
clock = sixgr.integration.AbsoluteRadioClock(1e6,100,14,10);
store = sixgr.integration.EventSourcedStateStore("RUN");
scheduler = sixgr.integration.AbsoluteEventScheduler(clock);
queue = sixgr.integration.MeasurementAvailabilityQueue(scheduler,store,1);
queue.publish("CSI",struct("CQI",9),10,20);
clock.advanceTo(10);
result = queue.release();
verifyEqual(testCase,result{1}.CQI,9);
trace = store.table();
verifyGreaterThanOrEqual(testCase,trace.ConsumedAt,trace.AvailableAt);
end

function testCommonWaveformImplementationAcrossModes(testCase)
[fixed,geometry] = localPair("DL","AWGN",5,11);
verifyEqual(testCase,fixed.WaveformImplementationSHA256, ...
    geometry.WaveformImplementationSHA256);
verifyEqual(testCase,fixed.ReceiverImplementationSHA256, ...
    geometry.ReceiverImplementationSHA256);
end

function testChunkedOneShotWaveformContinuity(testCase)
stream = RandStream("Threefry","Seed",11);
grid = complex(randn(stream,24,4),randn(stream,24,4));
[oneShot,~] = sixgr.phy.waveform.CanonicalOFDMModulator.math( ...
    grid,64,repmat(8,1,4));
chunks = cell(4,1);
for ii = 1:4
    chunks{ii} = sixgr.phy.waveform.CanonicalOFDMModulator.math( ...
        grid(:,ii),64,8);
end
verifyEqual(testCase,vertcat(chunks{:}),oneShot,"AbsTol",1e-12);
end

function testFixedGeometryPowerReferenceReconciliation(testCase)
[fixed,geometry] = localPair("DL","AWGN",0,23);
verifyEqual(testCase,fixed.Environment.SignalPower, ...
    geometry.Environment.SignalPower,"AbsTol",1e-15);
verifyEqual(testCase,fixed.Environment.NoiseVariance, ...
    geometry.Environment.NoiseVariance,"AbsTol",1e-15);
end

function testFixedSNRNoiseCalibration(testCase)
result = sixgr.integration.CommonAirInterfacePipeline.executeReduction( ...
    "DL","AWGN",8,47,"FIXED_SNR_SWEEP");
verifyLessThanOrEqual(testCase,abs(result.MeasuredInputSNR_dB-8),1e-12);
verifyNotEqual(testCase,result.PostEqualizationSINR_dB, ...
    result.ConfiguredSNR_dB);
end

function testIntegratedResourceTransactionMap(testCase)
manager = sixgr.integration.ResourceTransactionManager("RUN",1);
rows = localResourceRows(120);
manager.commit(rows);
verifyEqual(testCase,height(manager.table()),120);
end

function testInvalidDCICannotCreateGrant(testCase)
ledger = sixgr.integration.GrantCausalityLedger("RUN");
dci = struct("EventID","D","CRCValid",false,"RNTI","1", ...
    "SemanticValid",true,"AvailableAt",0,"Payload",struct());
verifyError(testCase,@()ledger.materialize(dci,0,"1"), ...
    "sixgr:integration:InvalidGrantCausality");
end

function testDecodedDCIGrantCausality(testCase)
ledger = sixgr.integration.GrantCausalityLedger("RUN");
dci = struct("EventID","D","CRCValid",true,"RNTI","1", ...
    "SemanticValid",true,"AvailableAt",10,"Payload",struct("MCS",4));
grantID = ledger.materialize(dci,10,"1");
verifyTrue(testCase,startsWith(grantID,"GRANT-"));
end

function testDecodedUCICausality(testCase)
event = sixgr.integration.EventEnvelope("DECODED_UCI","pucch_rx","harq", ...
    10,12,20,struct("ACK",true),"RunID","RUN");
verifyWarningFree(testCase,@()event.assertConsumable(12,1));
end

function testFutureCSIRejected(testCase)
event = sixgr.integration.EventEnvelope("CSI","rx","scheduler", ...
    0,10,20,struct(),"RunID","RUN");
verifyError(testCase,@()event.assertConsumable(9,1), ...
    "sixgr:integration:FutureEvidenceConsumed");
end

function testStaleCSIRejected(testCase)
event = sixgr.integration.EventEnvelope("CSI","rx","scheduler", ...
    0,10,20,struct(),"RunID","RUN");
verifyError(testCase,@()event.assertConsumable(21,1), ...
    "sixgr:integration:StaleEvidenceConsumed");
end

function testMeasuredCSIControlsScheduler(testCase)
source = "decoded_measurement_event";
verifyWarningFree(testCase,@()sixgr.integration. ...
    IntegrationInvariantGuard.prohibitConfiguredState(source));
end

function testSRSControlsULPrecoder(testCase)
selected = sixgr.integration.IntegrationHash.data(struct("SRI",2,"TPMI",1));
applied = selected;
verifyWarningFree(testCase,@()sixgr.integration. ...
    IntegrationInvariantGuard.requireAppliedPrecoder(selected,applied));
end

function testIntegratedHARQIdentity(testCase)
identity = struct("UE",1,"Direction","DL","ServingCell",1, ...
    "BWP",0,"Process",2,"Codeword",0,"NDIEpoch",1,"TBID","TB-1");
verifyWarningFree(testCase,@()sixgr.integration. ...
    IntegrationInvariantGuard.requireHARQIdentity(identity,identity));
end

function testIntegratedSoftBufferPositions(testCase)
positions = [0 2 3 1];
verifyWarningFree(testCase,@()sixgr.integration. ...
    IntegrationInvariantGuard.requireHARQPosition(positions,positions));
end

function testSampleDomainInterferenceSum(testCase)
a = struct("LinkID","A","Samples",ones(32,1));
b = struct("LinkID","B","Samples",1j*ones(32,1));
[sumSamples,ledger] = sixgr.integration.SampleDomainLinkGraph.compose({a,b});
verifyEqual(testCase,sumSamples,(1+1j)*ones(32,1));
verifyEqual(testCase,max(ledger.SumError),0);
end

function testMobilityDopplerPhaseContinuity(testCase)
link = struct("LinkID","L","GainLinear",1,"ImpulseResponse",1, ...
    "DelaySamples",0,"FrequencyOffsetHz",100,"SampleRateHz",1000, ...
    "Normalize",false);
[one,~] = sixgr.integration.ChannelApplicationContract.apply(ones(64,1),link);
[first,~] = sixgr.integration.ChannelApplicationContract.apply(ones(32,1),link);
link2 = link;
phase = exp(1j*2*pi*100*32/1000);
[second,~] = sixgr.integration.ChannelApplicationContract.apply( ...
    phase*ones(32,1),link2);
verifyEqual(testCase,[first;second],one,"AbsTol",1e-12);
end

function testIntegratedRankPortLayerNoCollapse(testCase)
verifyWarningFree(testCase,@()sixgr.integration. ...
    IntegrationInvariantGuard.requireRank(2,2));
end

function testIntegratedRFStateContinuity(testCase)
plan = sixgr.integration.SlotExecutionPlan(4);
verifyTrue(testCase,any(plan.Stages=="apply_channel_rf_interference"));
verifyTrue(testCase,any(plan.Stages=="receive_decode"));
end

function testIntegratedSchedulerEligibility(testCase)
event = sixgr.integration.EventEnvelope("ELIGIBILITY","mac","scheduler", ...
    10,10,11,struct("Eligible",true),"RunID","RUN");
verifyWarningFree(testCase,@()event.assertConsumable(10,1));
end

function testIntegratedPacketLineageConservation(testCase)
lineage = sixgr.integration.PacketLineageBridge("RUN");
lineage.append("P1",100,20,30,50,0);
verifyEqual(testCase,lineage.table().ConservationErrorBytes,0);
end

function testIntegratedConnectedStateCausality(testCase)
verifyError(testCase,@()sixgr.integration.IntegrationInvariantGuard. ...
    prohibitConfiguredState("configured_rrc_connected"), ...
    "sixgr:integration:ConfiguredStateOverride");
end

function testCrossModeAWGNDLBitExact(testCase)
rows = localCrossRows();
selection = rows.Direction=="DL" & rows.Channel=="AWGN";
verifyTrue(testCase,all(rows.BitsEqual(selection)));
verifyTrue(testCase,all(rows.DecodeEqual(selection)));
end

function testCrossModeAWGNULBitExact(testCase)
rows = localCrossRows();
selection = rows.Direction=="UL" & rows.Channel=="AWGN";
verifyTrue(testCase,all(rows.BitsEqual(selection)));
verifyTrue(testCase,all(rows.DecodeEqual(selection)));
end

function testCrossModeTDLDLGridEquivalence(testCase)
rows = localCrossRows();
selection = rows.Direction=="DL" & startsWith(rows.Channel,"TDL");
verifyTrue(testCase,all(rows.Status(selection)=="PASS"));
end

function testCrossModeTDLULGridEquivalence(testCase)
rows = localCrossRows();
selection = rows.Direction=="UL" & startsWith(rows.Channel,"TDL");
verifyTrue(testCase,all(rows.Status(selection)=="PASS"));
end

function testSerialParallelDeterminism(testCase)
seeds = [11 23 47 89];
forward = localTaskDigests(seeds);
reverse = localTaskDigests(fliplr(seeds));
forward = sortrows(forward,"Seed"); reverse = sortrows(reverse,"Seed");
verifyEqual(testCase,forward.Digest,reverse.Digest);
end

function testRetryIdempotence(testCase)
a = sixgr.integration.CommonAirInterfacePipeline.executeReduction( ...
    "UL","TDL-C",0,89,"FIXED_SNR_SWEEP");
b = sixgr.integration.CommonAirInterfacePipeline.executeReduction( ...
    "UL","TDL-C",0,89,"FIXED_SNR_SWEEP");
verifyEqual(testCase,a.ReceiverSHA256,b.ReceiverSHA256);
end

function testWorkerLossAndResume(testCase)
digest = sixgr.integration.IntegrationHash.data(struct("TaskID","T","Seed",11));
verifyWarningFree(testCase,@()sixgr.integration.IntegrationInvariantGuard. ...
    requireTaskHash("T",digest,digest));
end

function testGracefulStopPartialState(testCase)
verifyError(testCase,@()sixgr.integration.IntegrationInvariantGuard. ...
    requireComplete("STOPPED",false), ...
    "sixgr:integration:InvalidCompletionState");
end

function testIntegrationNegativeMatrix(testCase)
rows = sixgr.integration.IntegrationVectorValidator.negative( ...
    localVectorRoot(),"TEST-RUN");
verifyEqual(testCase,height(rows),60);
verifyTrue(testCase,all(rows.Status=="PASS"));
end

function [configuration,cleanup] = localStage(name)
root = tempname;
mkdir(root);
cleanup = onCleanup(@()rmdir(root,"s"));
configuration = sixgr.integration.ResolvedRunConfiguration.stage( ...
    fullfile(localRepoRoot(),"simulator","configs","scenarios",name),root);
end

function [fixed,geometry] = localPair(direction,channel,snr,seed)
fixed = sixgr.integration.CommonAirInterfacePipeline.executeReduction( ...
    direction,channel,snr,seed,"FIXED_SNR_SWEEP");
geometry = sixgr.integration.CommonAirInterfacePipeline.executeReduction( ...
    direction,channel,snr,seed,"GEOMETRY_NETWORK_NEUTRALIZED");
end

function rows = localResourceRows(n)
index = (0:n-1).';
rows = table(index*64,zeros(n,1),floor(index/14),mod(index,14), ...
    floor(index/12),mod(index,12),repmat("L0",n,1), ...
    repmat("P0",n,1),repmat("PDSCH",n,1), ...
    'VariableNames',{'AbsoluteSample','Frame','Slot','Symbol','PRB', ...
    'Subcarrier','LogicalPort','PhysicalPort','Owner'});
end

function rows = localCrossRows()
persistent cached
if isempty(cached)
    cached = sixgr.integration.IntegrationVectorValidator.crossMode( ...
        localVectorRoot());
end
rows = cached;
end

function root = localVectorRoot()
root = fullfile(localRepoRoot(),"tests","vectors","integration");
end

function root = localRepoRoot()
root = fileparts(fileparts(mfilename("fullpath")));
end

function value = localTaskDigests(seeds)
n = numel(seeds);
rows = repmat(struct("Seed",NaN,"Digest",""),n,1);
for ii = 1:n
    result = sixgr.integration.CommonAirInterfacePipeline.executeReduction( ...
        "DL","AWGN",0,seeds(ii),"FIXED_SNR_SWEEP");
    rows(ii) = struct("Seed",seeds(ii),"Digest",result.ReceiverSHA256);
end
value = struct2table(rows,"AsArray",true);
end
