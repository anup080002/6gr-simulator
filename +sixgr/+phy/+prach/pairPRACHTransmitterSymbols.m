function pairs=pairPRACHTransmitterSymbols(tx,prepared,observation)
% Post-execution TX EVM on native PRACH resources, not receiver detection EVM.
% The public NR modulator supplies a configuration-only unit-tone transform
% reference. It fixes PRACH frequency placement, symbol phase and gain; no
% parameter is fitted to received or impaired samples and RF is not replayed.
assert(observation.isComplete() && observation.SampleRateHz==prepared.SampleRate_Hz, ...
    'sixgr:prach:TXEVMClock','PRACH scoring requires the actual complete TX observation.');
mask=prepared.TransmitPortResourceGrid~=0;
K=size(mask,1); L=size(mask,2); P=size(mask,3);
basisGrid=complex(zeros(K,L)); basisGrid(1,:)=1;
[basis,info]=nrPRACHOFDMModulate(tx.Carrier,tx.PRACH,basisGrid,'Windowing',0);
assert(info.SampleRate==prepared.SampleRate_Hz && info.Windowing==0 && ...
    numel(info.SymbolLengths)==L && size(prepared.PhysicalWaveform,2)==P && ...
    observation.NumReceiveAntennas==P, ...
    'sixgr:prach:TXEVMLayout','Retain native PRACH numerology and physical TX mapping.');
origin=prepared.StartTime_s*prepared.SampleRate_Hz;
assert(abs(origin-round(origin))<1e-7,'sixgr:prach:TXEVMClock','TX origin must lie on the sample clock.');
origin=round(origin);
actual=observation.readComplete();
referenceGrid=complex(zeros(K,L,P)); measuredGrid=referenceGrid;
cursor=double(info.OffsetLength);
for symbol=1:L
    local=cursor+double(info.CyclicPrefixLengths(symbol))+(1:double(info.Nfft));
    cursor=cursor+double(info.SymbolLengths(symbol));
    if ~any(mask(:,symbol,:),'all'), continue; end
    observed=origin+local-observation.StartSample;
    assert(min(observed)>=1 && max(observed)<=size(actual,1) && max(local)<=size(prepared.PhysicalWaveform,1), ...
        'sixgr:prach:TXEVMIncomplete','Never pad an unobserved PRACH useful symbol.');
    tone=basis(local,1);
    assert(all(isfinite(tone)) && all(abs(tone)>0) && ...
        max(abs(abs(tone)/abs(tone(1))-1))<1e-10, ...
        'sixgr:prach:TXEVMTransform','The configuration-only transform basis must be a constant-modulus tone.');
    % Division removes only the known, unit-input modulator basis. Both
    % operands undergo the same fixed transform, so RF gain/phase errors stay.
    r=fft(prepared.PhysicalWaveform(local,:)./tone,[],1)/double(info.Nfft);
    m=fft(actual(observed,:)./tone,[],1)/double(info.Nfft);
    referenceGrid(:,symbol,:)=reshape(r(1:K,:),K,1,P);
    measuredGrid(:,symbol,:)=reshape(m(1:K,:),K,1,P);
end
pairs=struct([]);
for port=1:P
    indices=find(mask(:,:,port));
    if isempty(indices), continue; end
    r=referenceGrid(:,:,port); m=measuredGrid(:,:,port);
    entry=struct('SignalName',"PRACH",'PortIndex',port-1, ...
        'PortRole',"physical_TX_antenna_not_equalized_RX_stream", ...
        'ObservationID',"transmitted_PRACH_"+string(origin), ...
        'SampleIndex',double(indices(:)-1),'ReferenceReal',real(r(indices)), ...
        'ReferenceImag',imag(r(indices)),'MeasuredReal',real(m(indices)), ...
        'MeasuredImag',imag(m(indices)), ...
        'EVMDefinition',"reference_normalized_paired_symbol_evm", ...
        'AlignmentSource',"frozen_transmitter_OFDM_clock_no_gain_phase_or_timing_fit", ...
        'ReferenceSource',"actual_pre_TX_RF_waveform_on_declared_resource_clock", ...
        'MeasurementDomain',"transmitter_resource_elements", ...
        'ReceiverUsesScoringReference',false,'GainOrPhaseFitted',false);
    if isempty(pairs), pairs=entry; else, pairs(end+1)=entry; end %#ok<AGROW>
end
end
