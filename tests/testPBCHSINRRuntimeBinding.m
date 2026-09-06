function ok = testPBCHSINRRuntimeBinding()
% Actual receiver values survive the runtime/export adapter unchanged.
setup6GRSimToolkit('Verbose',false);
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
[pbch,~] = sixgr.phy.dl.PBCH_Recovery(grid,sync,cfg);
assert(pbch.Ok && pbch.ChannelEstimateAvailable && pbch.EqualizationAvailable);
template = struct('ChannelEstimateAvailable',pbch.ChannelEstimateAvailable, ...
    'EqualizationAvailable',pbch.EqualizationAvailable);
row = sixgr.truth.bindPBCHReceiverSINREvidence(template,struct(),pbch);
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
assert(isnan(absent.MeasuredSINR_dB) && ~absent.ReceiverHestSINRApplicable && ...
    ~absent.PostEqSINRAvailable && ~absent.PostEqSINRReceiverDerived);
ok = true;
disp('PBCH_SINR_RUNTIME_BINDING_PASS');
end
