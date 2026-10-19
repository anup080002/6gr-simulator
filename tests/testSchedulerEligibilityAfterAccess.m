function testSchedulerEligibilityAfterAccess
%TESTSCHEDULERELIGIBILITYAFTERACCESS Access+fresh SRS/TRS must unblock grants.

nUsers = 2;
nCells = 2;
state = struct();
state.NumUsers = nUsers;
state.CurrentSlot = 12;
state.CurrentFrame = 1;
state.CurrentDirection = "DL";
state.CurrentServingIdx = [1; 2];
state.CfgMobility = struct();
state.LargeScaleState = struct();
state.Bandwidth_Hz = 100e6;
state.NoiseFigure_dB = 7;
state.ControlGating = struct("PBCHRequired", true, "PRACHRequired", true, ...
    "PDCCHRequired", true, "SRSRequired", true, "TRSRequired", true, ...
    "SRSMaxAgeSlots", 20, "TRSMaxAgeSlots", 20);
state.CellAcquisitionState = repmat("acquired", nUsers, 1);
state.AccessState = repmat("succeeded", nUsers, 1);
state.SRSValidityState = repmat("valid", nUsers, 1);
state.CSIValidityState = repmat("valid", nUsers, 1);
state.LastSuccessfulSRSSlotByUE = repmat(10, nUsers, 1);
state.SRSInvalidEventCount = zeros(nUsers, 1);
state.TRSValidityStateByCell = repmat("valid", nCells, 1);
state.TrackingEligibilityByCell = true(nCells, 1);
state.LastSuccessfulTRSSlotByCell = repmat(10, nCells, 1);
state.LastTRSObservedSlotByCell = repmat(10, nCells, 1);
state.LastEstimatedTRSDopplerHzByCell=nan(nCells,1);
state.TRSFailureCountByCell=zeros(nCells,1);
state.ReceiverTrackingStateByCell=repmat(struct(),nCells,1);
% Explicit independent receiver-owned fixture state, not shared estimates.
state=sixgr.truth.TRSReceiverState.initialize(state);

state = sixgr.truth.CoupledTruthRuntime.refreshControlState(state);

assert(all(logical(state.ControlEligibility)), ...
    "PBCH/PRACH/TRS-complete UEs must be control eligible.");
assert(all(logical(state.SchedulingEligibility)), ...
    "Access-complete UEs with fresh SRS must be scheduler eligible.");

% Production publication must expose the effective UL codebook prerequisite
% even when the common SRS admission option is off. Declared scheduler
% fixtures below are not waveform measurements or statistical evidence.
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_pdcch_shared_queue_fixture.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
cfg.phy.pusch.transmissionScheme='codebook';
cfg.validation.strictWaveformTruthRequired=true;
cfg.phy.pdsch.qclTCI.enabled=false;
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),10);
state.CurrentSlot=5; state.CurrentFrame=1; state.CurrentDirection="DL";
state.ControlGating.SRSRequired=false; state.ControlGating.SRSMaxAgeSlots=2;
state.SchedulingEligibility=true; state.ControlEligibility=true;
state.SRSValidityState="not_required"; state.ReferenceSignalMeasurementTable=table();
artifacts=sixgr.truth.CoupledTruthRuntime.mobilityArtifacts(state);
row=artifacts.ControlGatingStateTable;
assert(row.DLSchedulingEligibility && ~row.ULSchedulingEligibility && ...
    ~row.DLSRSRequired && row.ULSRSRequired && ~row.ULSRSCausalUsable && ...
    startsWith(string(row.ULSchedulingBlockReason),"srs_") && ...
    strlength(string(row.DLSchedulingBlockReason))==0);
for mode=["fresh","stale","future"]
    producer=4; available=4;
    if mode=="stale", producer=1; available=1; end
    if mode=="future", available=6; end
    state.SRSValidityState="valid";
    state.ReferenceSignalMeasurementTable=table("SRS","UE",1,producer,available,true,"fixture", ...
        'VariableNames',{'SignalType','TargetType','TargetId','ProducerSlot', ...
        'AvailableSlot','Valid','MeasurementId'});
    artifacts=sixgr.truth.CoupledTruthRuntime.mobilityArtifacts(state);
    row=artifacts.ControlGatingStateTable;
    assert(row.DLSchedulingEligibility && row.ULSRSRequired && ...
        row.ULSchedulingEligibility==(mode=="fresh") && ...
        row.ULSRSCausalUsable==(mode=="fresh"));
    if mode=="fresh"
        assert(strlength(string(row.ULSchedulingBlockReason))==0);
    else
        assert(contains(string(row.ULSchedulingBlockReason),mode));
    end
end
end
