function ok=testPilotChannelPhaseEvolution()
% Algebraic boundary test, not qualification of mobility/Doppler spread.
carrier=nrCarrierConfig('NSizeGrid',25,'SubcarrierSpacing',15);
K=300; L=14; R=2; P=2;
ofdm=nrOFDMInfo(carrier); ofdm.CyclicPrefixFraction=.5;
times=localTimes(carrier,ofdm);
pilotSymbols=[3 8 12]; mask=false(K,L,P); mask(:,pilotSymbols,:)=true;
indices=find(mask); symbols=ones(size(indices));
% Exactly cancelling frequency and RX phases must not erase the channel.
base=reshape((-1).^(0:K-1),K,1,1,1).*reshape([1 -1],1,1,R,1).* ...
    reshape([1 1i],1,1,1,P);
for rate=[-175 0 125]
    h=base.*reshape(exp(2i*pi*rate*times),1,L,1,1);
    actual=sixgr.phy.rx.pilotChannelPhaseEvolution(carrier,h,indices,symbols,ofdm);
    assert(abs(mean(h,'all'))<1e-12,'Fixture must expose coherent-averaging cancellation.');
    assert(abs(actual.CommonPhaseRate_Hz-rate)<1e-10 && actual.PhaseFitResidualRMS_deg<1e-9);
    assert(actual.PairCount==2 && actual.MatchedChannelValueCount==2*K*R*P);
    changed=sixgr.phy.rx.pilotChannelPhaseEvolution(carrier, ...
        .03i*h(:,:,[2 1],[2 1]),indices,symbols,ofdm);
    assert(abs(changed.CommonPhaseRate_Hz-rate)<1e-10);
    assert(actual.UnaliasedHalfWidth_Hz>abs(rate));
    unavailable=h; unavailable(:,1,:,:)=NaN;
    outside=sixgr.phy.rx.pilotChannelPhaseEvolution(carrier,unavailable,indices,symbols,ofdm);
    assert(isequaln(outside,actual),'Unobserved nonpilot resources must not change the measurement.');
    unavailable(1,3,1,1)=NaN; caught=false;
    try, sixgr.phy.rx.pilotChannelPhaseEvolution(carrier,unavailable,indices,symbols,ofdm);
    catch ex, caught=strcmp(ex.identifier,'sixgr:phy:rx:InvalidPilotPhaseChannel'); end
    assert(caught,'Do not discard an invalid observed pilot.');
end
one=false(K,L,P); one(:,3,:)=true;
a=sixgr.phy.rx.pilotChannelPhaseEvolution(carrier,h,find(one),ones(nnz(one),1),ofdm);
assert(isnan(a.CommonPhaseRate_Hz) && a.PairCount==0);
two=one; two(:,8,:)=true;
a=sixgr.phy.rx.pilotChannelPhaseEvolution(carrier,h,find(two),ones(nnz(two),1),ofdm);
assert(abs(a.CommonPhaseRate_Hz-rate)<1e-10 && isnan(a.PhaseFitResidualRMS_deg));
% Hopping with no repeated subcarriers cannot establish a temporal phase.
hopping=false(K,L,P); hopping(1:150,3,:)=true; hopping(151:300,8,:)=true;
a=sixgr.phy.rx.pilotChannelPhaseEvolution(carrier,h,find(hopping),ones(nnz(hopping),1),ofdm);
assert(isnan(a.CommonPhaseRate_Hz) && a.PairCount==0);
cases=0;
for scs=[15 30 60 120]
    for slot=[0 1 3]
        for fraction=[.25 .5 1]
            c=nrCarrierConfig('NSizeGrid',25,'SubcarrierSpacing',scs,'NSlot',slot);
            info=nrOFDMInfo(c); info.CyclicPrefixFraction=fraction;
            t=localTimes(c,info); observed=base.*reshape(exp(2i*pi*125*t),1,L,1,1);
            selected=false(K,L,P); selected(:,[1 8 12],:)=true;
            a=sixgr.phy.rx.pilotChannelPhaseEvolution(c,observed,find(selected),ones(nnz(selected),1),info);
            assert(abs(a.CommonPhaseRate_Hz-125)<1e-9);
            cases=cases+1;
        end
    end
end
fprintf('PILOT_CHANNEL_PHASE_EVOLUTION_PASS no_spatial_frequency_cancellation=1 no_doppler_spread_claim=1\n');
fprintf('PILOT_PHASE_OFDM_CLOCK_PASS cases=%d actual_slot_CP_and_FFT_fraction=1\n',cases);
ok=true;
end

function times=localTimes(carrier,info)
first=mod(carrier.NSlot,info.SlotsPerSubframe)*carrier.SymbolsPerSlot;
cp=double(info.CyclicPrefixLengths(first+(1:carrier.SymbolsPerSlot)));
cursor=0; times=zeros(size(cp));
for i=1:numel(cp)
    samples=cursor+floor(cp(i)*info.CyclicPrefixFraction)+(0:info.Nfft-1);
    times(i)=mean(samples)/(info.Nfft*carrier.SubcarrierSpacing*1000);
    cursor=cursor+cp(i)+info.Nfft;
end
end
