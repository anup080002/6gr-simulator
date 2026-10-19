function ok = testPBCHSINRRuntimeBinding()
% Actual receiver values survive the runtime/export adapter unchanged.
setup6GRSimToolkit('Verbose',false);
collectorSource=fileread(which('sixgr.truth.runWaveformLinkBundle'));
assert(~contains(collectorSource,'r.DetectionMetric = 1;'), ...
    'A successful PBCH CRC must not replace the measured detector correlation by one.');
assert(exist('nrWaveformGenerator','file')==2, ...
    'The actual PBCH waveform backend is required for this regression.');
cfg = sixgr.config.defaultConfig();
cfg.run.strictMode = true;
cfg.phy.carrier.NCellID = 17;
cfg.phy.carrier.SubcarrierSpacing = 30;
cfg.phy.carrier.SubcarrierSpacing_kHz = 30;
cfg.phy.carrier.NSizeGrid = 51;
cfg.phy.channelBandwidth_MHz = 20;
cfg.frequency.bandwidth_hz = 20e6;
[carrier,~] = sixgr.phy.grid.makeCarrier(cfg);
[tx,~,info] = sixgr.phy.dl.SSB_Tx(cfg,'NumSubframes',5,'SSBIndex',0);
rx = sixgr.conformance.addReferenceNoise(tx,carrier,12, ...
    'Seed',88012,'SignalEnergyPerOccupiedRE',1);
[grid,sync] = sixgr.phy.dl.SSB_Rx(rx,cfg,'SampleRate_Hz',info.SampleRate_Hz);
assert(sync.CFOCorrectionEnabled && sync.CFOCorrectionApplied && sync.TimingEstimateUsed && ...
    sync.CFOCorrectionApplied_Hz==sync.FreqOffset_Hz && ...
    sync.AppliedTimingCorrection_samples==max(0,sync.RawTimingEstimate_samples), ...
    'Applied receiver synchronization must not be exported as disabled/unused.');
[pbch,~] = sixgr.phy.dl.PBCH_Recovery(grid,sync,cfg);
assert(pbch.Ok && pbch.ChannelEstimateAvailable && pbch.EqualizationAvailable);
symbols=pbch.EqualizedSymbols(:);
reference=complex(2*(real(symbols)>=0)-1,2*(imag(symbols)>=0)-1)/sqrt(2);
assert(pbch.EVMSymbolCount==numel(symbols) && pbch.EVMSymbolCount==432);
assert(abs(pbch.EVMErrorEnergy-sum(abs(symbols-reference).^2))<1e-12 && ...
    abs(pbch.EVMReferenceEnergy-sum(abs(reference).^2))<1e-12);
assert(abs(pbch.EVM_rms-sqrt(pbch.EVMErrorEnergy/pbch.EVMReferenceEnergy))<1e-14);
template = struct('ChannelEstimateAvailable',pbch.ChannelEstimateAvailable, ...
    'EqualizationAvailable',pbch.EqualizationAvailable);
row = sixgr.truth.bindPBCHReceiverSINREvidence(template,struct(),pbch);
for name=["EVMErrorEnergy","EVMReferenceEnergy","EVMSymbolCount", ...
        "EVMEnergyUnit","EVMComputationDomain"]
    assert(isequaln(row.(name),pbch.(name)));
end
assert(row.NoiseVariance==pbch.PreEqualizationNoiseVariance && ...
    row.NoiseVarianceSource==pbch.PreEqualizationNoiseVarianceSource && ...
    row.NoiseVarianceDomain==pbch.PreEqualizationNoiseVarianceDomain);
assert(row.ReceiverHestSINRApplicable && row.PostEqSINRAvailable && ...
    row.PostEqSINRReceiverDerived);
for metric = ["ReceiverHestSINR","MeasuredTrialSINR","PostEqSINR"]
    for suffix = ["_dB","Source","ValueRole","ValueStatus","NAReason"]
        field = metric+suffix;
        assert(isequaln(row.(field),pbch.(field)), ...
            'Runtime adapter changed receiver evidence %s.',field);
    end
end
T = struct2table(row,'AsArray',true);
T = sixgr.truth.fillBlankCategoricalColumns(T,'pbch');
T = sixgr.truth.canonicalizeLLSLiveSignalChainTable('pbch_trials',T);
assert(T.PostEqSINRNAReason=="" && T.ReceiverHestSINRNAReason=="" && ...
    T.MeasuredTrialSINRNAReason=="", ...
    'A successful measurement must not acquire a fabricated unavailable reason.');
% Preserve an explicitly unavailable/contradictory receiver result. A
% finite number must not override the receiver's own availability flag.
rejected = pbch;
rejected.PostEqSINRAvailable = false;
rejected.PostEqSINRNAReason = "receiver_rejected_observation";
bad = sixgr.truth.bindPBCHReceiverSINREvidence(template,rejected,pbch);
assert(~bad.PostEqSINRAvailable && ~bad.PostEqSINRReceiverDerived && ...
    bad.PostEqSINRNAReason==rejected.PostEqSINRNAReason);
emptyTemplate = struct('ChannelEstimateAvailable',false,'EqualizationAvailable',false);
absent = sixgr.truth.bindPBCHReceiverSINREvidence(emptyTemplate,struct(),struct());
assert(isnan(absent.EVMErrorEnergy) && isnan(absent.EVMSymbolCount) && ...
    isnan(absent.NoiseVariance) && absent.NoiseVarianceSource=="");
assert(isnan(absent.MeasuredSINR_dB) && ~absent.ReceiverHestSINRApplicable && ...
    ~absent.PostEqSINRAvailable && ~absent.PostEqSINRReceiverDerived);
ok = true;
disp('PBCH_SINR_RUNTIME_BINDING_PASS');
end
