function ok=testSRSConfiguredUECompositeReception()
% Actual composite OFDM reception with independently configured UE pilots.
% Aligned flat-channel engineering regression, not timing/statistical or
% network qualification. Channel and noise truth enter scoring only.
setup6GRSimToolkit('Verbose',false);
cfg=sixgr.config.defaultConfig();
cfg.phy.carrier=struct('NSizeGrid',25,'NStartGrid',0,'SubcarrierSpacing',15,'NCellID',1);
cfg.phy.numerology.scs_kHz=15; cfg.phy.duplex.mode='FDD';
cfg.channel.model='AWGN';
cfg.phy.srs=struct('enable',true,'nPorts',2,'period_slots',5,'period_offset',0, ...
    'slotNumbers',0,'CSRS',6,'BSRS',0,'BHop',0,'bandwidthRB',24,'expectedNumRB',24, ...
    'SymbolStart',11,'NumSRSSymbols',1,'KTC',2,'KBarTC',0,'CyclicShift',0, ...
    'NSRSID',1,'resourceSetUsage','codebook','runtimeChannelEstimator','nr_channel_estimate');
fragment=sixgr.lls6g.config.readConfigFile( ...
    'simulator/configs/validation/srs_two_ue_frequency_bindings.yaml');
cfg=sixgr.util.mergeStruct(cfg,fragment);
% The same fixed matrices and same independent noise realization are used
% in every population. No channel/noise values are passed to SRS_Rx.
channel={ [.8 .2i;-.1 .9], [.6i .3;.2 .7i] };
variance=1e-4; stream=RandStream('mt19937ar','Seed',5100531);
noise=sqrt(variance/2)*(randn(stream,300,14,2)+1i*randn(stream,300,14,2));
folder=fullfile(pwd,'results','lls','srs_configured_multiue_reception', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(folder); rows=struct([]);
for population=["single_ue","configured_disjoint_combs","configured_collision"]
    source=cfg;
    if population=="configured_collision"
        source.phy.srs.ueResourceBindings(2).comb_offset=0;
    end
    count=2; if population=="single_ue", count=1; end
    tx=cell(1,count); receiveCfg=cell(1,count); references=cell(1,count);
    composite=complex(zeros(300,14,2));
    for u=1:count
        receiveCfg{u}=sixgr.phy.srs.bindConfiguredUEFrequencyResource(source,u,4659+u,1);
        references{u}=sixgr.phy.srs.buildSRSConfigFromScenario(receiveCfg{u});
        s=references{u}; carrier=s.ToolboxCarrier;
        g=nrResourceGrid(carrier,2);
        g(nrSRSIndices(carrier,s.ToolboxSRS))=nrSRS(carrier,s.ToolboxSRS);
        tx{u}=g;
        composite=composite+reshape(reshape(g,[],2)*channel{u},300,14,2);
    end
    waveform=nrOFDMModulate(carrier,composite+noise,'Windowing',0);
    for u=1:count
        % No alternate UE reference or transmitted samples enter this RX.
        [rx,info]=sixgr.phy.ul.SRS_Rx(waveform,receiveCfg{u}, ...
            'Carrier',carrier,'SRS',references{u}.ToolboxSRS);
        expected=repmat(reshape(channel{u}.',1,1,2,2),300,14,1,1);
        score=sixgr.phy.srs.pilotChannelNMSE(rx.Hest,expected,rx.SRSIndices);
        row=struct('Population',population,'UEIndex',u,'NumUsers',count, ...
            'ChannelNMSE_dB',score.dB,'DeclaredNoiseVarianceScoringOnly',variance, ...
            'MeasuredNoiseVariance',rx.NoiseVar,'NoiseError_dB',10*log10(rx.NoiseVar/variance), ...
            'NoiseSource',string(rx.NoiseVarSource), ...
            'Scope',"controlled_composite_OFDM_receiver_regression_not_network_qualification");
        rows=[rows;row]; %#ok<AGROW>
        save(fullfile(folder,sprintf('%s_ue%d.mat',population,u)), ...
            'source','waveform','rx','info','score','variance','channel');
    end
end
T=struct2table(rows); writetable(T,fullfile(folder,'receiver_accuracy.csv'));
disp(T); fprintf('SRS_CONFIGURED_MULTIUE_RECEIVER_EVIDENCE=%s\n',folder);
separable=T.Population~="configured_collision";
assert(all(isfinite(T.ChannelNMSE_dB(separable)) & T.ChannelNMSE_dB(separable)<-20), ...
    'test:SRSConfiguredMultiUEChannel', ...
    'Installed separated pilots must recover the desired channel; inspect %s.',folder);
assert(all(isfinite(T.NoiseError_dB(separable)) & abs(T.NoiseError_dB(separable))<3), ...
    'test:SRSConfiguredMultiUENoise', ...
    'Other UEs on separated combs must not become desired-pilot noise; inspect %s.',folder);
assert(all(T.ChannelNMSE_dB(~separable)>-6), ...
    'test:SRSConfiguredCollisionHidden','Identical simultaneous pilots must expose contamination.');
ok=true;
end
