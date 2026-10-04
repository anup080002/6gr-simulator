function ok = testSharedDCIConfigurationPreflight()
% Production startup guard: no RF, acquired timing or transmitted payload.
setup6GRSimToolkit('Verbose',false);
legacy = sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_causal_access_to_data_wiring.yaml');
bad = sixgr.lls6g.buildInternalConfig(legacy,tempname);
localReject(@()sixgr.truth.validateSharedDCIConfiguration(bad), ...
    'sixgr:phy:pdcch:missing_dci_context');
% An intentionally minimal state proves rejection precedes antenna/channel
% materialization, access execution and any use of runtime UE payload state.
localReject(@()sixgr.truth.CoupledWaveformStream.initialize( ...
    struct('CurrentSlot',1),bad,{bad}), ...
    'sixgr:phy:pdcch:missing_dci_context');
paths = ["simulator/configs/validation/lls_fdd_staged_data_connected_dci.yaml", ...
    "simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml"];
for path = paths
    s = sixgr.lls6g.config.loadScenarioConfig(path);
    cfg = sixgr.lls6g.buildInternalConfig(s,tempname);
    original = cfg;
    contexts = sixgr.truth.validateSharedDCIConfiguration(cfg);
    assert(isequaln(cfg,original),'Preflight must not repair or mutate configuration.');
    assert(~contexts.DL.Data.LegacyCompatibility && ~contexts.UL.Data.LegacyCompatibility);
    % Installed resource IDs are not a complete SR configuration. Reject
    % before any RF materialization, including a malformed later UE.
    missingSR=cfg;
    if isfield(missingSR.validation.pucch_resources,'scheduling_request_resources')
        missingSR.validation.pucch_resources=rmfield( ...
            missingSR.validation.pucch_resources,'scheduling_request_resources');
    end
    localReject(@()sixgr.truth.validateSharedDCIConfiguration(missingSR), ...
        'sixgr:truth:MissingInstalledSRCalendar');
    localReject(@()sixgr.truth.CoupledWaveformStream.initialize( ...
        struct('CurrentSlot',1),cfg,{cfg,missingSR}), ...
        'sixgr:truth:MissingInstalledSRCalendar');
    % Feedback callbacks start from CfgMobility, not the per-UE waveform
    % configuration prepared by runWaveformLinkBundle. They must recover
    % the same installed identity in BOTH directions without consulting TX
    % payloads or copying the event's digest to make the comparison pass.
    multi=struct('Enabled',true,'NumUsers',2,'RNTIStart',201, ...
        'ExecutionModel','slot_coupled_truth');
    runtime=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),1);
    runtime.CurrentSlot=1; runtime.CurrentServingIdx(:)=1;
    for ue=1:2
        expectedCfg=cfg;
        expectedCfg.phy.pdsch.RNTI=multi.RNTIStart+ue-1;
        expectedCfg.phy.pusch.RNTI=multi.RNTIStart+ue-1;
        expected=sixgr.truth.validateSharedDCIConfiguration(expectedCfg);
        for direction=["DL","UL"]
            [bound,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext( ...
                cfg,runtime,ue,direction);
            assert(bound.lls6g.userContext.UEIndex==ue && ...
                bound.lls6g.userContext.RNTI==multi.RNTIStart+ue-1);
            actual=sixgr.truth.validateSharedDCIConfiguration(bound);
            assert(actual.DL.Digest==expected.DL.Digest && ...
                actual.UL.Digest==expected.UL.Digest, ...
                'test:SharedUEControlIdentityMismatch', ...
                'UE %d %s binding must retain its installed DL/UL DCI identity.',ue,direction);
        end
    end
    for badStart=[NaN 0 201.5 65535]
        invalidIdentity=runtime;
        invalidIdentity.MultiUser.RNTIStart=badStart;
        localReject(@()sixgr.truth.CoupledTruthRuntime.applyUserContext( ...
            cfg,invalidIdentity,2,'UL'),'sixgr:truth:InvalidRuntimeUEIdentity');
    end
    if ~contexts.DL.Data.ConnectedPolicy.tci_present
        noQCL=cfg;
        noQCL.phy.pdcch.operatorControl=rmfield( ...
            noQCL.phy.pdcch.operatorControl,'coreset_qcl_association');
        localReject(@()sixgr.truth.validateSharedDCIConfiguration(noQCL), ...
            'sixgr:qcl:MissingCORESETAssociation');
        localReject(@()sixgr.truth.CoupledWaveformStream.initialize( ...
            struct('CurrentSlot',1),cfg,{cfg,noQCL}), ...
            'sixgr:qcl:MissingCORESETAssociation');
        wrongEpoch=cfg;
        wrongEpoch.phy.pdcch.operatorControl.coreset_qcl_association.configuration_epoch= ...
            contexts.DL.Data.ConfigurationEpoch+1;
        localReject(@()sixgr.truth.validateSharedDCIConfiguration(wrongEpoch), ...
            'sixgr:qcl:CORESETAssociationIdentityMismatch');
        % UL-only control does not impose a nonexistent DL QCL obligation.
        noQCL.phy.pdsch.enable=false;
        sixgr.truth.validateSharedDCIConfiguration(noQCL);
    end
    localReject(@()sixgr.truth.CoupledWaveformStream.initialize( ...
        struct('CurrentSlot',1),cfg,{cfg,bad}), ...
        'sixgr:phy:pdcch:missing_dci_context');
    for fmt = ["1_1","0_1"]
        expected = sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg,fmt);
        actual = contexts.DL;
        if fmt=="0_1", actual=contexts.UL; end
        assert(isequaln(actual.Data,expected.Data));
    end
    incomplete = cfg;
    incomplete.phy.pdcch.operatorControl.connected_dci = rmfield( ...
        incomplete.phy.pdcch.operatorControl.connected_dci,'beta_offsets');
    localReject(@()sixgr.truth.validateSharedDCIConfiguration(incomplete), ...
        'sixgr:phy:pdcch:IncompleteConnectedDCIPolicy');
    mismatch = cfg;
    mismatch.phy.pusch.NumAntennaPorts = 1;
    localReject(@()sixgr.truth.validateSharedDCIConfiguration(mismatch), ...
        'sixgr:phy:pdcch:ULPrecodingContextMismatch');
    if contains(path,'fdd_staged')
        rankOne=cfg;
        rankOne.phy.mimo.maxRank=1;
        rankOne.phy.pusch.maxLayers=1;
        rankOne.phy.pusch.numLayers=1;
        rankOne.phy.pdcch.operatorControl.ul_precoding.max_rank=1;
        rankOne.phy.pdsch.RNTI=201;
        rankOne.phy.pusch.RNTI=201;
        one=sixgr.truth.validateSharedDCIConfiguration(rankOne);
        assert(one.UL.Data.LayerCapability==1 && ...
            one.UL.Data.ULPrecoding.num_ports==2 && ...
            one.DL.Data.RNTIValue==201 && one.UL.Data.RNTIValue==201);
        % Actual blind PDCCH reception and downstream typed PDSCH binding.
        % The initial-access test failed here after spending 18 minutes on
        % attachment; exercise the same no-TCI path without replaying access.
        rankOne=sixgr.phy.grid.applyRuntimeCarrierTimeline(rankOne,31);
        grant=sixgr.link.resolveWaveformGrant(rankOne,'DL',1, ...
            'Slot',31,'SFN',3,'ControlAbsoluteSlot',30);
        prepared=sixgr.link.preparePDCCHTransmission(rankOne,'Grant',grant, ...
            'RNTI',grant.RNTI,'K',numel(grant.DCI.Bits));
        [decoded,info]=sixgr.phy.dl.PDCCH_Rx(prepared.TransmitSamples,rankOne, ...
            'SampleRate_Hz',prepared.SampleRateHz);
        received=sixgr.phy.pdcch.materializeConnectedDCI(decoded,info,rankOne);
        [assignment,~,integration]=sixgr.pdsch.PDSCHAssignmentFactory. ...
            fromReceivedConnectedDCI(rankOne,received,1);
        bound=sixgr.pdsch.PDSCHIntegrationValidator.bind(assignment,integration);
        assert(~received.TCIPresent && ~isfield(received,'TCICodepoint') && ...
            isnan(assignment.get('TCIStateId')) && ...
            bound.ReceiverQCL.ReceiverParameterReuseStatus== ...
            "association_only_no_measured_timing_or_spatial_reuse");
    end
end
% Standalone reference/control observations do not require scheduled-data
% configuration. This is not a bypass for an enabled shared data channel.
bad.phy.pdsch.enable=false; bad.phy.pusch.enable=false;
assert(isempty(fieldnames(sixgr.truth.validateSharedDCIConfiguration(bad))));
ok=true;
end

function localReject(f,id)
try
    f();
catch err
    assert(strcmp(err.identifier,id),'test:WrongError', ...
        'Expected %s, received %s: %s',id,err.identifier,err.message);
    return;
end
error('test:MissingError','Expected %s.',id);
end
