function ok=testConfiguredAWGNReferenceEnergy()
% Receiver noise authority, not throughput or control integration acceptance.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
base=sixgr.config.defaultConfig();
base.channel.model='AWGN'; base.channel.awgnOnly=true;
base.channel.pathlossEnabled=false; base.channel.shadowFadingEnabled=false;
base.run.noiseOperatingMode='standalone_awgn_snr_argument';
base.channel.snr_dB=30;
assert(sixgr.link.resolveAWGNReferenceEnergy(base)==1);
legacy=base; legacy.channel=rmfield(legacy.channel,'awgnReferenceREEnergy');
assert(sixgr.link.resolveAWGNReferenceEnergy(legacy)==1);
for value={0,-1,NaN,Inf,[],[1 2],1i,true}
    bad=base; bad.channel.awgnReferenceREEnergy=value{1};
    reject(@()sixgr.link.resolveAWGNReferenceEnergy(bad));
end
profiles=[25 15 2.35e9;264 120 7e9];
for p=1:size(profiles,1)
    cfg=base;
    cfg.phy.carrier.NSizeGrid=profiles(p,1);
    cfg.phy.carrier.SubcarrierSpacing=profiles(p,2);
    cfg.phy.carrier.SubcarrierSpacing_kHz=profiles(p,2);
    cfg.phy.fc_Hz=profiles(p,3);
    carrier=sixgr.phy.grid.makeCarrier(cfg);
    info=nrOFDMInfo(carrier);
    count=sum(info.SymbolLengths(1:14));
    [unit,ru]=noise(cfg,info.SampleRate,[0 count]);
    cfg.channel.awgnReferenceREEnergy=.25;
    [quarter,rq]=noise(cfg,info.SampleRate,[0 count]);
    [split,rs]=noise(cfg,info.SampleRate,[0 1 337 count]);
    assert(isequal(quarter,unit*.5) && isequal(split,quarter));
    assert(rq.InjectedNoiseVariance==ru.InjectedNoiseVariance*.25 && ...
        rq.GridNoiseVariance==.25*10^(-30/10) && ...
        rq.SignalEnergyPerOccupiedRE==.25 && rs.NoiseStreamSeed==ru.NoiseStreamSeed);
    assert(rq.SharedNoiseCalibrationSource== ...
        "fixed_once_from_configured_occupied_re_energy_and_canonical_ofdm_noise_transform");
    grid=nrOFDMDemodulate(carrier,quarter);
    measured=mean(abs(grid(:)).^2);
    assert(abs(measured/rq.GridNoiseVariance-1)<.06, ...
        'Executed OFDM noise does not match configured RE variance.');
    % Rank is not allowed to recalibrate the fixed four-port receiver noise.
    cfg.phy.nLayers=2;
    [rank2,r2]=noise(cfg,info.SampleRate,[0 count]);
    cfg.phy.nLayers=4;
    [rank4,r4]=noise(cfg,info.SampleRate,[0 count]);
    assert(isequal(rank2,rank4) && r2.InjectedNoiseVariance==r4.InjectedNoiseVariance);
    fprintf('CONFIGURED_AWGN_REFERENCE_PROFILE_PASS PRB=%d SCS=%g Fs=%g measuredGridVariance=%.12g configured=%.12g\n', ...
        profiles(p,1),profiles(p,2),info.SampleRate,measured,rq.GridNoiseVariance);
end
ok=true;
fprintf('CONFIGURED_AWGN_REFERENCE_ENERGY_PASS bandwidths=5MHz,400MHz varianceRatio=0.25 delta_dB=6.020599913 splitClockExact=1\n');
end

function [samples,replay]=noise(cfg,fs,bounds)
owner=sixgr.truth.SharedWaveformPhysicalRuntime(fs,0,1);
owner.addTransmitter('silent',cfg,'DL',4,false);
owner.addReceiver('ue',cfg,'DL',4,false);
chunks=cell(1,numel(bounds)-1);
for k=1:numel(chunks)
    input=struct('ID',"silent",'Chunk',sixgr.phy.waveform.WaveformChunk( ...
        complex(zeros(bounds(k+1)-bounds(k),4)),bounds(k)));
    [output,execution]=owner.process(input,bounds(k),bounds(k+1),[]);
    selected=output(string({output.ID})=="ue:pre_rf");
    chunks{k}=selected.Chunk.Samples;
    replay=execution.RX.Replay;
end
samples=vertcat(chunks{:});
end

function reject(action)
try
    action();
catch ME
    assert(strcmp(ME.identifier,'sixgr:link:InvalidAWGNReferenceEnergy'), ...
        'Unexpected rejection: %s',ME.identifier);
    return;
end
error('test:ExpectedRejection','Invalid reference energy was accepted.');
end
