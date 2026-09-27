function ok = testH4BeamManagementRuntimeBinding()
%TESTH4BEAMMANAGEMENTRUNTIMEBINDING Verify measured P1/P2 and decoded TCI authority.

setup6GRSimToolkit("Verbose", false);
scfg = sixgr.lls6g.config.loadScenarioConfig( ...
    "simulator/configs/scenarios/h4_100_beam_refinement_tci.yaml");
cfg = sixgr.lls6g.buildInternalConfig(scfg, ...
    fullfile(tempdir, "h4_beam_runtime_binding"));

state = struct();
state.CfgMobility = cfg;
state.CurrentSlot = 1;
state.CurrentSNR_dB = 20;
state.SweepPointIndex = 1;
state.BeamManagementRuntimeEnabled = true;
state.BeamManagementMachines = {sixgr.phy.beam.BeamManagementStateMachine("IDLE")};
state.BeamManagementStateTraceTable = table();
state.PendingBeamCRIByUE = NaN;
state.PendingTCIStateIDByUE = NaN;
state.PendingTCICodepointByUE = NaN;
state.PendingBeamSourceByUE = "";
state.ActiveTCIStateIDByUE = NaN;
state.ActiveTCICodepointByUE = NaN;
state.AppliedDataBeamCRIByUE = NaN;

state = sixgr.truth.CoupledTruthRuntime.stageMeasuredSSBBeamRuntime( ...
    state, 1, 0, -82, "unit_test_received_PBCH");
assert(state.BeamManagementMachines{1}.State == "TCI_PENDING");
assert(state.PendingBeamCRIByUE(1) == 0 && ...
    state.PendingTCIStateIDByUE(1) == 16 && ...
    state.PendingTCICodepointByUE(1) == 0);

wrong = table(1, 'VariableNames', {'DecodedDCITCICodepoint'});
[unchanged, accepted] = sixgr.truth.CoupledTruthRuntime. ...
    applyDecodedTCIBeamRuntime(state, 1, wrong);
assert(~accepted && unchanged.BeamManagementMachines{1}.State == "TCI_PENDING", ...
    "A mismatched decoded TCI codepoint must not activate the beam.");

coarse = table(0, 'VariableNames', {'DecodedDCITCICodepoint'});
[state, accepted] = sixgr.truth.CoupledTruthRuntime. ...
    applyDecodedTCIBeamRuntime(state, 1, coarse);
assert(accepted && state.BeamManagementMachines{1}.State == "P2_REFINING", ...
    "The decoded SSB-seeded state must enter P2 refinement.");

report = struct("Direction","DL", "UEIndex",1, "CRI",3, ...
    "CSIUCIDecodeOk",true, "SourceSignal","received_CSI_UCI", ...
    "ReportIdentity","H4-CSI-REPORT-3");
state = sixgr.truth.CoupledTruthRuntime.stageReceivedCSIBeamRuntime(state, report);
assert(state.BeamManagementMachines{1}.State == "TCI_PENDING" && ...
    state.PendingBeamCRIByUE(1) == 3 && ...
    state.PendingTCIStateIDByUE(1) == 19 && ...
    state.PendingTCICodepointByUE(1) == 3);

refined = table(3, 'VariableNames', {'DecodedDCITCICodepoint'});
[state, accepted] = sixgr.truth.CoupledTruthRuntime. ...
    applyDecodedTCIBeamRuntime(state, 1, refined);
assert(accepted && state.BeamManagementMachines{1}.State == "DATA_ACTIVE");
assert(state.AppliedDataBeamCRIByUE(1) == 3 && ...
    state.ActiveTCIStateIDByUE(1) == 19 && ...
    state.ActiveTCICodepointByUE(1) == 3);
assert(height(state.BeamManagementStateTraceTable) == 8 && ...
    all(~state.BeamManagementStateTraceTable.GeometryOracleUsed), ...
    "The trace must contain causal state transitions without a geometry oracle.");

ok = true;
end
