function ok=testOFDMCalibrationSampleCounts()
% Independently check one-slot counts against actual waveform length and
% TS 38.211 normal/extended-CP timing, not against the DUT count helper.
setup6GRSimToolkit('Verbose',false);
% Exact requested 4 GHz / 100 MHz grid; RF carrier does not change CP counts.
c=nrCarrierConfig('NSizeGrid',273,'SubcarrierSpacing',30,'NSlot',1);
localCheckNative(c,{'Nfft',4096,'SampleRate',122.88e6,'Windowing',0});
cases=[15 0 0;30 0 0;30 1 8;60 0 0;60 1 8;120 0 8;120 1 0;120 4 8;120 7 0;60 1 0];
for k=1:size(cases,1)
    scs=cases(k,1); slot=cases(k,2); window=cases(k,3);
    cp='normal'; if k==size(cases,1), cp='extended'; end
    c=nrCarrierConfig('NSizeGrid',12,'SubcarrierSpacing',scs,'NSlot',slot,'CyclicPrefix',cp);
    localCheckNative(c,{'Windowing',window});
end
% Resampled waveform coordinates must not be combined with native IFFT
% sample counts. Keep the native partition and disclose output applicability.
c=nrCarrierConfig('NSizeGrid',12,'SubcarrierSpacing',30,'NSlot',1);
for window=[0 8]
    args={'Nfft',1024,'SampleRate',50e6,'Windowing',window};
    [w,info]=nrOFDMModulate(c,zeros(144,14),args{:});
    cal=sixgr.phy.waveform.calibrateOFDMNoiseTransform(c,args{:},'NumNoiseRE',65536,'UseCache',false);
    assert(cal.TotalSampleCount==size(w,1) && cal.TotalSampleCount==25000);
    assert(cal.NativeUsefulSampleCount==14336 && cal.NativeCyclicPrefixSampleCount==1024 && ...
        cal.NativeTotalSampleCount==15360 && cal.NativeSampleRate==30.72e6);
    assert(isnan(cal.UsefulSampleCount) && isnan(cal.CyclicPrefixSampleCount) && ...
        string(cal.SamplePartitionStatus)=="unavailable_partition_at_resampled_waveform_clock");
    assert(isequal(cal.SubframeCyclicPrefixLengths,info.CyclicPrefixLengths));
    assert(cal.ImpulseProbeSampleIndex>=1 && cal.ImpulseProbeSampleIndex<=size(w,1));
end
fprintf('OFDM_CALIBRATION_SAMPLE_COUNTS_PASS native_cases=11 resampled_cases=2\n');
ok=true;
end

function localCheckNative(c,args)
grid=exp(1i*reshape(1:(12*c.NSizeGrid*c.SymbolsPerSlot),12*c.NSizeGrid,c.SymbolsPerSlot)/17);
[wave,info]=nrOFDMModulate(c,grid,args{:});
cal=sixgr.phy.waveform.calibrateOFDMNoiseTransform(c,args{:},'NumNoiseRE',65536,'UseCache',false);
useful=c.SymbolsPerSlot*info.Nfft;
assert(cal.UsefulSampleCount==useful && cal.CyclicPrefixSampleCount==size(wave,1)-useful, ...
    'sixgr:test:WrongSlotCPCount', ...
    'SCS=%g slot=%g: useful=%g (expected %g), CP=%g, actual waveform=%g.', ...
    c.SubcarrierSpacing,c.NSlot,cal.UsefulSampleCount,useful,cal.CyclicPrefixSampleCount,size(wave,1));
mu=log2(c.SubcarrierSpacing/15);
symbols=mod(c.NSlot,c.SlotsPerSubframe)*c.SymbolsPerSlot+(0:c.SymbolsPerSlot-1);
if string(c.CyclicPrefix)=="extended"
    expectedCP=repmat(info.Nfft/4,1,12);
else
    expectedCP=repmat(info.Nfft*144/2048,1,14);
    expectedCP(symbols==0 | symbols==7*2^mu)=info.Nfft*144/2048+info.Nfft*2^mu/128;
end
assert(isequal(cal.CyclicPrefixLengths,expectedCP) && ...
    isequal(cal.SymbolLengths,info.Nfft+expectedCP));
assert(cal.TotalSampleCount==cal.UsefulSampleCount+cal.CyclicPrefixSampleCount && ...
    cal.TotalSampleCount==size(wave,1) && cal.NativeTotalSampleCount==size(wave,1));
assert(cal.NativeSampleRate==info.SampleRate && cal.SlotInSubframe0Based==mod(c.NSlot,c.SlotsPerSubframe));
assert(string(cal.SamplePartitionStatus)=="exact_native_sample_clock");
assert(abs(cal.CyclicPrefixOverheadFraction-sum(expectedCP)/size(wave,1))<eps);
assert(cal.ModDemodReconstructionMaxAbsError<1e-11);
end
