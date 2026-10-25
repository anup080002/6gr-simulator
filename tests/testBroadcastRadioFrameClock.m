function ok=testBroadcastRadioFrameClock()
% Actual SS/PBCH, SI-RNTI DCI and SIB1 decoding at later/wrapped frames.
% No channel/RF/statistical qualification is implied by these unit-link cases.
setup6GRSimToolkit('Verbose',false);
cfg=localConfig(); carrier=sixgr.phy.grid.makeCarrier(cfg);
configured=sixgr.phy.broadcast.deriveType0PDCCHFromMIB(carrier,cfg, ...
    struct('PDCCHConfigSIB1',4,'Source',"configured_test"));
assert(configured.SSBFrameNumberSource=="configured_carrier_frame_not_received");
mib=struct('PDCCHConfigSIB1',4,'SystemFrameNumberMSB6',0, ...
    'SystemFrameNumber',2,'SSBIndex',0);
poison=cfg;poison.phy.carrier.NFrame=799;
resolved=sixgr.phy.broadcast.deriveType0PDCCHFromMIB(carrier,poison,mib);
assert(resolved.Context.SSBFrameNumber==2 && ...
    resolved.SSBFrameNumberSource=="received_BCH_SFN");
wrapped=mib;wrapped.SystemFrameNumber=0;wrapped.AbsoluteFrameNumber=1024;
wrappedResult=sixgr.phy.broadcast.deriveType0PDCCHFromMIB(carrier,poison,wrapped);
assert(all(wrappedResult.MonitoringOccasions.SFN>=0 & wrappedResult.MonitoringOccasions.SFN<=1023));
assert(all(wrappedResult.MonitoringOccasions.AbsoluteFrameNumber>=1024));
for value={-1,'2',NaN,1.5}
    context=resolved.Context;context.SSBFrameNumber=value{1};
    reject(@()sixgr.phy.pdcch.Type0PDCCHResolver(context), ...
        'sixgr:phy:pdcch:type0_context_not_supported');
end
bad=rmfield(mib,'SystemFrameNumber');
reject(@()sixgr.phy.broadcast.deriveType0PDCCHFromMIB(carrier,poison,bad), ...
    'sixgr:phy:broadcast:MissingReceivedSFN');
bad=mib;bad.AbsoluteFrameNumber=3;
reject(@()sixgr.phy.broadcast.deriveType0PDCCHFromMIB(carrier,poison,bad), ...
    'sixgr:phy:broadcast:InconsistentReceivedSFN');
bad=mib;bad.SystemFrameNumber='2';
didReject=false;try,sixgr.phy.broadcast.deriveType0PDCCHFromMIB(carrier,poison,bad);catch,didReject=true;end
assert(didReject,'Do not convert text into an ASCII-valued SFN.');

rows=struct('Frame',{},'DecodedSFN',{},'ObservationStartSample',{}, ...
    'SIB1AbsoluteSlot',{},'SIB1CaptureLocalStartSample',{},'BCHCRC',{},'DCICRC',{},'SIB1CRC',{});
