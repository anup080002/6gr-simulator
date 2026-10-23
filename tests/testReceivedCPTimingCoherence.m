function ok=testReceivedCPTimingCoherence()
% Compare the production prefix-sum implementation against direct actual
% sample-pair arithmetic. OFDM boundaries/CFO are fixture inputs, not receiver
% inputs. No fading, noise statistics or hardware qualification is claimed.
setup6GRSimToolkit('Verbose',false);
rng(91842);
carrier=nrCarrierConfig('NSizeGrid',24,'SubcarrierSpacing',30,'NSlot',1);
grid=nrResourceGrid(carrier,2);
grid(:)=nrSymbolModulate(randi([0 1],2*numel(grid),1),'QPSK');
[wave,ofdm]=nrOFDMModulate(carrier,grid,'Windowing',0);
positions=14+(1:14); prefix=double(ofdm.CyclicPrefixLengths(positions));
nfft=double(ofdm.Nfft); offsets=(0:180).';
for delay=[0 13 129]
    capture=[zeros(delay,2);wave;zeros(180-delay,2)];
    for frequency=[0 2100]
        rx=capture.*exp(2i*pi*frequency*(0:size(capture,1)-1).'/ofdm.SampleRate);
        [coherence,evidence]=sixgr.phy.sync.receivedCPTimingCoherence(carrier,rx,offsets);
        expected=zeros(size(offsets));
        for k=1:numel(offsets)
            a=0; b=0; c=complex(0); start=offsets(k);
            for lengthCP=prefix(:).'
                first=rx(start+(1:lengthCP),:);
                second=rx(start+nfft+(1:lengthCP),:);
                a=a+sum(abs(first).^2,'all'); b=b+sum(abs(second).^2,'all');
                c=c+sum(conj(first).*second,'all');
                start=start+nfft+lengthCP;
            end
            if a>0 && b>0, expected(k)=min(1,abs(c/sqrt(a)/sqrt(b))^2); end
        end
        assert(max(abs(coherence-expected))<2e-12);
        assert(coherence(delay+1)>1-2e-12 && ...
            evidence.SamplePairCount==2*sum(prefix) && ...
            evidence.HypothesisCount==numel(offsets) && ...
            ~evidence.OracleTimingUsed && ~evidence.ReceiverZeroPaddingUsed);
    end
end
zero=sixgr.phy.sync.receivedCPTimingCoherence(carrier,zeros(size(capture)),offsets);
assert(all(zero==0),'An empty-energy capture must not create timing support.');
try
    sixgr.phy.sync.receivedCPTimingCoherence(carrier,capture(1:end-1,:),offsets);
    error('test:ExpectedFailure','Incomplete actual samples must be rejected.');
catch cause
    assert(strcmp(cause.identifier,'sixgr:phy:sync:IncompleteCPTimingObservation'));
end
fprintf('RECEIVED_CP_TIMING_COHERENCE_PASS delays=3 frequencies=2 direct_arithmetic=1\n');
ok=true;
end
