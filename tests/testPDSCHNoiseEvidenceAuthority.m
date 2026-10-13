function ok = testPDSCHNoiseEvidenceAuthority()
% Noise-accounting regression, not BLER/100-MHz performance qualification.
% Use the 100-MHz clock and a bounded six-PRB allocation. The transmitted
% waveform is unchanged across the assumed-noise cases; no RX oracle input.
setup6GRSimToolkit('Verbose',false);
prior=rng; cleanup=onCleanup(@()rng(prior));
rng(89317,'twister');
cases=0;
for rankValue=[1 2]
    cfg=localConfig(rankValue);
    [tx,~]=sixgr.phy.dl.PDSCH_Tx(cfg,'NumTxAnt',rankValue, ...
        'PrecodingMatrix',eye(rankValue),'ExecutionProfile','phy_calibration');
    assert(tx.Carrier.NSizeGrid==273 && tx.Carrier.SubcarrierSpacing==30);
    transform=tx.OFDMInfo.SampleToGridNoiseVarianceGain;
    physicalGridNoise=.01;
    noise=sqrt(physicalGridNoise/(2*transform))* ...
        complex(randn(size(tx.Waveform)),randn(size(tx.Waveform)));
    received=.7*tx.Waveform+noise;
    for supplied={[],physicalGridNoise,.09}
        [rx,info]=sixgr.phy.dl.PDSCH_Rx(received,cfg, ...
            'Carrier',tx.Carrier,'PDSCH',tx.PDSCH, ...
            'PDSCHIndices',tx.PDSCHIndices,'CodingPlan',tx.CodingPlans, ...
            'ExecutionProfile','phy_calibration','NoiseVar',supplied{1}, ...
            'NoiseVarDomain','grid','PrecodingMatrix',eye(rankValue), ...
            'SkipTimingEstimate',true);
        if isempty(supplied{1})
            expected=rx.EstimatedNoiseVariance;
            source="canonical_pdsch_dmrs_channel_estimator";
        else
            expected=supplied{1};
            source="supplied_receiver_grid_noise_variance";
        end
        assert(rx.EqualizationInfo.PreEqualizationNoiseVariance==expected && ...
            rx.PreEqualizationNoiseVar==expected && ...
            rx.PreEqualizationNoiseVariance==expected && ...
            info.PreEqualizationNoiseVariance==expected, ...
            'test:PDSCHNoiseAuthorityMismatch', ...
            'The facade and exported source must match the executed equalizer noise, not another estimate.');
        assert(string(rx.PreEqualizationNoiseVarianceSource)==source && ...
            string(info.PreEqualizationNoiseVarianceSource)==source);
        assert(rx.MeasuredPreEqualizationNoiseVariance==rx.EstimatedNoiseVariance && ...
            info.MeasuredPreEqualizationNoiseVariance==rx.EstimatedNoiseVariance, ...
            'The independent DM-RS noise estimate must remain available separately.');
        assert(rx.MeasuredPreEqualizationNoiseVarianceSource=="pdsch_dmrs_channel_estimator" && ...
            info.MeasuredPreEqualizationNoiseVarianceSource=="pdsch_dmrs_channel_estimator");
        exported=sixgr.link.deriveMeasuredPHYEvidence(rx);
        assert(exported.MeasuredPreEqualizationNoiseVariance==rx.EstimatedNoiseVariance && ...
            exported.MeasuredPreEqualizationNoiseVarianceSource=="pdsch_dmrs_channel_estimator");
        if ~isempty(supplied{1}) && supplied{1}==.09
            assert(abs(rx.EstimatedNoiseVariance-expected)>.02, ...
                'The regression must actually separate measured and supplied noise.');
        end
        if rankValue==1
            % Existing scalar-AWGN reporting uses measured pilot noise for
            % SINR, even if the decoder is configured with another value.
            assert(rx.PostEqSINRScalarNoiseVariance==rx.EstimatedNoiseVariance && ...
                string(rx.PostEqSINRScalarNoiseVarianceSource)== ...
                    "canonical_pdsch_dmrs_channel_estimator");
        else
            assert(rx.PostEqSINRScalarNoiseVariance==expected && ...
                string(rx.PostEqSINRScalarNoiseVarianceSource)==source);
            eq=rx.EqualizationInfo.EqualizerResult;
            assert(eq.PreEqualizationNoiseVariance==expected);
            C=rx.EqualizationInfo.DisturbanceCovariance;
            assert(norm(C-expected*eye(rankValue),'fro')<1e-12);
            for re=1:eq.NRE
                W=reshape(eq.W(re,:,:),rankValue,rankValue);
                A=reshape(eq.EffectiveResponseWH(re,:,:),rankValue,rankValue);
                for layer=1:rankValue
                    other=setdiff(1:rankValue,layer);
                    denominator=sum(abs(A(layer,other)).^2)+ ...
                        real(W(layer,:)*C*W(layer,:)');
                    actual=1/eq.PostEqSINRLinear(re,layer);
                    assert(abs(denominator-actual)<1e-11*max(1,actual), ...
                        'The recorded SINR denominator must match the executed W, H and covariance.');
                end
            end
        end
        assert(string(rx.PostEqSINRModelScope)== ...
            "executed_equalizer_channel_and_disturbance_model_not_total_received_error");
        assert(rx.PostEqualizationNoiseVariance==rx.NoiseVarianceUsedForLLR);
        cases=cases+1;
    end
    if rankValue==1
        [oracle,oracleInfo]=sixgr.phy.dl.PDSCH_Rx(received,cfg, ...
            'Carrier',tx.Carrier,'PDSCH',tx.PDSCH, ...
            'PDSCHIndices',tx.PDSCHIndices,'CodingPlan',tx.CodingPlans, ...
            'ExecutionProfile','phy_calibration','NoiseVar',physicalGridNoise, ...
            'NoiseVarDomain','grid','PrecodingMatrix',1, ...
            'SkipTimingEstimate',true,'TrueChannel',.7*ones(273*12,14), ...
            'OracleTestMode',true);
        assert(isnan(oracle.MeasuredPreEqualizationNoiseVariance) && ...
            isnan(oracleInfo.MeasuredPreEqualizationNoiseVariance) && ...
            contains(oracle.MeasuredPreEqualizationNoiseVarianceSource,'oracle'), ...
            'Explicit perfect-CSI calibration must not label its supplied noise as measured.');
        cases=cases+1;
    end
end
fprintf('PDSCH_NOISE_AUTHORITY_PASS cases=%d measured_and_supplied_separate=1\n',cases);
ok=true;
end

function cfg=localConfig(rankValue)
cfg=sixgr.config.defaultConfig();
cfg.run.pdschExecutionProfile='phy_calibration';
cfg.phy.pdsch.executionProfile='phy_calibration';
cfg.phy.carrier.NSizeGrid=273; cfg.phy.carrier.SubcarrierSpacing=30;
cfg.phy.pdsch.PRBSet=0:5; cfg.phy.pdsch.prbSet=0:5;
cfg.phy.pdsch.SymbolAllocation=[2 10]; cfg.phy.pdsch.symbolAllocation=[2 10];
cfg.phy.pdsch.MappingType='A'; cfg.phy.pdsch.mappingType='A';
cfg.phy.pdsch.nLayers=rankValue; cfg.phy.pdsch.numLayers=rankValue;
cfg.phy.pdsch.mcsTable='qam64_table1'; cfg.phy.pdsch.mcsIndex=4;
cfg.phy.pdsch.modulation='QPSK'; cfg.phy.pdsch.codeRate=308/1024;
cfg.phy.pdsch.dmrs.additionalPositions=1;
cfg.phy.pdsch.UECapability1024QAM=false; cfg.phy.pdsch.RRCEnabled1024QAM=false;
cfg.phy.pdsch.DCIEnabled1024QAM=false; cfg.phy.pdsch.DeploymentAllows1024QAM=false;
cfg.phy.pdsch.FrequencyRangeAllows1024QAM=false; cfg.phy.pdsch.BandAllows1024QAM=false;
cfg.phy.pdsch.FrequencyRange='FR1'; cfg.phy.pdsch.OperatingBand='n77';
cfg.phy.pdsch.DeploymentClass='macro'; cfg.phy.pdsch.DCIFormat='1_1';
cfg.phy.csirs.enable=false; cfg.phy.csirs.enabled=false;
cfg.phy.ssb.enable=false; cfg.phy.ptrs.enable=false;
cfg.phy.pdsch.enablePTRS=false; cfg.phy.pdsch.ptrs.enableCPECorrection=false;
cfg.phy.pdsch.measurements.dmrsResidualPostEqSINRBoundEnabled=false;
cfg.phy.pdsch.measurements.decisionDirectedPostEqSINRBoundEnabled=false;
cfg.channel.model='AWGN'; cfg.channel.awgnOnly=true;
cfg.phy.rx.useIdealTimingSync=false; cfg.phy.rx.cfoCorrectionEnabled=false;
cfg.outputs.saveCSV=false; cfg.outputs.saveMAT=false; cfg.outputs.saveFigures=false;
end