for frame=[0 2 1023 1024]
    txCfg=cfg;txCfg.phy.carrier.NFrame=frame;
    tx=sixgr.phy.broadcast.generateSSB_MIB_SIB1_Waveform(txCfg,'SNRdB',35,'Seed',137+frame);
    start=frame*0.01*tx.SampleRateHz;
    assert(tx.BroadcastStartAbsoluteSlot==frame*20 && tx.BroadcastStartSample==start);
    assert(tx.SIB1WaveformStartSample== ...
        sixgr.phy.frame.slotStartSample(tx.Carrier,tx.SIB1AbsoluteSlot,tx.SampleRateHz)-start);
    observation=sixgr.phy.waveform.WaveformObservationBuffer( ...
        start,start+size(tx.Waveform,1),tx.SampleRateHz,size(tx.Waveform,2));
    observation.append(sixgr.phy.waveform.WaveformChunk(tx.Waveform,start),tx.SampleRateHz);
    % Receiver configured frame is deliberately unrelated; only original
    % received samples, decoded BCH and typed capture epoch may own timing.
    rxCfg=cfg;rxCfg.phy.carrier.NFrame=777;
    rx=sixgr.phy.broadcast.recoverSIB1FromWaveform(observation,rxCfg);
    assert(rx.StrictOk && rx.BCHCrcPass && rx.DCICrcPass && rx.DLSCHCrcPass, ...
        'Frame %d physical recovery failed: %s / %s',frame,rx.Status,rx.FailureReason);
    assert(rx.MIBSystemFrameNumber==mod(frame,1024) && rx.SIB1AbsoluteSlot==tx.SIB1AbsoluteSlot);
    assert(rx.Type0FrameNumberSource=="received_BCH_SFN_bound_to_capture_epoch");
    assert(rx.PDSCHControlEvent.DecoderInfo.ReceiverAbsoluteSlotIndex0==rx.SIB1AbsoluteSlot, ...
        'Decoded SI control evidence must not retain an acquisition/configured slot.');
    [same,~]=sixgr.rrc.asn1.compareSIB1Trees(tx.TxTree,rx.SIB1RxTree);assert(same);
    timing=sixgr.phy.frame.receivedDLTimingReference(rxCfg,rx,observation,0);
    assert(timing.AbsoluteFrameNumber==frame && timing.ReceivedSFN==mod(frame,1024));
    rows(end+1)=struct('Frame',frame,'DecodedSFN',rx.MIBSystemFrameNumber, ...
        'ObservationStartSample',start,'SIB1AbsoluteSlot',rx.SIB1AbsoluteSlot, ...
        'SIB1CaptureLocalStartSample',rx.SIB1ObservationStartSample, ...
        'BCHCRC',rx.BCHCrcPass,'DCICRC',rx.DCICrcPass,'SIB1CRC',rx.DLSCHCrcPass); %#ok<AGROW>
    % Decode the same IQ without a lab epoch: retain a labelled SFN-cycle
    % clock, not an invented unwrapped frame number copied from the TX.
    raw=sixgr.phy.broadcast.recoverSIB1FromWaveform(tx.Waveform,rxCfg);
    assert(raw.StrictOk && raw.MIBSystemFrameNumber==mod(frame,1024));
    assert(raw.SIB1RadioFrameClock=="decoded_SFN_cycle_without_global_capture_epoch");
    assert(raw.SIB1ObservationStartSample==rx.SIB1ObservationStartSample);
    if frame==2
        shifted=sixgr.phy.waveform.WaveformObservationBuffer( ...
            start+0.01*tx.SampleRateHz,start+0.01*tx.SampleRateHz+size(tx.Waveform,1), ...
            tx.SampleRateHz,size(tx.Waveform,2));
        shifted.append(sixgr.phy.waveform.WaveformChunk(tx.Waveform,shifted.StartSample),tx.SampleRateHz);
        wrong=sixgr.phy.broadcast.recoverSIB1FromWaveform(shifted,rxCfg);
        assert(~wrong.StrictOk && ~wrong.SIB1ReceptionAttempted && ...
            wrong.FailureIdentifier=="sixgr:phy:broadcast:ReceivedSFNClockMismatch", ...
            'Relabelled old IQ must not reach an SI decoding attempt.');
    end
    fprintf('BROADCAST_RADIO_FRAME_PASS frame=%d sfn=%d si_slot=%d\n',frame,rx.MIBSystemFrameNumber,rx.SIB1AbsoluteSlot);
end
folder=fullfile('results','validation','broadcast_radio_frame',char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(folder);writetable(struct2table(rows),fullfile(folder,'decoded_frame_trials.csv'));
fprintf('BROADCAST_RADIO_FRAME_EVIDENCE %s\n',folder);
ok=true;
end

function cfg=localConfig()
cfg=sixgr.config.defaultConfig();cfg.run.strictMode=true;
cfg.phy.sib1.enable=true;
cfg.phy.carrier.NCellID=17;cfg.phy.carrier.NFrame=0;cfg.phy.carrier.NSlot=0;
cfg.phy.carrier.SubcarrierSpacing=30;cfg.phy.carrier.SubcarrierSpacing_kHz=30;
cfg.phy.carrier.NSizeGrid=51;cfg.phy.channelBandwidth_MHz=20;
cfg.frequency.bandwidth_hz=20e6;cfg.channel.bandwidth_Hz=20e6;
cfg.phy.ssb.NCRBSSB=30;cfg.phy.ssb.KSSB=0;
cfg.phy.ssb.periodicity_ms=10;cfg.phy.ssb.period_ms=10;
cfg.phy.ssb.activeBitmap=logical([1 0 0 0 0 0 0 0]);
cfg.initial_access.type0=struct('monitoring_occasion_ordinal',1);
cfg.initial_access.sib1.pdsch=struct('prb_start',0,'num_prb',24, ...
    'symbol_start',2,'num_symbols',12,'mcs',0,'rv',0);
cfg.phy.sib1.coreset0Index=0;cfg.phy.sib1.searchSpaceZero=4;
cfg.phy.mib.pdcchConfigSIB1=4;cfg.phy.mib.dmrsTypeAPosition=2;
end

function reject(call,id)
try,call();catch cause,assert(strcmp(cause.identifier,id),'Expected %s, got %s',id,cause.identifier);return;end
error('test:ExpectedBroadcastClockRejection','Expected %s',id);
end
