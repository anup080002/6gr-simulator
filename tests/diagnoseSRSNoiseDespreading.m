function outputRoot=diagnoseSRSNoiseDespreading()
% Controlled AWGN estimator diagnostic, not primary runtime measurements.
% Compare native estimation with/without explicit cyclic-shift despreading.
% The known noise and identity channel are scoring inputs only.
setup6GRSimToolkit('Verbose',false);
source=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_tdd_5mhz_four_port_shared_awgn_12db.yaml'));
outputRoot=fullfile('results','lls','srs_noise_despreading', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(outputRoot);
cfg=sixgr.lls6g.buildInternalConfig(source,outputRoot);
assert(strcmpi(cfg.channel.model,'AWGN'));
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,5);
carrier=sixgr.phy.grid.makeCarrier(cfg);
strict=sixgr.phy.srs.buildSRSConfigFromScenario(cfg);
originalRNG=rng; cleanup=onCleanup(@()rng(originalRNG)); %#ok<NASGU>
rng(double(cfg.run.seed),'twister');
% This experiment's declared grid variance uses the scenario reference,
% not a measured/estimated variance fed back into the receiver.
referenceEnergy=sixgr.link.resolveAWGNReferenceEnergy(cfg);
variance=referenceEnergy/10^(double(cfg.channel.snr_dB)/10);
rows=struct([]); captures=cell(0,1);
for ports=[1 2 4]
    srs=strict.ToolboxSRS; srs.NumSRSPorts=ports;
    [indices,indexInfo]=nrSRSIndices(carrier,srs);
    symbols=nrSRS(carrier,srs);
    assert(~isempty(indices),'Diagnostic must select an actual SRS occasion.');
    transmitted=nrResourceGrid(carrier,ports);
    transmitted(indices)=symbols;
    noise=sqrt(variance/2)*(randn(size(transmitted))+1i*randn(size(transmitted)));
    received=transmitted+noise;
    truth=complex(zeros(size(received,1),size(received,2),ports,ports));
    for port=1:ports, truth(:,:,port,port)=1; end
    for fdCDM=unique([1 ports])
        [estimated,estimatedNoise,info]=nrChannelEstimate(carrier,received,indices,symbols, ...
            'CDMLengths',[fdCDM 1],'AveragingWindow',[0 0]);
        score=sixgr.phy.srs.pilotChannelNMSE(estimated,truth,indices);
        row=struct('Ports',ports,'FDCDMLength',fdCDM, ...
            'DeclaredGridNoiseVariance',variance,'EstimatedGridNoiseVariance',double(estimatedNoise), ...
            'NoiseEstimateError_dB',10*log10(double(estimatedNoise)/variance), ...
            'PilotChannelNMSE_dB',10*log10(score.Linear), ...
            'Source',"controlled_identity_AWGN_estimator_diagnostic_not_normal_runtime");
        rows=[rows;row]; %#ok<AGROW>
        captures{end+1}=struct('Carrier',carrier,'SRS',srs,'Indices',indices, ...
            'IndexInfo',indexInfo,'Symbols',symbols,'ReceivedGrid',received, ...
            'EstimatedChannel',estimated,'EstimatorInfo',info,'Score',score); %#ok<AGROW>
    end
end
results=struct2table(rows);
writetable(results,fullfile(outputRoot,'noise_despreading.csv'));
save(fullfile(outputRoot,'noise_despreading.mat'),'cfg','results','captures','variance');
disp(results);
% Separate algebraic check: SRS per-port pilot SNR is not automatically
% PUSCH per-layer SINR after a unit-total-power multilayer precoder.
% Use an exact declared identity channel, not a fabricated runtime Hest.
ports=4;
identity=complex(zeros(size(received,1),size(received,2),ports,ports));
for port=1:ports, identity(:,:,port,port)=1; end
raw=sixgr.phy.ul.estimateSRSRITPMI(identity,variance,cfg);
pilotSNR=10*log10(1/variance);
anchored=sixgr.phy.ul.estimateSRSRITPMI(identity,variance,cfg, ...
    'AbsoluteSINRAnchor_dB',pilotSNR, ...
    'AbsoluteSINRAnchorSource','measured_ul_srs_pilot_reconstruction_sinr', ...
    'AbsoluteSINRAnchorPowerReferencePlane','receiver_srs_resource_elements_after_ofdm_demodulation');
native=nrPUSCHCodebook(raw.RI,ports,raw.TPMI,false);
projection=double(native).';
errorCovariance=eye(raw.RI)/(eye(raw.RI)+(projection'*projection)/variance);
referenceLayers=10*log10(1./real(diag(errorCovariance))-1);
rawLayers=double(raw.SelectedPostEqSINRPerLayer_dB(:));
assert(numel(referenceLayers)==numel(rawLayers) && max(abs(referenceLayers-rawLayers))<1e-8, ...
    'Independent identity-channel MMSE reference must match the unanchored spatial calculation.');
anchorLayers=double(anchored.SelectedPostEqSINRPerLayer_dB(:));
anchorComparison=table((1:numel(rawLayers)).',repmat(raw.RI,numel(rawLayers),1), ...
    repmat(sum(abs(projection(:)).^2),numel(rawLayers),1), ...
    repmat(pilotSNR,numel(rawLayers),1),referenceLayers,rawLayers,anchorLayers, ...
    anchorLayers-referenceLayers,'VariableNames',{'Layer','Rank','TotalPrecoderEnergy', ...
    'DeclaredSRSPilotSNR_dB','IndependentPUSCHSINR_dB','UnanchoredSINR_dB', ...
    'AnchoredSINR_dB','AnchorDeviationFromIndependentReference_dB'});
anchorComparison.Source=repmat("declared_identity_channel_MMSE_algebra_not_runtime_measurement",height(anchorComparison),1);
writetable(anchorComparison,fullfile(outputRoot,'anchor_power_comparison.csv'));
save(fullfile(outputRoot,'anchor_power_comparison.mat'),'anchorComparison','raw','anchored', ...
    'projection','errorCovariance','variance');
disp(anchorComparison);
fprintf('SRS_NOISE_DESPREADING_DIAGNOSTIC=%s\n',outputRoot);
end
