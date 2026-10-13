function ok=testAllocatedRAIdentityRoundTrip()
% Actual Msg1/RAR/Msg3/Msg4/RRC waveforms with a gNB-allocated identity.
% Unit channel and bounded legacy Msg4 codec; not full NR MAC/RRC or
% shared-stream multi-UE qualification.
setup6GRSimToolkit('Verbose',false);
prior=rng; cleanup=onCleanup(@()rng(prior));
rng(78132,'twister');
cfg=raStrictAnchorConfig(); cfg.phy.duplex.mode='TDD';
cfg.lls6g.userContext.RuntimeServingCell=2;
cfg.random_access.temporary_crnti_pool=[6201 6205];
% Match the multi-UE target's explicit last-two-symbol PUCCH/SRS protection.
cfg.random_access.setup_complete_pusch=cfg.random_access.msg3_pusch;
cfg.random_access.setup_complete_pusch.num_symbols=12;
root=fullfile(pwd,'results','lls','allocated_ra_identity',char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(root);
[prepared,cp]=sixgr.phy.ra.runFourStepRA(cfg,'RunFolder',root,'WriteArtifacts',false, ...
    'RuntimeIntegrationMode','provided_observation_unit_channel_test', ...
    'RequireRuntimeStageWaveforms',true,'UseRuntimeChannel',false, ...
    'AllowRuntimeStageWaveformComposition',false,'StageAction','prepare_next_stage');
state=struct(); stages=["Msg1","Msg2","Msg3","Msg4","RRCSetupComplete"];
evidence=struct('Stage',{},'Result',{});
for index=1:numel(stages)
    tx=prepared.PreparedTransmission; assert(tx.StageName==stages(index));
    fs=tx.SampleRate_Hz; first=round(tx.StartTime_s*fs);
    observation=sixgr.phy.waveform.WaveformObservationBuffer(first,first+tx.SampleCount,fs,tx.PortCount);
    observation.append(sixgr.phy.waveform.WaveformChunk(tx.Waveform,first),fs);
    streams=struct(); streams.(stages(index)+"RxWaveform")=observation;
    [received,cp]=sixgr.phy.ra.runFourStepRA(cfg,'Continuation',cp, ...
        'RuntimeStageWaveforms',streams,'StopAfterStage',stages(index));
    evidence(end+1)=struct('Stage',stages(index),'Result',received); %#ok<AGROW>
    save(fullfile(root,'received_stages.mat'),'evidence','cfg');
    if index==1
        assert(received.PreambleDetected);
        [state,prepared,cp]=sixgr.truth.prepareCellRARResponse(state,cfg,cp);
        assert(cp.Msg2Tx.RAR.TemporaryCRNTI==6201 && cfg.random_access.temp_crnti~=6201);
        assert(cp.RAConfig.NCellID==17 && cp.RAConfig.ServingCell==2);
    elseif index<5
        assert(cp.RAConfig.TempCRNTI==6201,'All post-RAR stages must retain the decoded temporary identity.');
        if index==2, assert(received.Msg2PDSCHCrcPass && received.TemporaryCRNTI==6201); end
        if index==3, assert(received.Msg3PUSCHCrcPass); end
        if index==4, assert(received.Msg4PDSCHCrcPass && received.FinalCRNTI==6201); end
        if index==3
            % A competing cell-common response/SRB1 reservation must defer
            % this Msg4, without changing the already executed Msg2/Msg3.
            originalMsg4=cp.RAConfig.Msg4Slot;
            state.GNBContentionReservations=struct('ServingCell',cp.RAConfig.ServingCell, ...
                'TemporaryCRNTI',6205,'Msg4Slot',originalMsg4, ...
                'SetupCompleteSlot',cp.RAConfig.SetupCompleteSlot,'RequireSetupComplete',true);
            [state,prepared,cp]=sixgr.truth.prepareCellContentionResponse(state,cfg,cp);
            assert(cp.RAConfig.Msg4Slot>originalMsg4 && numel(state.GNBContentionReservations)==2);
            calendar=sixgr.truth.CommonRAResourceCalendar;
            calendar=calendar.reserve(sixgr.truth.CommonRAResourceCalendar.fromTransmission( ...
                cp.Msg4Tx,cp.RAConfig,"Msg4"));
            ul=calendar.lookup(cp.RAConfig.ServingCell,cp.RAConfig.SetupCompleteSlot,"UL",cp.Msg4Tx.Carrier);
            assert(~isempty(ul) && max(ul(:,2))==11 && numel(calendar.Entries)==2);
        else
            [prepared,cp]=sixgr.phy.ra.runFourStepRA(cfg,'Continuation',cp,'StageAction','prepare_next_stage');
        end
    end
end
assert(isempty(fieldnames(cp)) && received.RACompleted && received.RRCConnected && ...
    received.RRCSetupCompleteCRC && received.TemporaryCRNTI==6201 && received.FinalCRNTI==6201);
assert(received.FinalCRNTIEncodingProfile=="legacy_bounded_not_NR_MAC_RRC");
ok=true; fprintf('ALLOCATED_RA_IDENTITY_ROUNDTRIP_PASS: received C-RNTI=6201; evidence=%s\n',root);
end
