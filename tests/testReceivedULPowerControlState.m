function ok=testReceivedULPowerControlState()
% Real PDCCH decoder and coded PUSCH, with declared boundary PL/TAG fixtures.
% This is NOT an independently qualified access/power/BLER campaign.
setup6GRSimToolkit('Verbose',false); rng(90221,'twister');
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml');
base=sixgr.lls6g.buildInternalConfig(s,tempname);
% Explicit component configuration derived from the installed DCI profile;
% this is not the unchanged YAML's normalized-SNR scenario execution.
base.lls6g=rmfield(base.lls6g,'resolvedConfig');
base.integration=struct('run_mode','GEOMETRY_NETWORK', ...
    'configured_snr_is_link_authority',false,'power_reference_mode','absolute_calibrated_sqrt_mw');
% Explicit component TDRA: control at pattern D0, PUSCH at U4. The unit
% decoder receives a whole control-slot capture, so retain its full latency.
base.phy.pusch.timeDomainAllocations(:,4)=4;
base.phy.pusch.powerControl=struct('enabled',true,'openLoopEnabled',true, ...
    'closedLoopEnabled',true,'requireMeasuredReferenceRS',true, ...
    'adjustmentMode','accumulated','p0PUSCH_dBm',-80,'p0UE_dB',0, ...
    'alpha',.8,'deltaTF_dB',0,'pcmax_dBm',23);
base.lls6g.userContext=struct('RuntimeServingPathloss_dB',100, ...
    'RuntimeServingPathlossSource','declared_RS_measurement_boundary_fixture_not_integrated_access', ...
    'RuntimeServingPathlossReferenceRS','SSB-0', ...
    'RuntimeServingPathlossMeasurementId','power_state_component_fixture');
