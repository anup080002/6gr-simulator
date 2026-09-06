function ok = testDataChannelStreamStages()
% Actual coded TDD-configured TX/RX through an attenuator plus sample noise.
% This tests stage ownership/coverage and exact payload retention. The
% analytic pathloss fixture and isolated SRS below do NOT qualify access,
% RF, shared-channel propagation, scheduler integration or link adaptation.
setup6GRSimToolkit('Verbose',false);
s = sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_causal_access_to_data_wiring_tdd.yaml'));
base = sixgr.lls6g.buildInternalConfig(s,tempname);
base.channel.model = 'AWGN';
base.channel.fading.enabled = false;
base.channel.fading.type = 'AWGN';
sixgr.runtime.RuntimeCallLedger.configure(tempname);
cleanup = onCleanup(@()sixgr.runtime.RuntimeCallLedger.reset()); %#ok<NASGU>
directions = ["DL","UL","UL"];
for caseIndex = 1:numel(directions)
    direction = directions(caseIndex);
    withUCI = caseIndex==3;
    cfg = base;
    if direction == "UL"
        cfg.lls6g.userContext.RuntimeServingPathloss_dB = 77;
        cfg.lls6g.userContext.RuntimeServingPathlossSource = 'unit_test_analytic_reference_pathloss';
        cfg.lls6g.userContext.RuntimeServingPathlossReferenceRS = 'unit_test_reference';
        cfg.lls6g.userContext.RuntimeServingPathlossMeasurementId = 'unit_test_analytic_input_not_runtime_measurement';
    end
    controlSlot0 = 0;
    if direction=="UL"
        % Authored DDD-S-U pattern: SRS in U (slot 4), subsequent control
        % in S (slot 8), K2=1 to U. Feedback precedes the UL grant.
        % Slot 0 + K2 would hit a fixed DL slot and must remain rejected.
        localReject(@()sixgr.link.resolveWaveformGrant(cfg,direction,0), ...
            'sixgr:SchedulerBase:TimingDecisionRejected');
        controlSlot0 = 8;
    end
    if direction=="UL"
        [cfg,grant] = localSoundedULGrant(cfg,controlSlot0);
    else
        grant = sixgr.link.resolveWaveformGrant(cfg,direction,controlSlot0);
    end
    assert(grant.Valid && grant.ExactPHYFeasible && grant.DCI.BitExactPDCCHPayload);
    slot = double(grant.ScheduledAbsoluteSlot)+1;
    frame = floor((slot-1)/(10*double(cfg.phy.carrier.SubcarrierSpacing)/15))+1;
    cfg = sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,slot,frame);
    if direction == "DL"
        runner = @sixgr.link.runDLPDSCHThroughput;
        txName = "sixgr.phy.dl.PDSCH_Tx"; rxName = "sixgr.phy.dl.PDSCH_Rx";
        grant.ControlDecodeOk = false; grant.PDCCHGrantBindingOk = false;
    else
        runner = @sixgr.link.runULPUSCHThroughput;
        txName = "sixgr.phy.ul.PUSCH_Tx"; rxName = "sixgr.phy.ul.PUSCH_Rx";
        % Dynamic UL transmission needs an actually decoded control waveform.
        grant = localReceiveControl(cfg,grant);
    end
    args = {'NumFrames',1,'StartSlotIndex',slot,'StartFrameIndex',frame, ...
        'GrantSnapshot',grant,'PHYGrant',grant.PHYGrant};
    if withUCI
        % Known codec-test HARQ bits, not invented feedback from a DL run.
        uci = sixgr.phy.ul.pusch.PUSCHUCIPayload('HARQACK',int8([1;0]));
        args = [args {'ExpectedUCIPayload',uci}]; %#ok<AGROW>
    end
    before = sixgr.runtime.RuntimeCallLedger.snapshot();
    pending = runner(cfg,args{:},'PrepareOnly',true);
    afterTX = sixgr.runtime.RuntimeCallLedger.snapshot();
    assert(~pending.Ok && ~pending.Skipped && isempty(pending.TrialTable) && ...
        pending.ExecutionStage == "transmit_prepared_not_received");
    assert(localCount(afterTX,txName)==localCount(before,txName)+1 && ...
        localCount(afterTX,rxName)==localCount(before,rxName));
    prepared = pending.PreparedTransmission;
    assert(~prepared.Tx.PowerContext.PAApplied && ...
        (~prepared.Tx.PowerContext.PAEnabled || prepared.Tx.PowerContext.PAExecutionDeferred) && ...
        ~isfield(prepared.Tx,'TxRFImpairmentReplay'));
    assert(all(isfinite(prepared.Tx.Waveform(:))) && any(abs(prepared.Tx.Waveform(:))>0));
    if direction == "DL"
        receivedGrant = localReceiveControl(cfg,grant);
        args{8} = receivedGrant;
    end
    % The test owner applies a declared 77 dB connector attenuation and
    % independent fixed sample noise. It measures the actual signal power;
    % it does not adapt noise to current signal power or manufacture SNR.
    if direction=="DL", role='bs'; signalName='pdsch'; else, role='ue'; signalName='pusch'; end
    array = sixgr.rf.AntennaArrayFactory.build(cfg,role,'signal',signalName, ...
        'numPorts',size(prepared.Tx.Waveform,2));
    x = prepared.Tx.Waveform * cast(array.PortToElementMatrix.','like',prepared.Tx.Waveform);
    assert(size(x,2)==prepared.NumPhysicalTransmitAntennas);
    assert(abs(norm(x,'fro')-norm(prepared.Tx.Waveform,'fro')) < 1e-10*norm(x,'fro'), ...
        'The configured physical port projection must conserve this waveform power.');
    numRx = grant.PHYGrant.AntennaArchitecture.NumRxAntennas;
    connector = eye(size(x,2),numRx) .* 10^(-77/20);
    delaySamples = 7;
    % Exact integer-delay test channel, including its actual late samples.
    % Idle input after the TX slot lets the channel flush its stored samples.
    input = [x; zeros(delaySamples,size(x,2),'like',x)];
    signal = filter([zeros(1,delaySamples) 1],1,input*cast(connector,'like',x));
    variance = 1e-13; % mW per complex sample per branch, fixed for both directions.
    [y,noiseState] = sixgr.link.addRuntimeComplexNoise(signal,variance,81,prepared.StartSample,struct());
    signalPower = mean(abs(double(signal(:))).^2);
    replay = struct('InjectedNoiseVariance',variance,'SampleNoiseVariance',variance, ...
        'Source','unit_connector_attenuation_and_actual_fixed_variance_noise', ...
        'NoiseVarianceSource','fixed_unit_test_sample_noise_variance', ...
        'DesiredSignalPowerBeforeNoise',signalPower,'CompositeSignalPowerBeforeNoise',signalPower, ...
        'AppliedNoiseSNR_dB',10*log10(signalPower/variance), ...
        'AppliedNoiseSNRSource','actual_attenuated_sample_power_over_fixed_noise_variance', ...
        'SNRReferencePlane','receiver_sample_waveform_pre_composite_front_end');
    context = struct('Prepared',prepared,'Observation',localBuffer(prepared,y), ...
        'PhysicalMeasurementObservation',localBuffer(prepared,y), ...
        'TransmitterObservation',localBuffer(prepared,x), ...
        'Replay',replay, ...
        'ChannelState',struct('Initialized',false,'UseFading',false,'Obj',[], ...
        'ReceiverNoiseState',noiseState));
    bad = context;
    bad.Observation = sixgr.phy.waveform.WaveformObservationBuffer( ...
        prepared.StartSample,prepared.EndSampleExclusive,prepared.SampleRateHz,size(y,2));
    localReject(@()runner(cfg,args{:},'ReceivedContext',bad),'WAVEFORM:IncompleteObservation');
    bad = context;
    bad.Observation = sixgr.phy.waveform.WaveformObservationBuffer( ...
        prepared.StartSample+1,prepared.EndSampleExclusive+1,prepared.SampleRateHz,size(y,2));
    localReject(@()runner(cfg,args{:},'ReceivedContext',bad),'sixgr:link:DataObservationMismatch');
    bad = context;
    bad.PhysicalMeasurementObservation = localBuffer(prepared,y(1:end-1,:));
    localReject(@()runner(cfg,args{:},'ReceivedContext',bad),'sixgr:link:DataObservationPlaneMismatch');
    bad = context; bad.Replay.ApproximationMode = 'fast_proxy';
    localReject(@()runner(cfg,args{:},'ReceivedContext',bad),'sixgr:link:ProxyDataStreamForbidden');
    bad = context; bad.Replay.FallbackUsedForPathloss = true;
    localReject(@()runner(cfg,args{:},'ReceivedContext',bad),'sixgr:link:ProxyDataStreamForbidden');
    wrongCfg = cfg; wrongCfg.phy.carrier.NCellID = cfg.phy.carrier.NCellID+1;
    localReject(@()runner(wrongCfg,args{:},'ReceivedContext',context), ...
        'sixgr:link:PreparedDataRequestMismatch');
    if withUCI
        badArgs = args;
        badArgs{end} = sixgr.phy.ul.pusch.PUSCHUCIPayload('HARQACK',int8([0;0]));
        localReject(@()runner(cfg,badArgs{:},'ReceivedContext',context), ...
            'sixgr:link:PreparedDataRequestMismatch');
    end
    rng(459,'twister'); rngBefore = rng;
    beforeRX = sixgr.runtime.RuntimeCallLedger.snapshot();
    completed = runner(cfg,args{:},'ReceivedContext',context);
    afterRX = sixgr.runtime.RuntimeCallLedger.snapshot();
    assert(isequal(rngBefore,rng),'Receive completion must not reset/consume the TX RNG.');
    assert(localCount(afterRX,txName)==localCount(beforeRX,txName) && ...
        localCount(afterRX,rxName)==localCount(beforeRX,rxName)+1);
    if completed.TrialTable.CRCPass~=1
        disp(completed.Notes);
        fields = intersect(["Direction","Slot","CRCPass","TrialStatus","Notes", ...
            "EVM_rms","MeasuredSINR_dB","PostEqSINR_dB","TimingOffset", ...
            "DecodeAvailable","DecodeFailureReason","ULSCHCRCStatus"], ...
            string(completed.TrialTable.Properties.VariableNames),'stable');
        disp(completed.TrialTable(:,fields));
    end
    assert(height(completed.TrialTable)==1 && ...
        completed.TrialTable.CRCPass==1 && ...
        completed.ExecutionStage=="received_shared_stream_completed");
    assert(isequal(completed.HARQ.TransportBlockBits,completed.HARQ.DecodedTransportBlockBits));
    assert(all(completed.NoiseDomainValidation.Status=="PASS"));
    if direction=="DL"
        % The component has no complete channel/RF qualification reference.
        % Preserve that gate instead of promoting a coded loopback to a run pass.
        assert(~completed.Ok && contains(completed.Notes,'dl_pdsch_channel_rf_reference_missing'));
    else
        assert(completed.Ok);
    end
    assert(isequaln(completed.ChannelState,context.ChannelState));
    if direction=="UL"
        assert(isequaln(completed.PUSCHPowerControlState,prepared.PowerControlState));
        assert(abs(completed.TrialTable.PUSCHRequestedPower_dBm - ...
            prepared.PowerControl.RequestedPower_dBm)<1e-12);
        if withUCI
            assert(completed.HARQ.HARQACKContentMatch && ...
                isequal(completed.HARQ.DecodedHARQACKBits,int8(uci.HARQACK(:))), ...
                'PUSCH must recover the exact retained HARQ-ACK payload alongside the transport block.');
        end
        wrongTiming = prepared.RequestBinding;
        wrongTiming.Grant.TimingDecision.DataDecision.TimingAdvanceTicks = int64(1024);
        localReject(@()sixgr.link.PreparedDataTransmission('UL',cfg,wrongTiming, ...
            prepared.Tx,prepared.TxInfo,prepared.ReceiverConfig,prepared.SampleRateHz,0, ...
            prepared.PowerControl,prepared.PowerControlState), ...
            'sixgr:link:SharedULTimingAdvanceNotIntegrated');
    end
end
ok = true;
disp('PASS testDataChannelStreamStages: retained coded DL/UL samples, exact coverage and one TX/one RX.');
end

function grant = localReceiveControl(cfg,grant)
controlCfg = sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,double(grant.ControlAbsoluteSlot)+1);
p = sixgr.link.preparePDCCHTransmission(controlCfg,'Grant',grant, ...
    'RNTI',grant.RNTI,'K',numel(grant.DCI.Bits));
