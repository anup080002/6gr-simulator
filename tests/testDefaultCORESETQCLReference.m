function ok=testDefaultCORESETQCLReference()
% Actual blind-decoded PDCCH; association is installed, not measured QCL gain.
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_received_ul_shared_queue_fixture.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,3);
g=sixgr.link.resolveWaveformGrant(cfg,'DL',1,'Slot',3,'SFN',0,'ControlAbsoluteSlot',2);
p=sixgr.link.preparePDCCHTransmission(cfg,'Grant',g,'RNTI',g.RNTI,'K',numel(g.DCI.Bits));
[rx,info]=sixgr.phy.dl.PDCCH_Rx(p.TransmitSamples,cfg,'SampleRate_Hz',p.SampleRateHz);
a=sixgr.phy.pdcch.materializeConnectedDCI(rx,info,cfg);
assert(~a.TCIPresent && ~isfield(a,'TCICodepoint') && isfield(a,'ReceivedCORESETQCLReference'));
[assignment,~,integration]=sixgr.pdsch.PDSCHAssignmentFactory.fromReceivedConnectedDCI(cfg,a,1);
binding=sixgr.pdsch.PDSCHIntegrationValidator.bind(assignment,integration);
assert(isempty(fieldnames(binding.TCIState)) && isnan(assignment.get('TCIStateId')) && ...
    binding.ReceiverQCL.BindingKind=="installed_coreset_qcl_without_dci_tci");
assert(binding.ReceiverQCL.ReceiverParameterReuseStatus== ...
    "association_only_no_measured_timing_or_spatial_reuse");
observation=sixgr.phy.waveform.WaveformObservationBuffer(0,100,p.SampleRateHz,1);
[window,evidence]=sixgr.phy.rx.applyQCLTimingTransfer(cfg,a,observation,0,[0 20],1);
assert(isequal(window,[0 20]) && ~evidence.QCLTimingPriorUsed && ...
    isnan(evidence.TCIStateID) && isnan(evidence.TCICodepoint) && ...
    evidence.TCIStatus=="field_absent_default_CORESET_QCL_association");
missing=rmfield(info,'ReceiverCORESETQCLReference');
localReject(@()sixgr.phy.pdcch.materializeConnectedDCI(rx,missing,cfg), ...
    'sixgr:qcl:MissingReceivedCORESETAssociation');
context=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg,'1_1');
for name={'configuration_epoch','serving_cell_index','component_carrier_index','bwp_id','coreset_id'}
    bad=cfg; bad.phy.pdcch.operatorControl.coreset_qcl_association.(name{1})= ...
        bad.phy.pdcch.operatorControl.coreset_qcl_association.(name{1})+1;
    localReject(@()sixgr.pdsch.CORESETQCLReference.fromInstalled(bad,context,2), ...
        'sixgr:qcl:CORESETAssociationIdentityMismatch');
end
bad=cfg; bad.phy.pdcch.operatorControl.coreset_qcl_association.activation_absolute_slot0=3;
localReject(@()sixgr.pdsch.CORESETQCLReference.fromInstalled(bad,context,2),'sixgr:qcl:InactiveCORESETAssociation');
bad=assignment.toStruct(); bad.TCIStateId=0;
localReject(@()sixgr.pdsch.PDSCHSchedulingAssignment(bad),'sixgr:qcl:CORESETAssociationIdentityMismatch');
bad=integration; bad.ActivatedTCIStates=struct('TCIStateId',0);
localReject(@()sixgr.pdsch.PDSCHIntegrationValidator.bind(assignment,bad),'sixgr:qcl:CORESETAssociationIdentityMismatch');
bad=cfg.phy.pdcch.operatorControl.coreset_qcl_association; bad.qcl_types={'A','D'};
localReject(@()sixgr.pdsch.CORESETQCLReference.validatePolicy(bad),'sixgr:qcl:CORESETSpatialReuseUnqualified');
fprintf('DEFAULT_CORESET_QCL_REFERENCE_PASS received_no_TCI=1 invented_state=0 negative_guards=10\n');
ok=true;
end
function localReject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Expected %s, got %s: %s',id,ME.identifier,ME.message); return; end
error('test:MissingRejection','Expected %s.',id);
end
