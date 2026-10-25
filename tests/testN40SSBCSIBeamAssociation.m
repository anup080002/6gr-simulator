function ok=testN40SSBCSIBeamAssociation()
% Config/matrix and declared callback fixtures, not physical UCI reception.
% Check every 4x8 handoff and noncontiguous actual SSB identities.
setup6GRSimToolkit('Verbose',false);
paths=["simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_reference_snr_sweep.yaml", ...
    "simulator/configs/scenarios/h4_100_beam_refinement_tci.yaml"];
for path=paths
    s=sixgr.lls6g.config.loadScenarioConfig(path);
    cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
    checkAll(cfg);
    original=s.toStruct();
    broken=original;
    broken.mimo_and_beam_management.ssb_to_initial_csi_resource_ids=[0 2 4 6];
    reject(@()sixgr.lls6g.buildInternalConfig(broken,tempname), ...
        'sixgr:lls6g:config:SSBInitialCSISpatialMismatch');
    % Arbitrary associations remain possible only when explicitly authored;
    % this is not a normative restriction on all NR SSB/CSI designs.
    broken.mimo_and_beam_management.ssb_initial_csi_spatial_policy='explicit_association';
    sixgr.lls6g.buildInternalConfig(broken,tempname);
    sparse=original;
    sparse.initial_access.ssb.positions_in_burst='10101010';
    sparse.mimo_and_beam_management.ssb_to_initial_csi_resource_ids=[0 2 4 6];
    sparseCfg=sixgr.lls6g.buildInternalConfig(sparse,tempname);
    assert(isequal(sparseCfg.phy.beamManagement.activeSSBIndices0Based,[0 2 4 6]));
    checkAll(sparseCfg);
end
ok=true;
fprintf('PASS SSB4_to_CSI8: actual matrix containment, sparse bitmap identities, all declared state/TCI handoffs; physical UCI not claimed.\n');
end

function checkAll(cfg)
active=cfg.phy.beamManagement.activeSSBIndices0Based;
map=cfg.phy.beamManagement.ssbToInitialCSIResourceIDs;
assert(numel(active)==4 && cfg.phy.csirs.numResources==8);
for k=1:numel(active)
    [~,initialCRI]=sixgr.phy.refsig.resolveCSIResourceIdentity(cfg,map(k),'resource_id');
    emitted=sixgr.phy.ia.SSBBurstPlan.selectedPrecoderFromConfig(cfg,active(k));
    w=emitted.MatrixRow.';
    B=cfg.phy.csirs.precoderMatrices(:,:,initialCRI+1);
    assert(norm(w-B*(B'*w))/norm(w)<1e-12);
    for cri=0:7
        state=emptyState(cfg);
        state=sixgr.truth.CoupledTruthRuntime.stageMeasuredSSBBeamRuntime( ...
            state,1,active(k),-80,'declared_selected_SSB_callback_fixture');
        assert(state.PendingBeamCRIByUE==initialCRI && isnan(state.AppliedDataBeamCRIByUE));
        report=struct('Direction',"DL",'UEIndex',1,'CRI',cri, ...
            'CSIUCIDecodeOk',false,'SourceSignal',"received_CSI_UCI", ...
            'ReportIdentity',"declared_callback_fixture_not_physical_UCI");
        reject(@()sixgr.truth.CoupledTruthRuntime.stageReceivedCSIBeamRuntime(state,report), ...
            'sixgr:truth:BeamRefinementRequiresReceivedCSI');
        report.CSIUCIDecodeOk=true;
        state=sixgr.truth.CoupledTruthRuntime.stageReceivedCSIBeamRuntime(state,report);
        assert(state.PendingBeamCRIByUE==cri && isnan(state.AppliedDataBeamCRIByUE));
        code=cfg.phy.beamManagement.csiResourceToTCICodepoints(cri+1);
        [state,accepted]=sixgr.truth.CoupledTruthRuntime.applyDecodedTCIBeamRuntime( ...
            state,1,table(mod(code+1,8),'VariableNames',{'DecodedDCITCICodepoint'}));
        assert(~accepted && isnan(state.AppliedDataBeamCRIByUE));
        [state,accepted]=sixgr.truth.CoupledTruthRuntime.applyDecodedTCIBeamRuntime( ...
            state,1,table(code,'VariableNames',{'DecodedDCITCICodepoint'}));
        assert(accepted && state.AppliedDataBeamCRIByUE==cri && ...
            state.ActiveTCIStateIDByUE==cfg.phy.beamManagement.csiResourceToTCIStateIDs(cri+1));
    end
end
state=emptyState(cfg);
inactive=setdiff(0:cfg.phy.ssb.Lmax-1,active);
if ~isempty(inactive)
    reject(@()sixgr.truth.CoupledTruthRuntime.stageMeasuredSSBBeamRuntime( ...
        state,1,inactive(1),-80,'declared_inactive_negative_fixture'), ...
        'sixgr:truth:MeasuredSSBOutsideBeamMap');
end
end

function state=emptyState(cfg)
state=struct('CfgMobility',cfg,'CurrentSlot',1,'CurrentSNR_dB',20, ...
    'SweepPointIndex',1,'BeamManagementRuntimeEnabled',true, ...
    'BeamManagementMachines',{{sixgr.phy.beam.BeamManagementStateMachine("IDLE")}}, ...
    'BeamManagementStateTraceTable',table(), ...
    'PendingBeamCRIByUE',NaN,'PendingTCIStateIDByUE',NaN, ...
    'PendingTCICodepointByUE',NaN,'PendingBeamSourceByUE',"", ...
    'ActiveTCIStateIDByUE',NaN,'ActiveTCICodepointByUE',NaN,'AppliedDataBeamCRIByUE',NaN);
end

function reject(f,id)
try
    f();
catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('test:MissingExpectedRejection','Expected %s.',id);
end