[rx,~] = sixgr.phy.dl.PDCCH_Rx(p.TransmitSamples,controlCfg, ...
    'Carrier',p.Tx.Carrier,'PDCCH',p.Tx.PDCCH,'RNTI',grant.RNTI, ...
    'K',numel(grant.DCI.Bits),'ExpectedDCIBits',grant.DCI.Bits, ...
    'SampleRate_Hz',p.SampleRateHz);
decoded = sixgr.phy.pdcch.decodeDCIPayload(rx.DCIBits,grant.DCI.Format,grant.DCI.ContextData);
authored = sixgr.phy.pdcch.decodeDCIPayload(grant.DCI.Bits,grant.DCI.Format,grant.DCI.ContextData);
assert(rx.Ok && rx.CausalGrantDecodeOk && isequal(rx.DCIBits(:),grant.DCI.Bits(:)) && ...
    isequaln(decoded.Fields,authored.Fields));
grant.ControlDecodeOk = logical(rx.CausalGrantDecodeOk);
grant.PDCCHGrantBindingOk = logical(rx.CausalGrantDecodeOk);
grant.PDCCHGrantDCIId = decoded.PayloadHash;
grant.PDCCHGrantDCIFormat = decoded.Format;
grant.PDCCHGrantDCIFieldsHash = sixgr.util.sha256Hex(uint8(unicode2native( ...
    jsonencode(orderfields(decoded.Fields)),'UTF-8')));
