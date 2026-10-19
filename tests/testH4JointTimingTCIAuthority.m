function ok=testH4JointTimingTCIAuthority()
% Full-band H4 scheduling regression, not RF/BLER qualification. Exercise
% the slot-46/47 path that previously replaced received beam state 18/2
% with cell-template state 17/0 when the first UL grant was planned.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_adaptation.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
assert(cfg.phy.carrier.NSizeGrid==273);
scheduler=sixgr.l2.mac.SchedulerPF(cfg,'Direction','DL');
state=struct('SharedWaveformStream',sixgr.truth.CoupledWaveformStream(), ...
    'DLSchedulers',{{scheduler}},'ControlTrials',struct());
ul=localULFixture(cfg);
for slot=[46 47]
    active=cfg;
    active.phy.beamManagement.selectedCRI=2;
    active.phy.csi.selectedCRI=2;
    active.phy.pdsch.qclTCI.state_id=18;
    active.phy.pdsch.qclTCI.codepoint=2;
    active.phy.pdsch.qclTCI.activation_absolute_slot0=slot-1;
    active.phy.pdsch.qclTCI.spatial_source_resource_id=2;
    active.phy.pdsch.qclTCI.spatial_source_reference_signal='NZP-CSI-RS';
    active.phy.pdsch.qclTCI.initialization_source='declared_TCI_regression_fixture';
    active.phy.pdsch.activeTCIStateID=18;
    active.phy.pdsch.PMI=NaN;
    active.phy.pdsch.pmi=NaN;
    active.phy.pdsch.prbSet=0:272;
    active.phy.pdsch.symbolAllocation=[2 12];
    active=sixgr.phy.grid.applyRuntimeCarrierTimeline(active,slot);
    dl=sixgr.link.resolveWaveformGrant(active,'DL',3, ...
        'Slot',slot,'ControlAbsoluteSlot',slot-1);
    dl.ServingCell=1;
    dl.PMI=NaN; % Exact retained bootstrap: no delivered CSI-selected PMI.
    before=sixgr.phy.pdcch.decodeDCIPayload(dl.DCI.Bits,dl.DCI.Format,dl.DCI.ContextData);
    assert(before.Fields.transmission_configuration_indication==2);
    assert(dl.PHYGrant.ConfigurationAuthority.DLQCLTCIBinding.TCICodepoint==2);
    assert(~isempty(sixgr.truth.buildHARQPUSCHTimingConstraints(cfg,dl,ul)));
    [after,planned,keptUL]=sixgr.truth.planJointHARQPUSCHTiming(state,{cfg},dl,ul);
    assert(isscalar(planned) && isequaln(keptUL,ul));
    decoded=sixgr.phy.pdcch.decodeDCIPayload( ...
        planned.DCI.Bits,planned.DCI.Format,planned.DCI.ContextData);
    assert(decoded.Fields.transmission_configuration_indication==2, ...
        'test:H4JointTimingLostTCI', ...
        'Joint timing changed the per-UE TCI codepoint from 2 to %g.', ...
        decoded.Fields.transmission_configuration_indication);
    assert(planned.DCI.ContextData.ActiveTCIStateID==18);
    assert(isequaln(planned.PHYGrant.ConfigurationAuthority.DLQCLTCIBinding, ...
        dl.PHYGrant.ConfigurationAuthority.DLQCLTCIBinding));
    assert(isequaln(planned.PHYGrant.PrecodingState.MatrixPhysicalPorts, ...
        dl.PHYGrant.PrecodingState.MatrixPhysicalPorts));
    assert(isequaln(planned.PHYGrant.AntennaArchitecture,dl.PHYGrant.AntennaArchitecture));
    assert(isequaln(planned.PHYGrant.CodingLayout,dl.PHYGrant.CodingLayout));
    assert(isequaln(planned.PHYGrant.ResourceAllocation,dl.PHYGrant.ResourceAllocation));
    assert(isequaln(planned.HARQ,dl.HARQ));
    sixgr.phy.grant.assertGrantTimingIdentity(planned,'DL');
    assert(height(after.ControlTrials.JointHARQPUSCHTimingDecisions)==1);
    assert(isempty(state.SharedWaveformStream.readTransmittedSchedulingControls()));
    fprintf('H4_JOINT_TCI slot=%d PRB=273 codepoint=2 K1_before=%d K1_after=%d RF_executions=0\n', ...
        slot,dl.K1,planned.K1);
end
ok=true;
end

function ul=localULFixture(cfg)
% Only an allocation fixture is needed to activate the joint planner. No
% synthetic SRS, UL reception, or accepted performance row is published.
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,50);
cfg.phy.pusch.prbSet=8:272;
cfg.phy.pusch.symbolAllocation=[0 11];
p=cfg.phy.pusch;
ul=struct('Direction','UL','Frame',3,'Slot',50,'ControlAbsoluteSlot',45, ...
    'RNTI',p.RNTI,'UEIndex',1,'ServingCell',1,'BaseStationID',1, ...
    'PRBSet',p.prbSet,'SymbolAllocation',p.symbolAllocation, ...
    'Modulation',p.modulation,'TargetCodeRate',p.codeRate, ...
    'MCSIndex',p.mcsIndex,'MCS',p.mcsIndex,'NumLayers',p.numLayers, ...
    'Layers',p.numLayers,'NumLogicalPorts',p.NumAntennaPorts,'TPMI',p.TPMI, ...
    'RV',0,'HARQProcess',0, ...
    'HARQ',struct('HarqID',0,'NDI',true,'RV',0,'IsRetransmission',false), ...
    'Source',"joint_timing_allocation_fixture_not_physical_SRS", ...
    'SRSCausalUsable',true,'SRSValid',true,'RI',p.numLayers, ...
    'SRSCausalMeasurementId',"H4_joint_timing_fixture_not_measurement", ...
    'LastSuccessfulSRSSlot',45);
scheduler=sixgr.l2.mac.SchedulerPF(cfg,'Direction','UL');
ul=scheduler.freezePHYGrantForGrant(ul);
ul.DCI=scheduler.buildDCIBitfield(ul);
end
