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

state = sixgr.truth.CoupledTruthRuntime.refreshControlState(state);

assert(all(logical(state.ControlEligibility)), ...
    "PBCH/PRACH/TRS-complete UEs must be control eligible.");
assert(all(logical(state.SchedulingEligibility)), ...
    "Access-complete UEs with fresh SRS must be scheduler eligible.");
end
