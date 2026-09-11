function ok=testReceivedFFTChannelDiagonal
% Independent basis-waveform test of the retained linear operator, not KPI data.
carrier=nrCarrierConfig('NSizeGrid',6,'SubcarrierSpacing',30,'NSlot',3);
info=nrOFDMInfo(carrier,'Windowing',0);
N=info.Nfft; K=72; L=3; R=2; T=2;
% Obtain CP lengths on this slot's actual modulation clock.
[~,modinfo]=nrOFDMModulate(carrier,zeros(K,L),'Windowing',0);
cp=double(modinfo.SymbolLengths(1:L))-N;
M=sum(cp+N)+30;
filters=zeros(18,2); filters(2,1)=0.8; filters(18,2)=0.4;
gains=complex(zeros(M,2,T,R));
for t=1:T
    for r=1:R
        gains(:,:,t,r)=exp(1i*(0:M-1).'*(0.004*t+0.002*r))* ...
            [(0.8+0.1i*r) (0.2-0.3i*t)];
    end
end
for offset=[0 7 20]
    for fraction=[0 0.5 1]
        actual=sixgr.truth.receivedFFTChannelDiagonal(gains,filters,N,cp,K,offset,fraction);
        for t=1:T
            for l=1:L
                for bin=[1 25 K]
                    grid=zeros(K,L); grid(bin,l)=1;
                    tx=nrOFDMModulate(carrier,grid,'Windowing',0);
                    tx=[tx;zeros(M-size(tx,1),1)]; % Explicit test input, not RX padding.
                    rx=complex(zeros(M,R));
                    for p=1:2
                        filtered=filter(filters(:,p),1,tx);
                        for r=1:R
                            rx(:,r)=rx(:,r)+filtered.*gains(:,p,t,r);
                        end
                    end
                    got=nrOFDMDemodulate(carrier,rx(offset+(1:sum(cp+N)),:), ...
                        'CyclicPrefixFraction',fraction);
                    expected=reshape(actual(bin,l,:,t),1,[]);
                    measured=reshape(got(bin,l,:),1,[]);
                    assert(max(abs(expected-measured))<1e-10, ...
                        'FFT diagonal differs from actual basis-waveform filtering.');
                end
            end
        end
    end
end
try
    sixgr.truth.receivedFFTChannelDiagonal(gains(1:10,:,:,:),filters,N,cp,K,0,0.5);
    error('test:MissingFailure','Missing snapshots were accepted.');
catch ME
    assert(strcmp(ME.identifier,'sixgr:truth:IncompleteFFTChannelReference'));
end
fprintf('RECEIVED_FFT_CHANNEL_DIAGONAL_PASS: time-varying MIMO, partial slots, CP/ISI, measured offsets.\n');
ok=true;
end
