function ok=testPUSCHNoiseEvidenceAuthority()
% Bounded waveform regression at 100-MHz numerology, not BLER qualification.
% Compare measured DM-RS noise with different supplied equalizer variances
% on exactly the same received waveform, including compact RX output.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
prior=rng; cleanup=onCleanup(@()rng(prior));
rng(91826,'twister');
cases=0;
for rankValue=[1 2 4]
    cfg=localConfig(rankValue);
    [tx,~]=sixgr.phy.ul.PUSCH_Tx(cfg,'CompactOutput',false);
    assert(tx.Carrier.NSizeGrid==273 && tx.Carrier.SubcarrierSpacing==30);
    assert(size(tx.Waveform,2)==rankValue);
    transform=tx.OFDMInfo.SampleToGridNoiseVarianceGain;
    trueGridNoise=.01;
    actualNoise=sqrt(trueGridNoise/(2*transform))* ...
        complex(randn(size(tx.Waveform)),randn(size(tx.Waveform)));
    received=.7*tx.Waveform+actualNoise;
    firstEstimate=NaN;
    for compact=[false true]
        for supplied={[],trueGridNoise,.09}
            [rx,info]=localReceive(received,cfg,tx,supplied{1},compact);
            measured=double(info.ChannelEstimation.NoiseVar);
            assert(isfinite(measured)&&measured>=0);
            if isnan(firstEstimate), firstEstimate=measured; end
            assert(abs(measured-firstEstimate)<1e-12, ...
                'Supplied equalizer noise must not overwrite the independent DM-RS estimate.');
            if isempty(supplied{1})
                expected=measured; source="runtime_channel_estimate";
            else
                expected=supplied{1}; source="runtime_metadata";
            end
            assert(rx.NoiseVar==expected && rx.PreEqualizationNoiseVariance==expected && ...
                string(rx.PreEqualizationNoiseVarianceSource)==source);
            assert(rx.MeasuredPreEqualizationNoiseVariance==measured && ...
                rx.MeasuredPreEqualizationNoiseVarianceSource=="pusch_dmrs_channel_estimator");
            assert(rx.PostEqSINRScalarNoiseVariance==expected && ...
                rx.PostEqSINRScalarNoiseVarianceSource==source && ...
                rx.PostEqSINRModelScope== ...
                "executed_equalizer_channel_and_disturbance_model_not_total_received_error");
            if ~isempty(supplied{1}) && supplied{1}==.09
                assert(abs(measured-expected)>.02, ...
                    'The waveform must separate measured and supplied noise for this regression.');
            end
            exported=sixgr.link.deriveMeasuredPHYEvidence(rx);
            assert(exported.MeasuredPreEqualizationNoiseVariance==measured && ...
                exported.MeasuredPreEqualizationNoiseVarianceSource== ...
                "pusch_dmrs_channel_estimator");
            eq=info.Equalizer.EqualizerResult;
            assert(eq.PreEqualizationNoiseVariance==expected);
            assert(max(abs(rx.PostEqSINRRawEqualizerPerLayer_dB- ...
                mean(eq.PostEqSINRPerRE_dB,1)))<1e-10, ...
                'Noise provenance must retain, not recompute, executed raw SINR.');
            cases=cases+1;
        end
    end
    if rankValue==1
        % Explicit oracle shortcuts may execute as labelled component tests,
        % but their configured nVar is not a receiver-noise measurement.
        [shortcut,~]=localReceive(received,cfg,tx,.09,false,'FastAWGNPath',true);
        assert(isnan(shortcut.MeasuredPreEqualizationNoiseVariance) && ...
            contains(shortcut.MeasuredPreEqualizationNoiseVarianceSource,'unit_awgn'));
        cfgOracle=cfg; cfgOracle.phy.channelEstimation.method='ideal';
        trueChannel=.7*ones(273*12,14);
        [oracle,~]=localReceive(received,cfgOracle,tx,.09,false, ...
            'TrueChannel',trueChannel,'OracleTestMode',true);
        assert(isnan(oracle.MeasuredPreEqualizationNoiseVariance) && ...
            contains(oracle.MeasuredPreEqualizationNoiseVarianceSource,'oracle'));
        % Invalid input in non-strict mode must leave decoding unavailable,
        % while retaining the pilot measurement that ran before that gate.
        [unavailable,unavailableInfo]=localReceive(received,cfg,tx,NaN,false, ...
            'StrictNoiseVarianceRequired',false);
        assert(~unavailable.EqualizationAttempted && ~unavailable.DecodeAttempted && ...
            unavailable.MeasuredPreEqualizationNoiseVariance== ...
            unavailableInfo.ChannelEstimation.NoiseVar);
        cases=cases+3;
    end
