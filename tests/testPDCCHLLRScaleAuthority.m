function ok=testPDCCHLLRScaleAuthority()
% Deterministic PDCCH receiver algebra, NOT RF/fading or BLER qualification.
% Scaling received signal AND noise together must not change LLR reliability
% after re-estimating H and N0. Compare to the native MMSE CSI convention.
setup6GRSimToolkit('Verbose',false);
policy=sixgr.lls6g.config.readConfigFile( ...
    'simulator/configs/validation/h4_100_installed_pdcch_development.yaml');
source=sixgr.lls6g.config.loadScenarioConfig(policy.scenario_path);
folder=fullfile(pwd,'results','diagnostics','pdcch_llr_scale', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
assert(~isfolder(folder)); mkdir(folder);
cfg=sixgr.lls6g.buildInternalConfig(source,folder);
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,policy.absolute_slot0+1);
context=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg,'1_1');
schema=sixgr.phy.pdcch.DCISchemaEngine.resolve(context);
fields=struct();
for def=schema.Definitions(:).', fields.(def.Name)=def.ValueMin; end
authored=sixgr.phy.pdcch.DCIPacker.pack(fields,context);
p=sixgr.link.preparePDCCHTransmission(cfg,'DCIBits',authored.Bits,'RNTI',context.Data.RNTIValue);
carrier=sixgr.phy.grid.makeCarrier(cfg);
[input,~]=sixgr.phy.waveform.addOccupiedREAWGN(p.TransmitSamples,carrier,cfg.channel.snr_dB, ...
    'Seed',policy.cases(2).noise_seed,'SignalEnergyPerOccupiedRE',sixgr.link.resolveAWGNReferenceEnergy(cfg));
baseline=[]; rows=table();
for scale=[0.1 1 10] % Algebraic gain transforms, not PHY operating points.
    [rx,info]=sixgr.phy.dl.PDCCH_Rx(scale*input,cfg,'SampleRate_Hz',p.SampleRateHz);
    assert(rx.Ok && isequal(rx.DCIBits,authored.Bits),'test:PDCCHAlgebraDecode');
    [symbols,h]=nrExtractResources(rx.MonitoredDataREIndices,rx.RxGrid,rx.ChannelEstimate);
    [equalized,csi]=nrEqualizeMMSE(symbols,h,rx.NoiseVar);
    raw=nrPDCCHDecode(equalized,info.PDCCHScramblingID,info.PDCCHScramblingRNTI,rx.NoiseVar);
    expected=raw.*repelem(csi,2);
    relative=norm(double(rx.DecoderLLRs(:)-expected(:)))/max(norm(double(expected(:))),eps);
    row=table(scale,rx.NoiseVar,mean(csi),mean(abs(rx.DecoderLLRs)),mean(abs(expected)),relative, ...
        'VariableNames',{'AlgebraicSampleGain','MeasuredNoiseVariance','MeanNativeCSI', ...
        'DecoderMeanAbsLLR','NativeReferenceMeanAbsLLR','RelativeLLRError'});
    rows=[rows;row]; %#ok<AGROW>
    sixgr.util.csvWriteTable(fullfile(folder,'llr_algebra.csv'),rows,'PreserveSchema',true);
    assert(relative<1e-12,'test:PDCCHLLRScaleMismatch', ...
        'Production LLRs differ from native MMSE CSI weighting by %.9g; meanCSI %.9g.',relative,mean(csi));
    if isempty(baseline), baseline=rx.DecoderLLRs;
    else
        assert(norm(double(rx.DecoderLLRs-baseline))/norm(double(baseline))<1e-8, ...
            'test:PDCCHLLRNotGainInvariant','Common input gain changed information reliability.');
    end
end
fprintf('PDCCH_LLR_SCALE_AUTHORITY_PASS folder=%s scope=receiver_algebra_not_RF_qualification\n',folder);
ok=true;
end
