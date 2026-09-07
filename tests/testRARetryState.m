function ok=testRARetryState()
% Counter/clock component inputs plus actual blind receive-window execution.
cfg=raStrictAnchorConfig(); cfg.phy.duplex.mode="TDD";
cfg.random_access.preamble_trans_max=2;
ra=sixgr.mac.ra.RAConfig(cfg,'RunId','retry_1'); ra.PreamblePowerRampingCounter=1;
state=sixgr.mac.ra.RARetryState(18731);
state=state.prepare("cell_1/SSB_0",int64(0),false,false);
state=state.arm(ra); state=state.transmitted(ra.PRACHActiveEndTicksExclusive);
localReject(@()state.prepare("cell_1/SSB_0",ra.RARMonitoringWindow.StartTicks,false,false),'sixgr:mac:ra:RetryNotEligible');
rx=localNoRAR(cfg,ra);
[ready,row]=state.responseExpired(rx,rx.Window.ExpiryTicksExclusive);
assert(ready.TransmissionCounter==2 && ready.PowerRampingCounter==1 && ...
    row.PreambleBackoff_ms==0 && row.BackoffTicks==0 && ...
    row.EarliestRetryTicks==double(rx.Window.ExpiryTicksExclusive));
localReject(@()ready.prepare("cell_1/SSB_0",rx.Window.ExpiryTicksExclusive-1,false,false),'sixgr:mac:ra:RetryNotEligible');
changed=ready.prepare("cell_1/SSB_1",rx.Window.ExpiryTicksExclusive,false,false);
suspended=ready.prepare("cell_1/SSB_0",rx.Window.ExpiryTicksExclusive,true,false);
lbt=ready.prepare("cell_1/SSB_0",rx.Window.ExpiryTicksExclusive,false,true);
assert(changed.PowerRampingCounter==1 && suspended.PowerRampingCounter==1 && lbt.PowerRampingCounter==1);
next=ready.prepare("cell_1/SSB_0",rx.Window.ExpiryTicksExclusive,false,false);
assert(next.PowerRampingCounter==2);
ra2=sixgr.mac.ra.RAConfig(cfg,'RunId','retry_2','AttemptId',2, ...
    'RuntimeSlot',ra.PRACHAbsoluteSlot+1+ra.RARMonitoringWindow.Numerology.SlotsPerFrame);
ra2.PreamblePowerRampingCounter=2;
next=next.arm(ra2); next=next.transmitted(ra2.PRACHActiveEndTicksExclusive);
rx2=localNoRAR(cfg,ra2);
[done,row]=next.responseExpired(rx2,rx2.Window.ExpiryTicksExclusive);
assert(done.TransmissionCounter==3 && done.Status=="exhausted" && row.PreambleTransMaxExhausted && ...
    isnan(row.EarliestRetryTicks) && ~done.canStart(rx2.Window.ExpiryTicksExclusive));
localReject(@()done.prepare("cell_1/SSB_0",rx2.Window.ExpiryTicksExclusive,false,false),'sixgr:mac:ra:RetryNotEligible');
% Decode a real wrong-RAPID RAR carrying BI=2 (20 ms), then execute every
% remaining receive occasion and the deadline. No gNB-side BI metadata is
% supplied to the retry state.
withBI=localNoRAR(cfg,ra,2);
[delayed,event]=state.responseExpired(withBI,withBI.Window.ExpiryTicksExclusive);
expectedRNG=RandStream('mt19937ar','Seed',18731);
expectedDraw=rand(expectedRNG);
expectedTicks=ceil(20*expectedDraw*1966080000/1000);
assert(event.PreambleBackoff_ms==20 && event.BackoffSource=="decoded_mac_rar_bi_table_7_2_1" && ...
    event.UniformDraw==expectedDraw && event.BackoffTicks==expectedTicks && ...
    event.EarliestRetryTicks==double(withBI.Window.ExpiryTicksExclusive)+expectedTicks);
assert(~delayed.canStart(int64(event.EarliestRetryTicks)-1) && delayed.canStart(int64(event.EarliestRetryTicks)));
% Value copies must not consume each other's random stream state.
[copy,copyEvent]=state.responseExpired(withBI,withBI.Window.ExpiryTicksExclusive);
assert(isequaln(copyEvent,event) && isequal(copy.BackoffRNGState,delayed.BackoffRNGState));
ok=true; disp('RA_RETRY_STATE_PASS: independent counters, reference/LBT/suspension conditions, exact expiry and max-attempt guard.');
end

function rx=localNoRAR(cfg,ra,bi)
if nargin<3, bi=NaN; end
cfg=sixgr.phy.ra.localizeCarrierConfig(cfg,ra);
rx=sixgr.phy.ra.RARReceiveWindow(cfg,ra);
c=sixgr.phy.grid.makeCarrier(cfg); info=nrOFDMInfo(c); fs=double(info.SampleRate);
stream=RandStream('mt19937ar','Seed',7123);
for slot=reshape(rx.Window.MonitoringSlots,1,[])
    first=sixgr.phy.frame.slotStartSample(c,slot,fs); stop=sixgr.phy.frame.slotStartSample(c,slot+1,fs);
    samples=(randn(stream,stop-first,1)+1i*randn(stream,stop-first,1))*1e-3;
    if isfinite(bi) && slot==rx.Window.MonitoringSlots(1)
        scheduled=ra; scheduled.Msg2Slot=slot;
        grant=sixgr.mac.ra.buildRARULGrant(scheduled);
        rar=sixgr.mac.ra.encodeMACRAR('RAPID',mod(ra.PreambleIndex+1,64), ...
            'TimingAdvanceCommand',0,'TemporaryCRNTI',ra.TempCRNTI, ...
            'ULGrant',grant,'BackoffIndicator',bi);
        tx=sixgr.phy.ra.generateMsg2RARWaveform(cfg,scheduled,rar);
        samples=tx.Waveform;
        assert(size(samples,1)==stop-first);
    end
    obs=sixgr.phy.waveform.WaveformObservationBuffer(first,stop,fs,1);
    obs.append(sixgr.phy.waveform.WaveformChunk(samples,first),fs);
    rx=rx.receive(slot,obs,cfg);
end
rx=rx.expire(rx.Window.ExpiryTicksExclusive);
end
function localReject(f,id)
try, f(); catch e, assert(string(e.identifier)==id,e.message); return; end
error('testRARetryState:MissingRejection','Expected %s.',id);
end
