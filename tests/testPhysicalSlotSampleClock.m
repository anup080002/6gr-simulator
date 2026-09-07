function ok=testPhysicalSlotSampleClock()
% Independent public OFDM layout comparison, including unequal normal-CP
% slot sample extents at mu >= 2 and extended CP.
for scs=[15 30 60 120 240]
    prefixes="normal"; if scs==60, prefixes=["normal","extended"]; end
    for cp=prefixes
        c=nrCarrierConfig('NSizeGrid',24,'SubcarrierSpacing',scs,'CyclicPrefix',char(cp));
        info=nrOFDMInfo(c); expected=0;
        for slot=0:2*c.SlotsPerSubframe-1
            assert(sixgr.phy.frame.slotStartSample(c,slot,info.SampleRate)==expected);
            positions=mod(slot,c.SlotsPerSubframe)*c.SymbolsPerSlot+(1:c.SymbolsPerSlot);
            expected=expected+sum(info.SymbolLengths(positions));
            assert(sixgr.phy.frame.slotStartSample(c,slot+1,info.SampleRate)==expected);
        end
        if scs>=60 && cp=="normal"
            first=sixgr.phy.frame.slotStartSample(c,1,info.SampleRate);
            second=sixgr.phy.frame.slotStartSample(c,2,info.SampleRate)-first;
            assert(first~=second,'This fixture must expose the unequal-slot clock defect.');
        end
    end
end
ok=true; disp('PHYSICAL_SLOT_SAMPLE_CLOCK_PASS: actual OFDM CP layouts, mu=0..4 and 60-kHz extended CP.');
end
