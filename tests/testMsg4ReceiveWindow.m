function ok=testMsg4ReceiveWindow()
% Actual NR coded Msg4 and independent silence observations, TDD only.
setup6GRSimToolkit('Verbose',false);
cfg=raStrictAnchorConfig(); cfg.phy.duplex.mode="TDD";
ra=sixgr.mac.ra.RAConfig(cfg,'RunId','contention_window_unit');
ra.PreamblePowerRampingCounter=1;
ra.RAContentionResolutionTimerSlots=16; % 8 ms at this 30-kHz component carrier.
grant=sixgr.mac.ra.buildRARULGrant(ra);
message=sixgr.mac.ra.buildMsg3Payload('UEId',1,'UEIdentity','UE-1');
carrier=sixgr.phy.grid.makeCarrier(cfg); info=nrOFDMInfo(carrier); fs=double(info.SampleRate);
origin=sixgr.phy.frame.slotStartSample(carrier,ra.Msg3Slot,fs);
% Explicit zero-phase/no-TA component clock, not a primary runtime artifact.
timing=struct('Source',"received_DL_reference_received_RAR_TA_and_common_offset", ...
    'WaveformTimingApplied',true,'SampleRateHz',fs,'TransmitStartSample',origin, ...
    'NominalStartSample',origin,'DLReference',struct('DLPhaseOffsetSamples',0));
armed=sixgr.phy.ra.Msg4ReceiveWindow(cfg,ra,grant,message.ContentionIdentity,timing);
assert(~isempty(armed.Window.MonitoringSlots));
zero=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol(ra.Msg3Slot,grant.SymbolStart,armed.Window.Numerology);
last=zero.plusSymbols(grant.NumSymbols,armed.Window.Numerology);
assert(armed.Window.StartTicks==last.Ticks && ...
    armed.Window.ExpiryTicksExclusive-last.Ticks==int64(.008*1966080000));
firstSlot=armed.Window.MonitoringSlots(1);
for wrong=[false true]
    receiver=armed.start(armed.Window.StartTicks);
    id=message.ContentionIdentity;
    if wrong, id="FFFFFFFFFFFF"; end
    payload=sixgr.mac.ra.buildMsg4ContentionResolution(id,'FinalCRNTI',ra.FinalCRNTI);
    scheduled=ra; scheduled.Msg4Slot=firstSlot;
    tx=sixgr.phy.ra.generateMsg4Waveform(cfg,scheduled,payload);
    obs=localObservation(carrier,firstSlot,fs,[tx.Waveform -tx.Waveform]);
    [receiver,out]=receiver.receive(firstSlot,obs,cfg);
    assert(out.Observation.DCICrcPass && out.Observation.PDSCHCrcPass, ...
        'Actual coded Msg4 must decode before testing MAC ownership.');
    expected="succeeded"; if wrong, expected="identity_mismatch"; end
    assert(receiver.MAC.Status==expected && receiver.MAC.IdentityMatches==~wrong);
    if wrong, mismatchReceiver=receiver; end
end
receiver=armed.start(armed.Window.StartTicks);
stream=RandStream('mt19937ar','Seed',921401);
for slot=reshape(receiver.Window.MonitoringSlots,1,[])
    a=sixgr.phy.frame.slotStartSample(carrier,slot,fs);
    b=sixgr.phy.frame.slotStartSample(carrier,slot+1,fs);
    b=min(b,double(receiver.Window.ExpiryTicksExclusive)*fs/1966080000);
    noise=1e-3*(randn(stream,b-a,2)+1i*randn(stream,b-a,2));
    obs=localObservation(carrier,slot,fs,noise);
    [receiver,out]=receiver.receive(slot,obs,cfg);
    assert(out.Status=="waiting" && ~out.Observation.PDSCHCrcPass);
end
receiver=receiver.expire(receiver.Window.ExpiryTicksExclusive);
assert(receiver.MAC.Status=="expired" && height(receiver.Observations)==numel(receiver.Window.MonitoringSlots));
% Retry ownership uses a physically decoded matching RAR and its BI, not
% a gNB-side Msg3 result or configured backoff substituted for reception.
rarReceiver=sixgr.phy.ra.RARReceiveWindow(cfg,ra);
rarSlot=rarReceiver.Window.MonitoringSlots(1);
scheduled=ra; scheduled.Msg2Slot=rarSlot;
rar=sixgr.mac.ra.encodeMACRAR('RAPID',ra.PreambleIndex,'TimingAdvanceCommand',0, ...
    'TemporaryCRNTI',ra.TempCRNTI,'ULGrant',grant,'BackoffIndicator',2);
tx=sixgr.phy.ra.generateMsg2RARWaveform(cfg,scheduled,rar);
rarReceiver=rarReceiver.receive(rarSlot,localObservation(carrier,rarSlot,fs,tx.Waveform),cfg);
assert(rarReceiver.Status=="matched" && rarReceiver.PreambleBackoff_ms==20);
retry=sixgr.mac.ra.RARetryState(19831);
retry=retry.prepare("cell_1/SSB_0",int64(0),false,false);
retry=retry.arm(ra); retry=retry.transmitted(ra.PRACHActiveEndTicksExclusive);
retry=retry.rarAccepted();
for failed={mismatchReceiver,receiver}
    rx=failed{1};
    [next,event]=retry.contentionFailed(rx,rarReceiver,rx.MAC.ResolutionTicks);
    assert(next.TransmissionCounter==2 && next.Status=="ready" && ...
        event.PreambleBackoff_ms==20 && isnan(event.ResponseExpiryTicks) && ...
        event.ContentionResolutionTicks==double(rx.MAC.ResolutionTicks) && ...
        event.EarliestRetryTicks==event.ContentionResolutionTicks+event.BackoffTicks);
    assert(rx.MAC.Msg3HARQFlushRequired && rx.MAC.TemporaryCRNTIDiscardRequired);
end
fprintf('MSG4_RECEIVE_WINDOW_PASS: matching/mismatching coded identity; %d real noise-only monitoring windows before expiry.\n',height(receiver.Observations));
ok=true;
end
function obs=localObservation(carrier,slot,fs,samples)
a=sixgr.phy.frame.slotStartSample(carrier,slot,fs);
obs=sixgr.phy.waveform.WaveformObservationBuffer(a,a+size(samples,1),fs,size(samples,2));
obs.append(sixgr.phy.waveform.WaveformChunk(samples,a),fs);
end