end
fprintf('PUSCH_NOISE_AUTHORITY_PASS receiver_cases=%d no_performance_claim=1\n',cases);
ok=true;
end

function [rx,info]=localReceive(waveform,cfg,tx,noise,compact,varargin)
[rx,info]=sixgr.phy.ul.PUSCH_Rx(waveform,cfg, ...
    'Carrier',tx.Carrier,'PUSCH',tx.PUSCH,'PUSCHIndices',tx.PUSCHIndices, ...
    'TransportBlockSize',tx.TransportBlockSize,'TargetCodeRate',tx.TargetCodeRate, ...
    'RV',tx.RV,'NoiseVar',noise,'NoiseVarDomain','grid', ...
    'CodingLayout',tx.CodingLayout,'CompactOutput',compact, ...
    'SkipTimingEstimate',true,varargin{:});
end

function cfg=localConfig(rankValue)
cfg=sixgr.config.defaultConfig();
cfg.run.strictMode=true; cfg.run.noProxyTruthContract=true;
cfg.run.strictNoiseVarianceRequired=true;
cfg.outputs.saveCSV=false; cfg.outputs.saveMAT=false; cfg.outputs.saveFigures=false;
cfg.channel.model='AWGN'; cfg.channel.awgnOnly=true;
cfg.phy.nTxAnt=rankValue; cfg.phy.nRxAnt=rankValue;
cfg.channel.nTxAnt=rankValue; cfg.channel.nRxAnt=rankValue;
cfg.scenario.ue.nTxAnt=rankValue; cfg.antenna.ue.numElements=rankValue;
cfg.phy.carrier.NSizeGrid=273; cfg.phy.carrier.SubcarrierSpacing=30;
cfg.phy.pusch.prbSet=0:5; cfg.phy.pusch.symbolAllocation=[0 10];
cfg.phy.pusch.modulation='QPSK'; cfg.phy.pusch.codeRate=308/1024;
cfg.phy.pusch.mcsTable='qam64_table1'; cfg.phy.pusch.mcsIndex=4;
cfg.phy.pusch.numLayers=rankValue; cfg.phy.pusch.nLayers=rankValue;
cfg.phy.pusch.numAntennaPorts=rankValue; cfg.phy.pusch.numPorts=rankValue;
cfg.phy.pusch.dmrs.portSet=0:rankValue-1;
cfg.phy.pusch.dmrs.DMRSPortSet=0:rankValue-1;
cfg.phy.pusch.transmissionScheme='codebook'; cfg.phy.pusch.transformPrecoding=false;
if rankValue==1, cfg.phy.pusch.transmissionScheme='nonCodebook'; end
cfg.phy.pusch.TPMI=0; cfg.phy.pusch.PMI=0;
cfg.phy.pusch.enablePTRS=false; cfg.phy.pusch.ptrs.enableCPECorrection=false;
cfg.phy.pusch.equalizer='MMSE'; cfg.phy.channelEstimation.method='LS';
cfg.phy.rx.cfoCorrectionEnabled=false;
end
