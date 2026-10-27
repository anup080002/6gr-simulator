function ok=testH4ReceivedTCIAdmission()
% Actual PDCCH decoding plus declared beam-state admission boundaries.
% The control waveform uses a logical-port unit link, not the H4 RF/CDL
% channel. These checks do not qualify beam acquisition or PDSCH reception.
setup6GRSimToolkit('Verbose',false);
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_gate.yaml');
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
% This unit-link waveform represents canonical control slot1. The receiver
% must bind the configured CORESET association at that actual slot clock.
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,1);
assert(cfg.lls6g.runtime.AbsoluteSlotIndex0==0);
assert(cfg.phy.beamManagement.requireReceivedTCIForData);
context=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg,'1_1');
schema=sixgr.phy.pdcch.DCISchemaEngine.resolve(context);
fields=struct();
for definition=schema.Definitions(:).'
    fields.(definition.Name)=definition.ValueMin;
end
decoded=cell(1,2);
controlRows=cell(1,2);
codepoints=[1 3];
for k=1:numel(codepoints)
    fields.transmission_configuration_indication=codepoints(k);
    packed=sixgr.phy.pdcch.DCIPacker.pack(fields,context);
    tx=sixgr.phy.dl.PDCCH_Tx(cfg,'DCIBits',packed.Bits,'RNTI',context.Data.RNTIValue);
    [rx,info]=sixgr.phy.dl.PDCCH_Rx(tx.Waveform,cfg,'SampleRate_Hz',122.88e6);
    assert(rx.Ok && info.ReceiverConfiguredMonitoring && isequal(rx.DCIBits,packed.Bits));
    assert(info.ReceiverAbsoluteSlotIndex0==0 && ...
        isequaln(info.ReceiverCORESETQCLReference, ...
            sixgr.pdsch.CORESETQCLReference.fromInstalled(cfg,context,0)), ...
        'Retain the actual receive-clock-qualified installed association.');
    value=double(rx.DecodedDCI.Fields.transmission_configuration_indication);
    assert(value==codepoints(k));
    decoded{k}=table(value,'VariableNames',{'DecodedDCITCICodepoint'});
    controlRows{k}=table("PASS",logical(rx.Ok),isequal(rx.DCIBits,packed.Bits), ...
        logical(rx.Ok),false,false,value,1,'VariableNames', ...
        {'Status','DCICrcPass','PDCCHPayloadMatch','PDCCHCausalGrantDecodeOk', ...
         'PDCCHFalseAlarm','PDCCHMissedDetection','DecodedDCITCICodepoint','Slot'});
end
missing=table(NaN,'VariableNames',{'DecodedDCITCICodepoint'});
checks=0;
for phase=["IDLE","P1_MEASURING","P1_REPORTED", ...
        "BEAM_FAILURE_DETECTED","BFR_RA","RECOVERED"]
    % Even a stale matching scalar is not an active beam in these states.
    for active=[NaN 3]
        state=localState(cfg,phase,active);
        [after,accepted]=sixgr.truth.CoupledTruthRuntime.applyDecodedTCIBeamRuntime(state,1,decoded{2});
        assert(~accepted && after.BeamManagementMachines{1}.State==phase, ...
            'test:TCIAdmissionFailOpen','State %s with active scalar %g admitted data without usable TCI.',phase,active);
        checks=checks+1;
    end
end
for phase=["TCI_ACTIVE","P2_REFINING","DATA_ACTIVE"]
    state=localState(cfg,phase,3);
    [after,accepted]=sixgr.truth.CoupledTruthRuntime.applyDecodedTCIBeamRuntime(state,1,decoded{2});
    assert(accepted && after.BeamManagementMachines{1}.State==phase, ...
        'The matching active beam remains usable during refinement.');
    checks=checks+1;
    for row={decoded{1},missing}
        [~,accepted]=sixgr.truth.CoupledTruthRuntime.applyDecodedTCIBeamRuntime(state,1,row{1});
        assert(~accepted,'test:TCIAdmissionFailOpen','State %s admitted an unmatched/missing codepoint.',phase);
        checks=checks+1;
    end
    state.ActiveTCICodepointByUE=NaN;
    [~,accepted]=sixgr.truth.CoupledTruthRuntime.applyDecodedTCIBeamRuntime(state,1,decoded{2});
    assert(~accepted,'test:TCIAdmissionFailOpen','State %s has no active codepoint.',phase);
    checks=checks+1;
