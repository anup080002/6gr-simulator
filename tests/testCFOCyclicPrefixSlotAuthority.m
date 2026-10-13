function ok = testCFOCyclicPrefixSlotAuthority()
% CP correlation must use the captured slot, not subframe-start CP lengths.
% No propagation model, decoder target or injected-CFO metadata is supplied
% to the estimator. The only frequency information is in received samples.
setup6GRSimToolkit('Verbose',false);
assert(exist('nrOFDMInfo','file')==2 && exist('nrOFDMModulate','file')==2, ...
    'sixgr:test:Missing5GToolbox','Physical OFDM clock verification requires 5G Toolbox.');
stream=RandStream('mt19937ar','Seed',104031);
cases={15,'normal';30,'normal';60,'normal';120,'normal';60,'extended'};
checked=0;
for caseIndex=1:size(cases,1)
    carrier=nrCarrierConfig('NSizeGrid',25, ...
        'SubcarrierSpacing',cases{caseIndex,1}, ...
        'CyclicPrefix',cases{caseIndex,2});
    for slot=0:double(carrier.SlotsPerSubframe)-1
        carrier.NSlot=slot;
        dims=[12*double(carrier.NSizeGrid),double(carrier.SymbolsPerSlot),2];
        grid=((2*randi(stream,[0 1],dims)-1)+ ...
            1i*(2*randi(stream,[0 1],dims)-1))/sqrt(2);
        [waveform,txInfo]=sixgr.phy.waveform.ofdmModulate(carrier,grid,'Windowing',0);
        [~,rxInfo]=sixgr.phy.waveform.ofdmDemodulate(carrier,waveform);
        directInfo=nrOFDMInfo(carrier,'Nfft',txInfo.Nfft,'Windowing',0);
        positions=mod(slot,double(carrier.SlotsPerSubframe))* ...
            double(carrier.SymbolsPerSlot)+(1:double(carrier.SymbolsPerSlot));
        slotCP=double(directInfo.CyclicPrefixLengths(positions));
        assert(size(waveform,1)==sum(slotCP+double(directInfo.Nfft)), ...
            'Independent Toolbox CP schedule must describe the actual waveform.');
        % CSI-RS already passes explicitly selected slot CP metadata. Keep
        % that legitimate direct-Toolbox form working too.
        explicitSlotInfo=directInfo;
        explicitSlotInfo.CyclicPrefixLengths=slotCP;
        fs=double(txInfo.SampleRate);
        for frequency=[0 -700 430]
            received=waveform.*exp(1i*2*pi*frequency*(0:size(waveform,1)-1).'/fs);
            authorities={txInfo,rxInfo,explicitSlotInfo};
            for authorityIndex=1:numel(authorities)
                [estimated,evidence]=sixgr.phy.rx.estimateCFOFromCyclicPrefix( ...
                    received,authorities{authorityIndex},fs);
                assert(evidence.EstimateAvailable && isfinite(estimated), ...
                    'Captured-slot CP evidence must produce an estimate.');
                assert(abs(estimated-frequency)<1e-6, ...
                    'sixgr:test:WrongCFOCapturedSlot', ...
                    'SCS=%g CP=%s NSlot=%d metadata=%d: CFO=%g, expected=%g Hz.', ...
                    carrier.SubcarrierSpacing,carrier.CyclicPrefix,slot, ...
                    authorityIndex,estimated,frequency);
                assert(evidence.NumSymbolsUsed==carrier.SymbolsPerSlot, ...
                    'All and only the captured slot symbols must be correlated.');
                checked=checked+1;
            end
        end
    end
end

% Ambiguous full-subframe metadata cannot silently assert that an arbitrary
% received slot starts at subframe symbol zero. Canonical metadata above has
% the exact resolved per-slot vector; direct callers can supply that vector.
carrier=nrCarrierConfig('NSizeGrid',25,'SubcarrierSpacing',120,'NSlot',1);
grid=complex(randn(stream,300,14),randn(stream,300,14));
[waveform,info]=sixgr.phy.waveform.ofdmModulate(carrier,grid,'Windowing',0);
ambiguous=nrOFDMInfo(carrier,'Nfft',info.Nfft,'Windowing',0);
localUnavailable(waveform,ambiguous,info.SampleRate, ...
    'Full-subframe metadata without captured-slot authority');

bad=info;
bad.OFDMSamplingResolution.SampleRateHz=2*info.SampleRate;
localUnavailable(waveform,bad,info.SampleRate,'Inconsistent canonical sample clocks');
bad=info;
bad.OFDMSamplingResolution.Nfft=2*info.Nfft;
localUnavailable(waveform,bad,info.SampleRate,'Inconsistent canonical FFT lengths');
bad=info;
bad.OFDMSamplingResolution.CyclicPrefixLengthsPerSlot(2)=0;
localUnavailable(waveform,bad,info.SampleRate,'Invalid CP entry must not be removed');
localUnavailable(waveform,info,2*info.SampleRate,'Wrong supplied sample clock');
localUnavailable(zeros(size(waveform)),info,info.SampleRate,'Zero-energy capture');

fprintf('CP_SLOT_AUTHORITY_PASS estimates=%d negative_checks=6\n',checked);
ok=true;
end

function localUnavailable(waveform,info,fs,label)
[estimate,evidence]=sixgr.phy.rx.estimateCFOFromCyclicPrefix(waveform,info,fs);
assert(~evidence.EstimateAvailable && isnan(estimate), ...
    'sixgr:test:CFOInvalidClockAccepted','%s must not yield a CFO estimate.',label);
assert(strlength(string(evidence.Status))>0 && string(evidence.Status)~="OK", ...
    'Unavailable CFO evidence must retain an explicit diagnostic reason.');
end
