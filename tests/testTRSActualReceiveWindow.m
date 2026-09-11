function ok = testTRSActualReceiveWindow(mode)
% Actual OFDM component fixture: delayed samples, no padded receiver evidence.
setup6GRSimToolkit('Verbose',false);
if nargin<1, mode="TDD"; end
file='lls_causal_access_to_data_wiring_tdd.yaml';
if string(mode)=="FDD", file='lls_causal_access_to_data_wiring.yaml'; end
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios',file));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
runtimeSlot=double(cfg.phy.trs.slotNumbers(1))+1;
p=sixgr.link.prepareTRSTransmission(cfg,12,'RuntimeSlot',runtimeSlot);
tx=p.Tx; strict=p.StrictConfig;
for delay=[0 17]
    % Deterministic delay-channel unit fixture, not a primary campaign row.
    x=[complex(zeros(delay,1));tx.Waveform];
    rx=struct('Waveform',[x (0.7+0.2i)*x], ...
        'NoiseVariance',0,'InjectedTimingOffset_samples',delay);
    timing=sixgr.phy.trs.estimateTRSTiming(rx,strict,tx);
    assert(all(timing.Table.TRSTimingEstimateAvailable));
    assert(all(timing.Table.EstimatedTimingOffset_samples==delay));
    det=sixgr.phy.trs.detectTRSResources(rx,strict,tx,'Timing',timing);
    assert(det.DetectionSuccess && all(det.Table.ReceivedSymbolCount==9));
    for k=1:numel(tx.SlotResources)
        a=det.Table.ReceiveStartSample1Based(k);
        b=det.Table.ReceiveEndSample1Based(k);
        assert(a==tx.SlotTable.StartSample1Based(k)+delay);
        assert(isequal(det.SlotDetections(k).CorrectedWaveform,rx.Waveform(a:b,:)));
        expected=nrOFDMDemodulate(tx.SlotResources(k).Carrier,rx.Waveform(a:b,:), ...
            'CyclicPrefixFraction',0.5);
        assert(isequal(det.SlotDetections(k).RxGrid,expected));
        assert(size(expected,3)==2);
    end
    channel=sixgr.phy.trs.estimateTRSChannel(rx,strict,tx,det);
    assert(channel.EstimateAvailable && channel.HestRxPorts==2);
    % A different receiver resource hypothesis owns its required window.
    % Do not silently crop it to the transmitter's earlier reference symbol.
    for lastSymbol=[9 10]
        hypothesis=strict;
        hypothesis.SymbolLocation=[lastSymbol-4 lastSymbol];
        hypothesis.ConfigHash=sixgr.phy.trs.hashTRSConfig(hypothesis);
        alternative=sixgr.phy.trs.detectTRSResources(rx,hypothesis,tx,'Timing',timing);
        assert(all(alternative.Table.ReceivedSymbolCount==lastSymbol+1));
    end
    invalid=rx;
    invalid.Waveform(det.Table.ReceiveEndSample1Based(end),2)=NaN;
    rejected=sixgr.phy.trs.detectTRSResources(invalid,strict,tx,'Timing',timing);
    assert(~rejected.Table.DetectionSuccess(end) && isnan(rejected.Table.DetectionMetric(end)));
    assert(isempty(rejected.SlotDetections(end).CorrectedWaveform));
    % Removing unused trailing symbols changes no reference measurement.
    clipped=rx;
    clipped.Waveform=rx.Waveform(1:det.Table.ReceiveEndSample1Based(end),:);
    exact=sixgr.phy.trs.detectTRSResources(clipped,strict,tx,'Timing',timing);
    assert(isequaln(exact,det));
    % One missing required sample cannot be replaced by padding.
    clipped.Waveform=clipped.Waveform(1:end-1,:);
    incomplete=sixgr.phy.trs.detectTRSResources(clipped,strict,tx,'Timing',timing);
    assert(~incomplete.DetectionSuccess && ~incomplete.Table.DetectionSuccess(end));
    assert(contains(incomplete.Table.Status(end),'IncompleteReceiveWindow'));
    assert(isempty(incomplete.SlotDetections(end).CorrectedWaveform));
    assert(isnan(incomplete.Table.DetectionMetric(end)));
    % Timing correlation itself must not silently shorten a declared slot.
    rejected=sixgr.phy.trs.estimateTRSTiming(clipped,strict,tx);
    assert(~rejected.Table.TRSTimingEstimateAvailable(end));
    assert(contains(rejected.Table.Status(end),'IncompleteTimingCapture'));
    for mutation=["missing","unavailable","nan","fractional","duplicate"]
        bad=timing;
        switch mutation
            case "missing", bad.Table=table();
            case "unavailable", bad.Table.TRSTimingEstimateAvailable(:)=false;
            case "nan", bad.Table.EstimatedTimingOffset_samples(:)=NaN;
            case "fractional", bad.Table.EstimatedTimingOffset_samples(:)=delay+0.5;
            case "duplicate", bad.Table=[bad.Table;bad.Table];
        end
        result=sixgr.phy.trs.detectTRSResources(rx,strict,tx,'Timing',bad);
        assert(~any(result.Table.DetectionSuccess) && all(isnan(result.Table.DetectionMetric)));
        assert(all(arrayfun(@(v)isempty(v.CorrectedWaveform),result.SlotDetections)));
    end
end
fprintf('TRS_ACTUAL_RECEIVE_WINDOW_PASS: %s; measured delay, exact samples, missing capture rejected.\n',mode);
ok=true;
end
