function ok=testTRSSlotTimeline()
% Configured TRS gaps must survive modulation, power scaling and reception.
setup6GRSimToolkit("Verbose",false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile("simulator","configs", ...
    "scenarios","lls_causal_access_to_data_wiring_tdd.yaml"));
base=sixgr.lls6g.buildInternalConfig(s,tempname);
for scs=[15 30 60 120]
    cfg=base;
    cfg.phy.numerology.scs_kHz=scs;
    cfg.phy.carrier.SubcarrierSpacing=scs;
    cfg.phy.trs.slotNumbers=[2 3 7 8];
    cfg.phy.trs.burstLengthSlots=2;
    p=sixgr.link.prepareTRSTransmission(cfg,12);
    tx=p.Tx;
    T=tx.SlotTable;
    assert(isequal(T.Slot,[2;3;7;8]));
    assert(tx.FirstSlot0Based==2 && T.StartSample1Based(1)==1);
    mask=false(size(tx.Waveform,1),1);
    for k=1:height(T)
        idx=T.StartSample1Based(k):T.EndSample1Based(k);
        mask(idx)=true;
        % Independent per-slot modulation must match its actual span in
        % the continuous, zero-windowing TRS waveform.
        expected=nrOFDMModulate(tx.GridSlots(k).Carrier,tx.GridSlots(k).Grid, ...
            "Windowing",0);
        assert(isequal(size(expected),size(tx.SlotWaveforms{k})));
        assert(norm(expected-tx.SlotWaveforms{k},'fro') < 1e-10);
    end
    assert(any(~mask) && all(tx.Waveform(~mask,:)==0,"all"));
    assert(all(p.TransmitSamples(~mask,:)==0,"all"));
    assert(isequal(p.TxInfo.PortGrid,tx.PortGrid));
    assert(size(tx.PortGrid,2)== ...
        (max(T.Slot)-min(T.Slot)+1)*tx.GridSlots(1).Carrier.SymbolsPerSlot);
    % Compare slot starts to independently modulated intervening slots. This
    % includes long CP placement at high numerology, not equal slot lengths.
    carrier=tx.GridSlots(1).Carrier;
    for k=1:height(T)
        expectedOffset=0;
        for slot=2:T.Slot(k)-1
            carrier.NSlot=slot;
            emptySlot=nrOFDMModulate(carrier,nrResourceGrid(carrier),"Windowing",0);
            expectedOffset=expectedOffset+size(emptySlot,1);
        end
        assert(T.StartSample1Based(k)-1==expectedOffset);
    end
    if scs==15
        assert(isequal(round(diff(T.StartSample1Based)/tx.SampleRateHz*1e3),[1;4;1]));
        t=(0:size(tx.Waveform,1)-1)'/tx.SampleRateHz;
        rx=struct("Waveform",tx.Waveform.*exp(1i*2*pi*37*t), ...
            "NoiseVariance",0,"InjectedCFO_Hz",37,"PhysicalDoppler_Hz",0, ...
            "InjectedTimingOffset_samples",0);
        timing=sixgr.phy.trs.estimateTRSTiming(rx,p.StrictConfig,tx);
        det=sixgr.phy.trs.detectTRSResources(rx,p.StrictConfig,tx, ...
            "Timing",timing);
        assert(det.DetectionSuccess);
        freq=sixgr.phy.trs.estimateTRSFrequencyOffset(det,p.StrictConfig,tx,rx);
        assert(freq.EstimateAvailable && abs(freq.EstimatedCFO_Hz-37)<0.1);
        assert(all(freq.Table.FromSymbol0Based==4) && ...
            all(freq.Table.ToSymbol0Based==8));
    end
end
fprintf('TRS_SLOT_TIMELINE_PASS: true configured gaps at 15/30/60/120 kHz; received CFO verified.\n');
ok=true;
end
