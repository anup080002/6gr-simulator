function ok=testCSIRSSSBPhysicalSeparation()
% Physical before/after replay of the inherited CSI-RS/SSB collision.
% The invalid baseline is deliberately generated with a Toolbox resource
% object; production scenario construction must reject that configuration.
setup6GRSimToolkit('Verbose',false);
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_rank2_shared_awgn_20db.yaml');
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
[ssb,ssbInfo]=sixgr.phy.dl.SSB_Tx(cfg,'NumSubframes',5);
assert(ssbInfo.SSBComposite.ComponentCount==4 && size(ssb,2)==4);
current=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,2);
carrier=sixgr.phy.grid.makeCarrier(current);
[~,~,info,resource]=sixgr.phy.refsig.csirs(carrier,current);
assert(resource.NumCSIRSPorts==4 && resource.SymbolLocations==6);
ofdm=nrOFDMInfo(carrier);
slotSamples=sum(ofdm.SymbolLengths(1:carrier.SymbolsPerSlot));
ssbSlot=ssb(slotSamples+(1:slotSamples),:);
basis=cfg.phy.csirs.precoderMatrices(:,:,1);
estimatedNoise=zeros(1,2);
for trial=1:2
    resource.SymbolLocations=4+trial; % Retained bad symbol 5; corrected 6.
    indices=nrCSIRSIndices(carrier,resource); symbols=nrCSIRS(carrier,resource);
    grid=nrResourceGrid(carrier,4); grid(indices)=symbols;
    physicalGrid=reshape(reshape(grid,[],4)*basis.',size(grid));
    waveform=nrOFDMModulate(carrier,physicalGrid,'Windowing',0);
    assert(isequal(size(waveform),size(ssbSlot)));
    [received,noise]=sixgr.phy.waveform.addOccupiedREAWGN( ...
        waveform+ssbSlot,carrier,20,'Seed',38214227,'SignalEnergyPerOccupiedRE',1);
    receivedGrid=nrOFDMDemodulate(carrier,received);
    [H,estimatedNoise(trial)]=nrChannelEstimate(carrier,receivedGrid, ...
        indices,symbols,'CDMLengths',info.Resources(1).CDMLengths);
    assert(all(isfinite(H(:))) && noise.RequestedEsN0_dB==20);
end
noiseError=10*log10(estimatedNoise(2)/noise.GridNoiseVariance);
assert(abs(noiseError)<3 && estimatedNoise(1)>4*estimatedNoise(2), ...
    'Separated pilots must recover injected noise; the retained collision must be reproduced.');
fprintf('CSI_SSB_PHYSICAL_SEPARATION_PASS bad_noise=%.12g fixed_noise=%.12g injected_noise=%.12g fixed_error_db=%.6g\n', ...
    estimatedNoise(1),estimatedNoise(2),noise.GridNoiseVariance,noiseError);
ok=true;
end