grant.PDCCHGrantFieldsHash = sixgr.util.sha256Hex(uint8(unicode2native( ...
    jsonencode(orderfields(authored.Fields)),'UTF-8')));
% These additional gates are required BEFORE preparing dynamic UL samples.
if string(grant.Direction)=="UL"
    grant.PDCCHGrantBindingRequired = true;
    grant.DCICrcPass = logical(rx.Ok);
    grant.PDCCHPayloadMatch = isequal(rx.DCIBits(:),grant.DCI.Bits(:));
    grant.DecodedDCIFields = decoded.Fields;
end
end

function [cfg,grant] = localSoundedULGrant(cfg,controlSlot0)
% Execute actual SRS samples/estimation; never relax the strict SRS gate.
srsCfg = sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,5);
[tx,info] = sixgr.phy.ul.SRS_Tx(srsCfg);
assert(~isempty(tx.SRSIndices) && any(abs(tx.Waveform(:))>0));
nRx = cfg.antenna.bs.numElements;
array = sixgr.rf.AntennaArrayFactory.build(srsCfg,'ue','signal','srs', ...
    'numPorts',size(tx.Waveform,2));
physical = tx.Waveform * cast(array.PortToElementMatrix.','like',tx.Waveform);
clean = physical * cast(eye(size(physical,2),nRx),'like',physical);
[y,~] = sixgr.link.addRuntimeComplexNoise(clean,1e-9,41,0,struct());
[rx,~] = sixgr.phy.ul.SRS_Rx(y,srsCfg,'Carrier',tx.Carrier,'SRS',tx.SRS, ...
    'NoiseVar',1e-9,'NoiseVarDomain','time');
choice = sixgr.phy.ul.estimateSRSRITPMI(rx.Hest,rx.NoiseVar,srsCfg);
assert(choice.Valid && isfinite(choice.TPMI) && choice.RI==cfg.phy.pusch.nLayers);
measurementId = sixgr.phy.waveform.WaveformHash.numeric(rx.RxGrid);
cfg.phy.pusch.TPMI = choice.TPMI;
cfg.phy.pusch.srsDecision = struct('Authoritative',choice.Valid, ...
    'MeasurementID',measurementId,'MeasurementSlot',5,'RI',choice.RI, ...
    'TPMI',choice.TPMI,'NumPorts',choice.PUSCHCodebookNumPorts);
p = cfg.phy.pusch;
grant = struct('Direction','UL','Frame',0,'Slot',controlSlot0, ...
    'RNTI',p.RNTI,'UEIndex',1,'BaseStationID',1,'ServingCell',1, ...
    'PRBSet',p.prbSet,'SymbolAllocation',p.symbolAllocation, ...
    'Modulation',p.modulation,'TargetCodeRate',p.codeRate, ...
    'MCSIndex',p.mcsIndex,'MCS',p.mcsIndex,'RV',0, ...
    'Layers',choice.RI,'NumLayers',choice.RI,'RI',choice.RI, ...
    'NumLogicalPorts',choice.PUSCHCodebookNumPorts,'TPMI',choice.TPMI, ...
    'SRSCausalUsable',choice.Valid,'SRSValid',choice.Valid, ...
    'SRSCausalMeasurementId',measurementId,'LastSuccessfulSRSSlot',5, ...
    'HARQ',struct('HarqID',0,'NDI',true,'RV',0,'IsRetransmission',false));
scheduler = sixgr.l2.mac.SchedulerPF(cfg,'Direction','UL');
grant = scheduler.attachCanonicalTimingDecision(grant);
grant = scheduler.finalizeExactPHYFeasibility(grant);
grant.DCI = scheduler.buildDCIBitfield(grant);
grant.PHYGrant = sixgr.phy.grant.freezePHYGrant(cfg,'UL',grant,'Frame',0, ...
    'Slot',controlSlot0,'HARQContext',grant.HARQ);
grant.PHYGrantContextId = grant.PHYGrant.GrantContextId;
assert(info.OFDMInfo.SampleRate>0 && double(grant.ControlAbsoluteSlot)>4);
end

function buffer = localBuffer(prepared,x)
buffer = sixgr.phy.waveform.WaveformObservationBuffer(prepared.StartSample, ...
    prepared.StartSample+size(x,1),prepared.SampleRateHz,size(x,2));
split = floor(size(x,1)/2);
buffer.append(sixgr.phy.waveform.WaveformChunk(x(1:split,:),prepared.StartSample),prepared.SampleRateHz);
buffer.append(sixgr.phy.waveform.WaveformChunk(x(split+1:end,:),prepared.StartSample+split),prepared.SampleRateHz);
end

function n = localCount(t,name)
n = sum(string(t.FunctionName)==name);
end

function localReject(call,identifier)
try, call(); catch cause
    assert(strcmp(cause.identifier,identifier),'Expected %s, got %s: %s',identifier,cause.identifier,cause.message);
    return;
end
error('TEST:MissingRejection','Expected %s.',identifier);
end
