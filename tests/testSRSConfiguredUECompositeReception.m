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
baseChannel={ [.8 .2i;-.1 .9], [.6i .3;.2 .7i] };
% Keep the original two-port regression and exercise the port count used by
% the target rank-two scenario. Rank two alone does not imply two SRS ports.
target=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_rank2_shared_awgn_20db.yaml');
targetData=target.toStruct();
portCounts=unique([cfg.phy.srs.nPorts targetData.reference_signals.srs.num_ports]);
variance=1e-4;
folder=fullfile(pwd,'results','lls','srs_configured_multiue_reception', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(folder); rows=struct([]);
for ports=reshape(portCounts,1,[])
    cfg.phy.srs.nPorts=ports;
    channel=cellfun(@(h)kron(eye(ports/size(h,1)),h),baseChannel, ...
        'UniformOutput',false);
    stream=RandStream('mt19937ar','Seed',5100531);
    noise=sqrt(variance/2)*(randn(stream,300,14,ports)+1i*randn(stream,300,14,ports));
for population=["single_ue","configured_disjoint_combs","configured_collision"]
    source=cfg;
    if population=="configured_collision"
        source.phy.srs.ueResourceBindings(2).comb_offset=0;
    end
    count=2; if population=="single_ue", count=1; end
    tx=cell(1,count); receiveCfg=cell(1,count); references=cell(1,count);
    composite=complex(zeros(300,14,ports));
    for u=1:count
        receiveCfg{u}=sixgr.phy.srs.bindConfiguredUEFrequencyResource(source,u,4659+u,1);
        references{u}=sixgr.phy.srs.buildSRSConfigFromScenario(receiveCfg{u});
        s=references{u}; carrier=s.ToolboxCarrier;
        g=nrResourceGrid(carrier,ports);
        g(nrSRSIndices(carrier,s.ToolboxSRS))=nrSRS(carrier,s.ToolboxSRS);
        tx{u}=g;
        composite=composite+reshape(reshape(g,[],ports)*channel{u},300,14,ports);
    end
    overlap=0;
    if count==2
        % Inspect the actual native port-expanded mapping, not the declared
        % comb offsets. Four-port cyclic shifts can change that mapping.
        occupied1=any(abs(tx{1})>0,3);
        occupied2=any(abs(tx{2})>0,3);
        overlap=nnz(occupied1 & occupied2);
        if population=="configured_disjoint_combs"
            assert(overlap==0,'test:SRSConfiguredCombOverlap', ...
                'Declared disjoint resources overlap after native SRS port expansion.');
        else
            assert(overlap>0,'test:MissingSRSPhysicalCollision', ...
                'The negative population must physically overlap on transmitted REs.');
        end
    end
    waveform=nrOFDMModulate(carrier,composite+noise,'Windowing',0);
    for u=1:count
        % No alternate UE reference or transmitted samples enter this RX.
        [rx,info]=sixgr.phy.ul.SRS_Rx(waveform,receiveCfg{u}, ...
            'Carrier',carrier,'SRS',references{u}.ToolboxSRS);
        if population=="configured_disjoint_combs"
            assert(info.ChannelEstimation.NullREDisturbance.SampleCount==0 && ...
                string(rx.NoiseVarSource)=="received_srs_channel_estimator_residual", ...
                'Configured UE pilots must not be used as null-RE noise samples.');
        end
        expected=repmat(reshape(channel{u}.',1,1,ports,ports),300,14,1,1);
        score=sixgr.phy.srs.pilotChannelNMSE(rx.Hest,expected,rx.SRSIndices);
        row=struct('Population',population,'UEIndex',u,'NumUsers',count, ...
            'NumSRSPorts',ports,'NumReceiveAntennas',ports,'PhysicalOverlapRECount',overlap, ...
            'ChannelNMSE_dB',score.dB,'DeclaredNoiseVarianceScoringOnly',variance, ...
            'MeasuredNoiseVariance',rx.NoiseVar,'NoiseError_dB',10*log10(rx.NoiseVar/variance), ...
            'NoiseSource',string(rx.NoiseVarSource), ...
            'Scope',"controlled_composite_OFDM_receiver_regression_not_network_qualification");
        rows=[rows;row]; %#ok<AGROW>
        save(fullfile(folder,sprintf('%s_ports%d_ue%d.mat',population,ports,u)), ...
            'source','waveform','rx','info','score','variance','channel');
    end
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
