function ok=testRARReceiveWindow()
% Actual coded receive buffers; explicit component unit-channel fixtures.
% These are not fading/main-run qualification evidence.
setup6GRSimToolkit('Verbose',false); rng(491827,'twister');
for mode=["TDD","FDD"]
    cfg=raStrictAnchorConfig(); cfg.phy.duplex.mode=mode;
    ra=sixgr.mac.ra.RAConfig(cfg);
    cfg=sixgr.phy.ra.localizeCarrierConfig(cfg,ra);
    carrier=sixgr.phy.grid.makeCarrier(cfg); info=nrOFDMInfo(carrier); fs=double(info.SampleRate);
    obj=sixgr.phy.ra.RARReceiveWindow(cfg,ra); window=obj.Window;
    localReject(@()obj.expire(window.ExpiryTicksExclusive-1),'sixgr:phy:ra:PrematureRARTimeout');
    localReject(@()obj.expire(window.ExpiryTicksExclusive),'sixgr:phy:ra:UnexecutedRARMonitoring');
    slots=window.MonitoringSlots;
    assert(numel(slots)>=2);
    for slot=reshape(slots,1,[])
        start=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol(slot,0,window.Numerology);
        finish=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol(slot+1,0,window.Numerology);
        first=double(start.Ticks)*fs/1966080000;
        n=double(finish.Ticks-start.Ticks)*fs/1966080000;
        samples=(randn(n,1)+1i*randn(n,1))*1e-3;
        obs=localBuffer(samples,first,fs);
        if slot==slots(1)
            localReject(@()obj.receive(slots(2),obs,cfg),'sixgr:phy:ra:SkippedRARObservation');
        end
        [obj,out]=obj.receive(slot,obs,cfg);
        assert(~out.Accepted && ~out.Observation.DCICrcPass && out.Observation.CandidatesAttempted>0);
    end
    obj=obj.expire(window.ExpiryTicksExclusive);
    assert(obj.Status=="expired" && height(obj.Observations)==numel(slots));
    % The first correctly decoded RAR has another RAPID. The UE must keep
    % monitoring and accept its own RAPID from a later real coded waveform.
    obj=sixgr.phy.ra.RARReceiveWindow(cfg,ra);
    for k=1:2
        scheduled=ra; scheduled.Msg2Slot=slots(k);
        grant=sixgr.mac.ra.buildRARULGrant(scheduled);
        rapid=ra.PreambleIndex; if k==1, rapid=mod(rapid+1,64); end
        rar=sixgr.mac.ra.encodeMACRAR('RAPID',rapid,'TimingAdvanceCommand',0, ...
            'TemporaryCRNTI',ra.TempCRNTI,'ULGrant',grant,'BackoffIndicator',localBI(k));
        tx=sixgr.phy.ra.generateMsg2RARWaveform(cfg,scheduled,rar);
        start=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol(slots(k),0,window.Numerology);
        obs=localBuffer(tx.Waveform,double(start.Ticks)*fs/1966080000,fs);
        [obj,out]=obj.receive(slots(k),obs,cfg);
        assert(out.Observation.DCICrcPass && out.Observation.PDSCHCrcPass);
        if k==1
            assert(~out.Accepted && obj.Status=="waiting" && out.Observation.Result=="rapid_mismatch");
            assert(obj.PreambleBackoff_ms==5 && obj.BackoffSource=="decoded_mac_rar_bi_table_7_2_1", ...
                'BI index zero is 5 ms, not the absent-BI default.');
        else
            assert(out.Accepted && obj.Status=="matched" && out.RAConfig.Msg2Slot==slots(2));
            assert(obj.PreambleBackoff_ms==0 && obj.BackoffSource=="decoded_mac_rar_without_bi_zero_ms", ...
                'A subsequent CRC-valid RAR without BI resets the backoff parameter.');
            bound=sixgr.phy.ra.bindReceivedRARTiming(cfg,out.RAConfig,out.RAR.ULGrant,out.Receiver.RecoveredSchedule);
            assert(bound.Msg3Slot==slots(2)+out.RAR.ULGrant.K2+out.RAR.ULGrant.Msg3AdditionalDelaySlots);
        end
    end
    assert(all(~obj.Observations.ProxyUsed & ~obj.Observations.FallbackUsed));
end

ok=true;
disp('RAR_RECEIVE_WINDOW_PASS: actual candidate decoding, wrong-RAPID then acceptance, no skipped observations or premature expiry; TDD/FDD unit fixtures.');
end

function bi=localBI(k)
bi=NaN; if k==1, bi=0; end
end

function obs=localBuffer(samples,first,fs)
obs=sixgr.phy.waveform.WaveformObservationBuffer(first,first+size(samples,1),fs,size(samples,2));
obs.append(sixgr.phy.waveform.WaveformChunk(samples,first),fs);
end

function localReject(f,id)
try, f(); catch e, assert(string(e.identifier)==id,e.message); return; end
error('testRARReceiveWindow:MissingRejection','Expected %s.',id);
end