end
% Leave explicitly non-strict and beam-disabled modes unchanged. This
% scenario policy does not replace NR's separately configured QCL defaults.
state=localState(cfg,"IDLE",NaN);
state.CfgMobility.phy.beamManagement.requireReceivedTCIForData=false;
[~,accepted]=sixgr.truth.CoupledTruthRuntime.applyDecodedTCIBeamRuntime(state,1,missing);
assert(accepted); checks=checks+1;
state=localState(cfg,"IDLE",NaN); state.BeamManagementRuntimeEnabled=false;
[~,accepted]=sixgr.truth.CoupledTruthRuntime.applyDecodedTCIBeamRuntime(state,1,missing);
assert(accepted); checks=checks+1;
% Exercise the production data-admission caller, not only its beam helper.
% The state and minimal grant envelope are explicit admission fixtures;
% decoded TCI/CRC/payload fields above come from actual PDCCH reception.
phases=["IDLE","P2_REFINING","P2_REFINING"];
active=[NaN 1 3]; expected=[false false true];
for k=1:numel(phases)
    state=localState(cfg,phases(k),active(k));
    state.NumUsers=1; state.MultiUser=struct('RNTIStart',1);
    state.CurrentSlot=1; state.CurrentFrame=1; state.CurrentServingIdx=1;
    state.SlotDuration_s=.5e-3; state.LastPDCCHStatus="";
    state.LastSuccessfulPDCCHSlotByUE=NaN;
    state.PDCCHFailureCount=0; state.GrantsBlockedByGatingCount=0;
    state.DLGrantTraceTable=table(); state.ULGrantTraceTable=table();
    state.InitialAccessEvents=table(); state.InitialAccessLifecycleTraceTable=table();
    grant=struct('UEIndex',1,'Slot',1,'Frame',1,'ServingCell',1,'ControlAbsoluteSlot',0);
    [after,bound,allowed]=sixgr.truth.CoupledTruthRuntime.applyPDCCHGrantTrial( ...
        state,grant,'DL',controlRows{2});
    assert(allowed==expected(k) && bound.ControlDecodeOk==expected(k) && ...
        bound.GrantValid==expected(k) && bound.DCICrcPass && bound.PDCCHPayloadMatch);
    assert(bound.PDCCHReceiverDecodeOk && ...
        bound.PDCCHDataAdmissionOk==expected(k));
    assert(strlength(string(bound.PDCCHTCIAdmissionStatus))>0);
    assert(after.GrantsBlockedByGatingCount==double(~expected(k)) && ...
        after.BeamManagementMachines{1}.State==phases(k));
    if ~expected(k)
        assert(startsWith(string(bound.PDCCHControlFailureReason),'pdcch_tci_binding_failed:') && ...
            isnan(after.LastSuccessfulPDCCHSlotByUE));
    else
        assert(after.LastSuccessfulPDCCHSlotByUE==1);
    end
    checks=checks+1;
end
fprintf('H4_RECEIVED_TCI_ADMISSION_PASS physical_control_decodes=2 state_checks=%d full_scenario_accepted=0\n',checks);
ok=true;
end

function state=localState(cfg,phase,active)
state=struct('CfgMobility',cfg,'BeamManagementRuntimeEnabled',true, ...
    'PendingTCICodepointByUE',NaN,'ActiveTCICodepointByUE',active);
state.BeamManagementMachines={sixgr.phy.beam.BeamManagementStateMachine(phase)};
end
