function ok=testPDCCHPerResourceChannel()
% Deterministic receiver mathematics, not statistical fading qualification.
setup6GRSimToolkit('Verbose',false);
previousRNG=rng;
restoreRNG=onCleanup(@()rng(previousRNG)); %#ok<NASGU>
rng(728,'twister');
K=288; L=14; nRx=2;
[sc,sym]=ndgrid((0:K-1)',0:1);
locations=table(sc(:),sym(:),ones(numel(sc),1),ones(numel(sc),1), ...
    'VariableNames',{'Subcarrier','Symbol','SlotIndex','CopyIndex'});
pilots=ismember(mod(locations.Subcarrier,12),[0 4 8]);
dmrs=struct('Locations',locations(pilots,:), ...
    'Symbols',repmat((1+1i)/sqrt(2),sum(pilots),1));
payload=locations(~pilots,:);
grid=complex(zeros(K,L));
pilotIndex=sub2ind([K L],locations.Subcarrier(pilots)+1,locations.Symbol(pilots)+1);
dataIndex=sub2ind([K L],payload.Subcarrier+1,payload.Symbol+1);
symbols=nrSymbolModulate(randi([0 1],2*numel(dataIndex),1),'QPSK');
grid(pilotIndex)=dmrs.Symbols; grid(dataIndex)=symbols;
frequency=(0:K-1)'/K;
H=[(1+.2*cos(2*pi*frequency)).*exp(1i*2*pi*frequency), ...
    (.7+.1*sin(2*pi*frequency)).*exp(-1i*pi*frequency)];
received=grid.*reshape(H,K,1,nRx);
cfg=struct('ChannelModel','TDL-C','CyclicPrefix','normal');
est=sixgr.ctrl.PDCCHChannelEstimator(received,dmrs,cfg,1,[],payload);
assert(isequal(size(est.HData),[height(payload) nRx]) && ...
    std(real(est.HData(:,1)))>.3 && ...
    est.ChannelEstimateSource=="received_dmrs_nrChannelEstimate_per_resource", ...
    'Fading estimation must preserve RE-dependent responses on each receive branch.');
reference=complex(zeros(K,L)); reference(pilotIndex)=dmrs.Symbols;
[native,nVar]=nrChannelEstimate(received,reference,'CDMLengths',[1 1],'CyclicPrefix','normal');
native=reshape(native,K*L,nRx);
assert(isequal(est.HData,native(dataIndex,:)) && isequal(est.NoiseVar,nVar), ...
    'Production payload extraction and noise must match the executed native estimator.');
% Execute an actual sample-filtered channel too: the study runner's
% equivalent scalar-fading branch is not physical fading qualification.
carrier=nrCarrierConfig('NSizeGrid',K/12,'SubcarrierSpacing',30);
[wave,ofdm]=nrOFDMModulate(carrier,grid,'Windowing',0);
channel=nrTDLChannel('DelayProfile','TDL-C','DelaySpread',300e-9, ...
    'MaximumDopplerShift',0,'SampleRate',ofdm.SampleRate, ...
    'NumTransmitAntennas',1,'NumReceiveAntennas',nRx,'Seed',731);
ci=info(channel); trim=ci.ChannelFilterDelay;
padding=trim+ceil(max(ci.PathDelays)*ofdm.SampleRate);
filtered=channel([wave;zeros(padding,1)]);
captured=nrOFDMDemodulate(carrier,filtered(trim+(1:size(wave,1)),:));
physical=sixgr.ctrl.PDCCHChannelEstimator(captured,dmrs,cfg,1,[],payload);
assert(all(isfinite(physical.HData(:))) && std(real(physical.HData(:,1)))>.01, ...
    'Sample-filtered TDL-C must retain its received frequency-selective estimates.');
% Independent equalizer algebra: distinct channels on every RE/branch.
hData=H(payload.Subcarrier+1,:);
nVar=.02;
rx=symbols.*hData;
for mode=["ZF","MMSE"]
    eq=sixgr.ctrl.PDCCHEqualizer(rx,hData,nVar,mode);
    expectedNoise=nVar./sum(abs(hData).^2,2);
    assert(max(abs(eq.Symbols-symbols))<1e-12 && ...
        max(abs(eq.PostEqualizationNoiseVariance-expectedNoise))<1e-12);
    assert(abs(eq.EstimatedSINR_dB-10*log10(mean(1./expectedNoise)))<1e-12);
end
one=sixgr.ctrl.PDCCHEqualizer(rx(1,:),hData(1,:),nVar,'MMSE');
assert(isscalar(one.Symbols) && abs(one.Symbols-symbols(1))<1e-12, ...
    'A single RE with two antennas must not become two single-antenna REs.');
try
    sixgr.ctrl.PDCCHEqualizer(rx,mean(hData,1),nVar,'MMSE');
    error('test:MissingRejection','A burst-wide mean must not replace per-RE estimates.');
catch cause
    assert(strcmp(cause.identifier,'sixgr:ctrl:PDCCHEqualizer:ChannelDimensions'));
end
cfg.ChannelModel='AWGN';
flat=sixgr.ctrl.PDCCHChannelEstimator(received,dmrs,cfg,1,[],payload);
assert(flat.ChannelEstimateSource=="received_dmrs_flat_awgn" && ...
    all(flat.HData==flat.HData(1,:),'all'));
decoder=struct('Modulation','QPSK','PayloadScramblingEnabled',false, ...
    'PayloadSequenceInit',0,'PayloadLengthBits',32,'CRCPolynomial','24C', ...
    'PolarListLength',8,'CRCScramblingEnabled',false);
observed=symbols(1:108); variances=linspace(.01,.2,numel(observed))';
decoded=sixgr.ctrl.PDCCHDecoder(observed,variances,struct(),decoder,struct());
expectedLLR=zeros(2*numel(observed),1);
for k=1:numel(observed)
    expectedLLR(2*k-1:2*k)=nrSymbolDemodulate(observed(k),'QPSK',variances(k));
end
assert(max(abs(decoded.LLR-expectedLLR))<1e-10, ...
    'Each QPSK bit must use its own propagated complex noise variance.');
fprintf('PDCCH_PER_RESOURCE_CHANNEL_PASS native_mapping=1 noise_propagation=1 dimension_rejection=1 qualification=component_only\n');
ok=true;
end