% The independently executed link still needs the actual installed array
% for its enabled precoder/pattern archive. Do not synthesize an antenna in
% the exporter or discard this capture to hide a missing test context.
base=sixgr.truth.attachFixedLinkRuntimeAntennaContext(base,1,1);
base.lls6g.userContext.UEIndex=1;
owner=sixgr.link.ReceivedULPowerControlState(base);
harq=sixgr.link.ReceivedULHARQState(base);
commands=[2 3 0 3 3 0]; expectedF=[1 4 3 6 6 5]; previousF=0;
for k=1:numel(commands)
    cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(base,31+10*(k-1));
    % TCI changes must not reset a UE's unrelated power accumulator.
    cfg.phy.pdsch.qclTCI.state_id=16+mod(k,3); cfg.phy.pdsch.qclTCI.codepoint=mod(k,3);
    c=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg,'0_1');
    defs=sixgr.phy.pdcch.DCISchemaEngine.resolve(c).Definitions;
    f=struct(); for d=defs(:).', f.(d.Name)=d.ValueMin; end
    f.frequency_resource_assignment=cfg.phy.carrier.NSizeGrid*5+3;
    f.mcs=0; f.rv=0; f.ndi=mod(k,2); f.harq_process=2;
    f.antenna_ports=3; f.precoding_information_and_number_of_layers=3;
    f.dmrs_sequence_initialization=1; f.tpc_command_for_pusch=commands(k);
    packet=sixgr.phy.pdcch.DCIPacker.pack(f,c);
    control=sixgr.link.preparePDCCHTransmission(cfg,'DCIBits',packet.Bits,'RNTI',c.Data.RNTIValue);
    [rx,ri]=sixgr.phy.dl.PDCCH_Rx(control.TransmitSamples,cfg,'SampleRate_Hz',control.SampleRateHz);
    a=sixgr.phy.pdcch.materializeConnectedDCI(rx,ri,cfg);
    assert(a.Fields.tpc_command_for_pusch==commands(k));
    allocation=sixgr.phy.pdcch.connectedDataAllocation(cfg,a);
    bits=int8(randi([0 1],allocation.NominalTBSBits,1));
    cfg=allocation.Config;
    if k>=4, cfg.lls6g.userContext.RuntimeServingPathloss_dB=140; end
    [tx,info,harq]=harq.transmit(cfg,a,bits,[]);
    fs=nrOFDMInfo(tx.Carrier).SampleRate;
    common=struct('Source',"decoded_sib1",'TimingAdvanceOffsetPresent',false,'TimingAdvanceOffset',"");
    cfg.SharedULTimingContext=struct('DLReference',struct( ...
        'Source',"received_SSB_timing_and_decoded_BCH",'SampleRateHz',fs, ...
        'DLPhaseOffsetSamples',6,'AvailableAtSample',1000), ...
        'Offset',sixgr.phy.frame.resolveULTimingAdvanceOffset(common,'FR1'), ...
        'ReceivedRARTiming',sixgr.phy.ra.resolveRARTimingAdvance(3,tx.Carrier.SubcarrierSpacing,fs), ...
        'TimingAdvanceAvailableAtSample',1000,'TimingAdvanceEffectiveAtSample',2000, ...
        'TimeAlignmentExpirySampleExclusive',Inf);
    obs=struct('AssignmentDigest',a.AssignmentDigest,'SampleRateHz',fs, ...
        'AvailableAtSample',sixgr.phy.frame.slotStartSample(tx.Carrier,a.ControlAbsoluteSlot+1,fs));
    before=owner;
    [wave,pc,resolved,st,owner]=owner.resolvePUSCH(cfg,a,tx,obs);
    assert(isequal(wave,tx.Waveform),'Power binding must not double-scale samples.');
    assert(pc.PreviousF_dB==previousF && pc.UpdatedF_dB==expectedF(k) && st.UpdateCount==k);
    early=owner.adjustmentAt(cfg,pc.TPCAppliedAtSample-1,fs);
    current=owner.adjustmentAt(cfg,pc.TPCAppliedAtSample,fs);
    assert(early.Adjustment_dB==previousF && current.Adjustment_dB==expectedF(k));
    assert(current.ReceivedAssignmentDigest==a.AssignmentDigest && current.StateUpdateCount==k);
    assert(isequaln(current,owner.adjustmentAt(cfg,pc.TPCAppliedAtSample,fs)), ...
        'Reading SRS state must never accumulate TPC again.');
    if k==1, firstApplied=pc.TPCAppliedAtSample; end
    historical=owner.adjustmentAt(cfg,firstApplied,fs);
    assert(historical.Adjustment_dB==1 && historical.StateUpdateCount==1, ...
        'Future queued commands must not leak into an earlier SRS.');
    requestSRS=struct('Channel','SRS','Mu',log2(tx.Carrier.SubcarrierSpacing/15), ...
        'MRB',6,'MeasuredPathloss_dB',100,'PathlossSource','measured_reference_rs_fixture', ...
        'P0_dBm',-80,'Alpha',.8,'DeltaTF_dB',0,'PCMAX_dBm',23);
    srs=sixgr.rf.runtime.SRSPowerController.resolveSharedPUSCH(owner,cfg,requestSRS,pc.TPCAppliedAtSample,fs);
    assert(abs(srs.RequestedPower_dBm-(-80+10*log10(2^requestSRS.Mu*6)+80+expectedF(k)))<1e-10);
    localReject(@()owner.adjustmentAt(cfg,pc.TPCAppliedAtSample,fs*2),'sixgr:power:AdjustmentClockMismatch');
    assert(pc.TPCAdjustmentHeldAtPowerLimit==(k==5));
    mu=log2(tx.Carrier.SubcarrierSpacing/15);
    request=-80+10*log10(2^mu*6)+.8*cfg.lls6g.userContext.RuntimeServingPathloss_dB+expectedF(k);
    assert(abs(pc.RequestedPower_dBm-request)<1e-10 && pc.TxPower_dBm==min(23,request));
    assert(abs(pc.PowerHeadroom_dB-(23-request))<1e-10);
    if k>=4, assert(pc.Clipped && pc.PowerHeadroom_dB<0); end
    [scaled,power]=sixgr.rf.applyPowerContext(wave,resolved,'UL',info,'ApplyPA',false);
    assert(abs(power.OutputTotalPower_dBm-pc.TxPower_dBm)<1e-8 && ~isequal(scaled,wave));
    assert(abs(power.PowerClosureError_dB)<1e-8);
    localReject(@()owner.resolvePUSCH(cfg,a,tx,obs),'sixgr:power:ReplayedOrNoncausalTPC');
    bad=obs; bad.AvailableAtSample=pc.TPCAppliedAtSample;
    localReject(@()before.resolvePUSCH(cfg,a,tx,bad),'sixgr:power:TPCNotYetApplicable');
    bad=obs; bad.AssignmentDigest="unreceived_command";
    localReject(@()before.resolvePUSCH(cfg,a,tx,bad),'sixgr:power:MissingReceivedTPCObservation');
    evidence=sixgr.link.puschPowerStateEvidence(pc);
    assert(evidence.PUSCHUpdatedF_dB==expectedF(k) && evidence.PUSCHStateUpdateCount==k);
    assert(evidence.PUSCHReceivedAssignmentDigest==a.AssignmentDigest);
    if k==2
        % Exercise the actual one-trial runner consumer, not just arithmetic.
        component=cfg;
        artifactParent=fullfile(pwd,'results','validation');
        if ~isfolder(artifactParent), mkdir(artifactParent); end
        component.run.rootRunFolder=tempname(artifactParent);
        mkdir(component.run.rootRunFolder);
        fprintf('POWER_STATE_COMPONENT_ARTIFACTS=%s\n',component.run.rootRunFolder);
        component.phy.pusch.executionProfile='phy_calibration';
        component.run.puschExecutionProfile='phy_calibration';
        component.run.noiseOperatingMode='standalone_awgn_snr_argument';
        component.channel.model='AWGN'; component.channel.awgnOnly=true;
        component.channel.fading.enabled=false; component.channel.fading.enable=false;
        component.channel.fading.type='AWGN';
        component.phy.pusch.receivedPowerControlState=before;
        component.phy.pusch.receivedTPCObservation=obs;
        result=sixgr.link.runULPUSCHThroughput(component,'NumFrames',1, ...
            'StartSlotIndex',a.DataAbsoluteSlot+1,'SNR_dB',35, ...
            'ExecutionProfile','phy_calibration','TransportBlockBits',bits);
        assert(height(result.TrialTable)==1 && result.TrialTable.PUSCHUpdatedF_dB==4);
        assert(isequaln(result.UEPowerControlState,owner));
        assert(result.TrialTable.PUSCHStateOwner=="received_ue_pusch_power_control");
        % Explicit narrow SRS component with measured-PL boundary fixture.
        % Prepare before the newly decoded command, bind after it, and
        % verify actual samples rather than accepting an export-only change.
        sounding=cfg;
        sounding.run.noiseOperatingMode='receiver_noise_figure_thermal_noise';
        sounding.rf.frontend.ul_power_control.srs=struct('adjustment_state','same_as_pusch', ...
            'p0_dbm',-80,'alpha',.8,'delta_tf_db',0,'pcmax_dbm',23);
        sounding.rf.frontend.ul_power_control.closed_loop_enabled=true;
        sounding.rf.frontend.ul_power_control.require_measured_reference_rs=false;
        sounding.phy.srs.receivedPowerControlState=before;
        sounding.phy.srs.period_slots=1; sounding.phy.srs.period_offset=0;
        sounding.phy.srs.slotWithinPeriod1Based=1;
        sounding=sixgr.phy.grid.applyRuntimeCarrierTimeline(sounding,a.DataAbsoluteSlot+1);
        prepared=sixgr.link.runSRSChannelEstimation(sounding,'SlotIndex',a.DataAbsoluteSlot+1, ...
            'TrialIndex',1,'TimingAdvanceSamples',sounding.SharedULTimingContext.ReceivedRARTiming.Samples, ...
            'PrepareOnly',true);
        sp=prepared.PreparedTransmission;
        resourceStart=sixgr.link.srsResourceStartSample(sp.Tx,sp.StartSample,sp.SampleRateHz);
        [emitted,scale]=sp.bindSRSPowerAtEmission(owner,resourceStart);
        assert(sp.Metadata.PowerEvidence.AccumulatedTPC_dB==1 && ...
            emitted.Metadata.PowerEvidence.AccumulatedTPC_dB==4 && ...
            abs(scale-10^(3/20))<1e-12);
        assert(norm(emitted.Tx.Waveform-sp.Tx.Waveform*scale,'fro')<1e-10);
        assert(abs(emitted.Tx.PowerContext.OutputTotalPower_dBm- ...
            emitted.Metadata.PowerEvidence.AppliedPower_dBm)<1e-8);
        actual=sixgr.link.srsPowerControlEvidence(emitted.Metadata.PowerEvidence);
        assert(actual.SRSPowerControlBoundAtEmission && ...
            actual.SRSPowerControlReceivedAssignmentDigest==a.AssignmentDigest);
        fprintf('SRS_RECEIVED_TPC_WAVEFORM_PASS before_h=1 after_h=4 amplitude_ratio=%g target=%g measured=%g\n', ...
            scale,emitted.Metadata.PowerEvidence.AppliedPower_dBm,emitted.Tx.PowerContext.OutputTotalPower_dBm);
    end
    previousF=expectedF(k);
    fprintf('RECEIVED_UL_POWER_PASS command=%d f=%g requested=%g applied=%g PH=%g\n', ...
        commands(k),pc.UpdatedF_dB,pc.RequestedPower_dBm,pc.TxPower_dBm,pc.PowerHeadroom_dB);
end
% Value-state serialization must preserve the last command and saturation.
path=[tempname '.mat']; clean=onCleanup(@()delete(path)); %#ok<NASGU>
save(path,'owner'); restored=load(path,'owner'); assert(isequaln(restored.owner,owner));
ok=true;
end

function localReject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Expected %s, got %s: %s',id,ME.identifier,ME.message); return; end
error('test:ExpectedFailure','Expected %s.',id);
end
