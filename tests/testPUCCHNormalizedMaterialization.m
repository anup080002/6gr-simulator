function ok=testPUCCHNormalizedMaterialization()
% Actual generated TX samples with declared HARQ vectors; no RF reception,
% no detector qualification, and no fabricated measured pathloss.
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_pucch_baseline_signal_fixture.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
cfg.lls6g.userContext=struct();
assert(cfg.integration.configured_snr_is_link_authority && ...
    strcmpi(cfg.integration.run_mode,'FIXED_SNR_SWEEP') && ...
    cfg.validation.pucch_resources.power_control.require_measured_reference_rs);
ue=struct('UEID',1,'RNTI',cfg.phy.pusch.RNTI,'ServingCell',1,'PUCCHCell',1, ...
    'ComponentCarrier',cfg.phy.frame.DefaultIdentity.ScheduledCCID, ...
    'ActiveULBWP',cfg.phy.frame.DefaultIdentity.ULBWPID);
pri=sixgr.phy.pucch.resolveConfiguredPRI(cfg,ue.UEID,ue.RNTI);
frame=struct('K1',0,'K1Source','configured_detector_test_occasion', ...
    'PDSCHEndSlot',19,'TargetSlot',19,'DecodedPRI',pri.PRIValue, ...
    'PRIFieldWidth',3,'PRIProvenance',pri.Source,'FlexibleResolutionProvided',false);
% Slot 19 overlaps the inherited installed SR calendar. Declare an idle
% UE procedure explicitly; missing state is not equivalent to negative SR.
localReject(@()sixgr.phy.pucch.PUCCHConfigBuilder.planHARQ(cfg,ue,int8([1;0]),frame), ...
    'sixgr:truth:MissingSRProcedureState');
initial=sixgr.truth.initializeConfiguredSRProcedures(cfg,ue);
frame.SchedulingRequestStates=sixgr.phy.pucch.SchedulingRequestState.atSlot(initial,frame.TargetSlot-1);
plan=sixgr.phy.pucch.PUCCHConfigBuilder.planHARQ(cfg,ue,int8([1;0]),frame);
assert(isequal(plan.Report.Data.SchedulingRequestReports.Bits,int8(0)), ...
    'Explicit idle SR state must retain the negative SR indication.');
bound=sixgr.phy.pucch.PUCCHConfigBuilder.materialize(cfg,plan);
state=bound.Assignment.PowerControlState.Data;
assert(state.OperatingPointAuthority=="configured_occupied_re_esn0" && ...
    state.ReferenceEnergyPerOccupiedRE==1 && isnan(state.PathlossdB) && ...
    isnan(state.P0dBm) && ~state.RuntimeMeasuredPathlossUsed);
carrier=sixgr.phy.grid.makeCarrier(sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,19));
tx=sixgr.phy.pucch.PUCCHTransmitter.transmit(carrier,bound.Assignment,bound.Report);
reference=sixgr.phy.waveform.ofdmModulate(carrier,tx.Grid);
assert(isequal(tx.Waveform,reference),'Normalized TX must preserve every original IFFT sample.');
assert(tx.Power.WaveformScale==1 && tx.Power.NormalizedPowerReference && ...
    ~tx.Power.PhysicalPowerApplicable && isnan(tx.Power.AppliedPowerdBm) && ...
    isnan(tx.Power.RequestedPowerdBm) && isnan(tx.Power.MeasuredWaveformPowerdBm) && ...
    tx.Power.NormalizedActiveMeanSquare>0);
[actual,~,e]=sixgr.link.preparePUCCHTransmitWaveform(tx,cfg,'ApplyNodeRF',false);
assert(isequal(actual,reference) && e.NormalizedPowerReference && ...
    ~e.PhysicalPowerApplicable && e.RemovedAbsoluteTransmitScale==1 && ...
    isnan(e.AppliedPower_dBm) && isnan(e.PowerContext.UnappliedPUCCHTarget_dBm));
% Unapplied absolute calibration must not affect the emitted normalized IQ.
changed=cfg;
changed.validation.pucch_resources.power_control.pathloss_db=999;
changed.validation.pucch_resources.power_control.p0_dbm=20;
changed.validation.pucch_resources.power_control.pcmax_dbm=-10;
plan2=sixgr.phy.pucch.PUCCHConfigBuilder.planHARQ(changed,ue,int8([1;0]),frame);
bound2=sixgr.phy.pucch.PUCCHConfigBuilder.materialize(changed,plan2);
tx2=sixgr.phy.pucch.PUCCHTransmitter.transmit(carrier,bound2.Assignment,bound2.Report);
assert(isequal(tx.Waveform,tx2.Waveform) && tx.WaveformSHA256==tx2.WaveformSHA256);
physical=cfg; physical.integration.configured_snr_is_link_authority=false;
localReject(@()sixgr.phy.pucch.PUCCHConfigBuilder.materialize(physical,plan), ...
    'sixgr:phy:pucch:PathlossReferenceSignalMeasurementMissing');
localReject(@()sixgr.link.preparePUCCHTransmitWaveform(tx,physical,'ApplyNodeRF',false), ...
    'sixgr:phy:pucch:PowerOperatingModeMismatch');
bad=state; bad.PathlossdB=0;
localReject(@()sixgr.phy.pucch.PUCCHPowerControlState(bad),'sixgr:phy:pucch:InvalidPowerControlState');
bad=state; bad.ReferenceEnergyPerOccupiedRE=2;
localReject(@()sixgr.phy.pucch.PUCCHPowerControlState(bad),'sixgr:phy:pucch:InvalidPowerControlState');
bad=tx; bad.Power.WaveformScale=2;
localReject(@()sixgr.link.preparePUCCHTransmitWaveform(bad,cfg,'ApplyNodeRF',false), ...
    'sixgr:phy:pucch:InvalidPowerControlState');
ok=true;
disp('PUCCH_NORMALIZED_MATERIALIZATION_PASS: original IFFT, no absolute target/pathloss, physical guards retained; no RX episodes.');
end
function localReject(f,id)
try, f(); catch e, assert(string(e.identifier)==id,e.message); return; end
error('testPUCCHNormalizedMaterialization:MissingRejection','Expected %s.',id);
end
