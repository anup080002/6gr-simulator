function ok=testSLSPhysicalChannelClock()
% Fading time must follow native CP-OFDM sample boundaries, not mean slots.
cfg=sixgr.config.defaultConfig();
for scs=[15 30 60 120 240]
    prefixes="normal"; if scs==60, prefixes=["normal","extended"]; end
    for cp=prefixes
        cfg.phy.carrier.SubcarrierSpacing=scs;
        cfg.phy.numerology.scs_kHz=scs;
        cfg.phy.carrier.CyclicPrefix=char(cp);
        cfg.phy.numerology.cyclicPrefix=char(cp);
        carrier=sixgr.phy.grid.makeCarrier(cfg);
        ofdm=nrOFDMInfo(carrier);
        perSlot=sum(reshape(ofdm.SymbolLengths,carrier.SymbolsPerSlot,[]),1);
        sample=0;
        for slot=0:2*carrier.SlotsPerFrame-1
            expected=sample/ofdm.SampleRate;
            grant=struct('ScheduledAbsoluteSlot',slot,'ControlAbsoluteSlot',slot);
            for field=["ScheduledAbsoluteSlot","ControlAbsoluteSlot"]
                actual=sixgr.system.waveform.resolveReplayChannelTime(cfg,grant,field,[]);
                assert(abs(actual-expected)<1e-15, ...
                    'test:SLSPhysicalChannelClock','SCS=%g CP=%s slot=%d native=%.17g modeled=%.17g', ...
                    scs,cp,slot,expected,actual);
            end
            cfg.phy.carrier.NFrame=floor(slot/carrier.SlotsPerFrame);
            cfg.phy.carrier.NSlot=mod(slot,carrier.SlotsPerFrame);
            actual=sixgr.system.waveform.resolveReplayChannelTime(cfg,struct(),'ScheduledAbsoluteSlot',[]);
            assert(abs(actual-expected)<1e-15,'Legacy carrier clock must use the same CP-aware boundary.');
            if scs>=60 && cp=="normal" && mod(slot,carrier.SlotsPerSubframe)==1
                average=slot*1e-3/carrier.SlotsPerSubframe;
                assert(abs(average-expected)>1e-10,'Fixture must expose unequal-slot timing.');
                reject(@()sixgr.system.waveform.resolveReplayChannelTime( ...
                    cfg,grant,'ScheduledAbsoluteSlot',average));
            end
            sample=sample+perSlot(mod(slot,carrier.SlotsPerSubframe)+1);
        end
    end
end
ok=true;
fprintf('SLS_PHYSICAL_CHANNEL_CLOCK_PASS native_OFDM_mu0_to4=1 extended_CP=1\n');
end

function reject(fn)
try, fn(); catch err
    assert(strcmp(err.identifier,'sixgr:system:WaveformReplay:ChannelClockMismatch')); return;
end
error('test:ExpectedClockRejection','Mean-slot fading time was accepted.');
end
