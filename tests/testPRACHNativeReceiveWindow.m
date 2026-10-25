function testPRACHNativeReceiveWindow()
% Native configured RO -> receive geometry plus generated TX support check.
% No channel/RF/gNB detector or shared monitoring is executed.
setup6GRSimToolkit('Verbose',false);
checked=0;
for index=[0 16 157]
    scs=1.25; if index==157, scs=30; end
    n=sixgr.phy.frame.PRACHOccasionResolver.resolve('FrequencyRange','FR1', ...
        'DuplexMode','TDD','ConfigurationIndex',index,'CarrierSubcarrierSpacingKHz',30, ...
        'NSizeGrid',51,'PRACHSubcarrierSpacingKHz',scs);
    assert(n.CarrierCyclicPrefix=="normal");
    for k=1:height(n.Occasions)
        row=n.Occasions(k,:);
        c=nrCarrierConfig('SubcarrierSpacing',30,'NSizeGrid',51, ...
            'NFrame',row.Frame,'NSlot',row.SlotWithinFrame);
        p=nrPRACHConfig('DuplexMode','TDD','ConfigurationIndex',index, ...
            'SubcarrierSpacing',scs,'NPRACHSlot',row.PRACHSlot, ...
            'ActivePRACHSlot',row.ActivePRACHSlot,'TimeIndex',row.TimeIndex,'FrequencyIndex',row.FrequencyIndex);
        before=p;
        t=sixgr.rach.prachSampleTiming(c,p);
        g=nrPRACHGrid(c,p); g(nrPRACHIndices(c,p))=nrPRACH(c,p);
        [w,oi]=nrPRACHOFDMModulate(c,p,g,'Windowing',0);
        nz=find(any(abs(w)>0,2)); tc=int64(double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond)/oi.SampleRate);
        assert(isequal(p,before) && ~isempty(nz));
        assert(t.ActiveStartTicks==t.WaveformStartTicks+int64(nz(1)-1)*tc && ...
            t.ActiveEndTicksExclusive==t.WaveformStartTicks+int64(nz(end))*tc && ...
            t.WaveformEndTicksExclusive==t.WaveformStartTicks+int64(size(w,1))*tc);
        assert(row.AbsoluteSlot==t.CarrierSlot0 && row.StartSymbol==t.CarrierStartSymbol && ...
            row.DurationSymbols==t.CarrierDurationSymbols && row.PRACHActiveStartTicks==t.ActiveStartTicks);
        clock=struct('CellID',1,'ConfigurationEpoch',1,'SampleRateHz',oi.SampleRate, ...
            'RadioFrameZeroSample',0,'ConfigurationAvailableAtSample',0, ...
            'TimingAdvanceOffsetPresent',true,'TimingAdvanceOffset',"n0", ...
            'SearchGuardSamples',16,'FilterTailSamples',11,'NumReceiveAntennas',64,'ULCarrierID',0);
        a=sixgr.phy.ra.planPRACHReceiveWindow(n,k,clock);
        assert(a.NominalWaveformEndSampleExclusive-a.NominalWaveformStartSample==size(w,1));
        assert(a.ReceiveEndSampleExclusive-a.ReceiveStartSample==size(w,1)+43);
        assert(isequal(a.CandidatePreambles0,0:63) && ~a.ReceiverArmed && ~a.WaveformExecuted);
        checked=checked+1;
    end
end
fprintf('PRACH_NATIVE_RECEIVE_WINDOW_PASS native_generated_support=%d gNB_detector=0 shared_monitor=0\n',checked);
end
