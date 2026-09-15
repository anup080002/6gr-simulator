function ok=testJointHARQPUSCHTimingPlanning()
% Actual scenario configuration / scheduler allocation fixture. No DCI RX,
% IQ transmission, ACK, or integrated 12-dB success is manufactured here.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml'));
root=tempname(fullfile(pwd,'logs')); mkdir(root);
cfg=sixgr.lls6g.buildInternalConfig(s,root);
cfg.run.rootRunFolder=root;
dlCfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,34,4);
dlCfg.phy.pdsch.symbolAllocation=[2 8]; dlCfg.phy.pdsch.prbSet=6:24;
ulCfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,35,4);
ulCfg.phy.pusch.symbolAllocation=[0 13]; ulCfg.phy.pusch.prbSet=6:24;
dl=sixgr.link.resolveWaveformGrant(dlCfg,'DL',4,'Slot',34,'ControlAbsoluteSlot',33);
% The calibration-only resolveWaveformGrant helper does not attach the
% connected UL precoding field. Materialize an explicit allocation fixture
% through the ordinary scheduler finalizer, without claiming measured SRS.
p=ulCfg.phy.pusch;
ul=struct('Direction','UL','Frame',4,'Slot',35,'ControlAbsoluteSlot',33, ...
    'RNTI',p.RNTI,'UEIndex',1,'ServingCell',1,'BaseStationID',1, ...
    'PRBSet',p.prbSet,'SymbolAllocation',p.symbolAllocation, ...
    'Modulation',p.modulation,'TargetCodeRate',p.codeRate, ...
    'MCSIndex',p.mcsIndex,'MCS',p.mcsIndex,'NumLayers',p.numLayers, ...
    'Layers',p.numLayers,'NumLogicalPorts',p.NumAntennaPorts,'TPMI',p.TPMI, ...
    'RV',0,'HARQProcess',0,'HARQ',struct('HarqID',0,'NDI',true,'RV',0,'IsRetransmission',false), ...
    'Source',"allocation_timing_fixture_not_measured_SRS", ...
    'SRSCausalUsable',true,'SRSValid',true,'RI',p.numLayers, ...
    'SRSCausalMeasurementId',"joint_timing_unit_fixture_not_physical_measurement", ...
    'LastSuccessfulSRSSlot',30);
% Explicit unit-fixture metadata satisfies the codebook grant contract;
% this test does NOT qualify SRS reception, access, or an actual UL attempt.
us=sixgr.l2.mac.SchedulerPF(ulCfg,'Direction','UL');
ul=us.freezePHYGrantForGrant(ul); ul.DCI=us.buildDCIBitfield(ul);
dl.ServingCell=1; ul.ServingCell=1;
assert(dl.K1==1 && ul.K2==1 && dl.TimingDecision.FeedbackAbsoluteSlot==34);
c=sixgr.truth.buildHARQPUSCHTimingConstraints(cfg,dl,ul);
assert(isscalar(c));
[valid,reason]=sixgr.phy.frame.evaluateHARQPUSCHTimingConstraints(dl.TimingDecision.HARQACKDecision,c);
assert(~valid && reason=="insufficient_harq_pusch_n1_multiplexing_time", ...
    'The actual slot-34 to slot-35 pair must fail the earliest-PUSCH processing check.');
probe=dl; probe.HARQACKPUSCHTimingConstraints=c;
rejected=sixgr.phy.frame.TimingRelationEngine.resolveProductionGrant(cfg,probe);
assert(~rejected.Valid && rejected.ReasonCode== ...
    "harq_ack_timing_rejected:insufficient_harq_pusch_n1_multiplexing_time");
probe.K1=NaN;
selected=sixgr.phy.frame.TimingRelationEngine.resolveProductionGrant(cfg,probe);
assert(selected.Valid && selected.K1>1 && ...
    ismember(selected.K1,cfg.phy.frameStructure.TimingContext.Policy.AllowedK1));
assert(isequaln(selected.DataDecision,dl.TimingDecision.DataDecision));
fprintf('JOINT_TIMING_CANONICAL_SELECTION old_K1=%d selected_K1=%d unchanged_data=1\n',dl.K1,selected.K1);
% Exercise the same joint planner used before runtime control enqueue.
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,root,multi,struct(),58);
state.CurrentSlot=1; state.CurrentFrame=1; state.CurrentCanonicalSlot=1;
state.CurrentServingIdx(:)=1;
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
% Future metadata planning is not physical advancement or a transmission.
state.CurrentSlot=34; state.CurrentFrame=4; state.CurrentCanonicalSlot=34;
[state,plannedDL,plannedUL]=sixgr.truth.planJointHARQPUSCHTiming(state,{cfg},dl,ul);
assert(isscalar(plannedDL) && isequaln(plannedUL,ul) && plannedDL.K1==selected.K1);
assert(plannedDL.TBSBits==dl.TBSBits && isequaln(plannedDL.PRBSet,dl.PRBSet) && ...
    isequaln(plannedDL.SymbolAllocation,dl.SymbolAllocation));
assert(~isequaln(plannedDL.DCI.Bits,dl.DCI.Bits), ...
    'The newly selected K1 must be encoded in the untransmitted DCI.');
sixgr.phy.grant.assertGrantTimingIdentity(plannedDL,'DL');
assert(isempty(owner.readTransmittedSchedulingControls()) && isempty(owner.DataTransmissions) && owner.Events.NextSampleIndex==0);
assert(state.ControlTrials.JointHARQPUSCHTimingDecisions.DecisionStage=="before_current_DL_and_UL_DCI_enqueue");
% Exact-budget and one-Tc-early checks are explicit arithmetic fixtures.
f=dl.TimingDecision.HARQACKDecision;
ready=max(c.PDSCHEndTick+c.PDSCHProcessingTicks,c.PDCCHEndTick+c.PDCCHProcessingTicks);
c.ULTargetTick=ready; c.ULTargetEndTick=ready+int64(100);
c.ULWaveformPlacementTick=ready;
f.TargetTick=ready; f.TargetEndTick=ready+int64(100); f.WaveformPlacementTick=ready;
assert(sixgr.phy.frame.evaluateHARQPUSCHTimingConstraints(f,c));
c.ULWaveformPlacementTick=ready-int64(1);
assert(~sixgr.phy.frame.evaluateHARQPUSCHTimingConstraints(f,c));
c.ULWaveformPlacementTick=ready;
% Transitive overlap must use the earliest start for the WHOLE group.
c2=c; c2.ULTargetTick=ready+int64(90); c2.ULTargetEndTick=ready+int64(200);
c2.ULWaveformPlacementTick=c2.ULTargetTick;
c2.PDCCHEndTick=ready-c2.PDCCHProcessingTicks+int64(1);
c2.ULGrantContextID="second_timing_fixture";
f.TargetEndTick=ready+int64(50);
assert(~sixgr.phy.frame.evaluateHARQPUSCHTimingConstraints(f,[c c2]));
c.PDSCHEndTick=c.PDSCHEndTick+int64(1);
try
    sixgr.phy.frame.evaluateHARQPUSCHTimingConstraints(f,c);
    error('test:ExpectedRejection','Stale PDSCH timing evidence must be rejected.');
catch cause
    assert(strcmp(cause.identifier,'sixgr:phy:frame:InvalidHARQPUSCHTimingConstraint'));
end
fprintf('JOINT_HARQ_PUSCH_TIMING_PLANNING_PASS old_K1=%d selected_K1=%d TB_bits=%d\n',dl.K1,plannedDL.K1,plannedDL.TBSBits);
ok=true;
end
