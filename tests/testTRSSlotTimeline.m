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
    native=nrOFDMInfo(tx.GridSlots(1).Carrier);
    assert(isequal(tx.OFDM.SymbolLengths,native.SymbolLengths) && ...
        isequal(tx.OFDM.CyclicPrefixLengths,native.CyclicPrefixLengths));
    assert(tx.OFDM.InitialSlotInSubframe== ...
        mod(2,tx.GridSlots(1).Carrier.SlotsPerSubframe));
    assert(numel(tx.SymbolTimeline.SymbolLengths)==size(tx.PortGrid,2) && ...
        tx.SymbolTimeline.FirstSlot0Based==2 && ...
        tx.SymbolTimeline.SampleBoundaries0Based(end)==size(tx.Waveform,1));
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
    % Independently select useful samples from each separately modulated
    % active slot. The complete multislotted clock must yield the same power.
    referenceSamples=[];
    for k=1:numel(tx.GridSlots)
        resource=tx.GridSlots(k);
        [reference,clock]=nrOFDMModulate(resource.Carrier,resource.Grid,"Windowing",0);
        L=resource.Carrier.SymbolsPerSlot;
        cp=double(clock.CyclicPrefixLengths);
        cp=cp(mod(double(resource.Carrier.NSlot)*L+(0:L-1),numel(cp))+1);
        starts=[0 cumsum(cp+double(clock.Nfft))];
        active=find(any(abs(resource.Grid)>0,[1 3]));
        for symbol=active(:).'
            useful=starts(symbol)+cp(symbol)+(1:double(clock.Nfft));
            referenceSamples=[referenceSamples;reference(useful,:)]; %#ok<AGROW>
        end
    end
    expectedPower=sum(mean(abs(referenceSamples).^2,1));
    [actualPower,~,powerInfo]=sixgr.rf.measureActiveOFDMTotalPower( ...
        tx.Waveform,struct('OFDM',tx.OFDM));
    assert(abs(actualPower-expectedPower)<max(1e-14,expectedPower*1e-10));
    assert(powerInfo.OFDMSymbolClockSource== ...
        "original_transmit_slot_rotated_full_subframe_cp_pattern");
    corrupt=tx.OFDM;
    corrupt.SymbolLengths=tx.SymbolTimeline.SymbolLengths;
    corrupt.CyclicPrefixLengths=tx.SymbolTimeline.CyclicPrefixLengths;
    caught=false;
    try
        sixgr.rf.measureActiveOFDMTotalPower(tx.Waveform,struct('OFDM',corrupt));
    catch ME
        caught=strcmp(ME.identifier,'sixgr:rf:ActiveOFDMClockMetadata');
    end
    assert(caught,'Expanded waveform lengths must not replace a native subframe clock.');
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
    end
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
fprintf('TRS_SLOT_TIMELINE_PASS: native clock/power and true gaps at 15/30/60/120 kHz; received CFO verified.\n');
ok=true;
end
