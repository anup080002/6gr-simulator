function tableOut=diagnoseCSIRSNoiseEstimator()
% Independent receiver diagnosis, not a qualification or scenario pass.
% Known channel/noise are used ONLY to score the production measurement.
setup6GRSimToolkit('Verbose',false);
prior=rng; restore=onCleanup(@()rng(prior)); %#ok<NASGU>
rows=struct([]);
for bandwidth=[25 100 264]
    carrier=nrCarrierConfig('NSizeGrid',bandwidth,'SubcarrierSpacing',30);
    csirs=nrCSIRSConfig('CSIRSType','nzp','CSIRSPeriod','on','RowNumber',3, ...
        'Density','one','SymbolLocations',4,'SubcarrierLocations',0,'NumRB',bandwidth);
    indices=nrCSIRSIndices(carrier,csirs); symbols=nrCSIRS(carrier,csirs);
    reference=nrResourceGrid(carrier,2); reference(indices)=symbols;
    K=size(reference,1); L=size(reference,2);
    port0=double(indices(indices<=K*L));
    for seed=1:8
        rng(73512+seed,'twister');
        unitNoise=complex(randn(K,L),randn(K,L))/sqrt(2);
        for noiseVariance=[0 10^(-12/10)]
            noise=sqrt(noiseVariance)*unitNoise;
            for cycles=[0 2]
                response=exp(-1j*2*pi*(0:K-1)'*cycles/K);
                signal=reference(:,:,1).*response;
                actual=sixgr.phy.refsig.measureCSISINRFromResourceGrid(carrier,csirs,signal+noise);
                % Compare both supported Toolbox reference interfaces.
                [~,indexNoise]=nrChannelEstimate(carrier,signal+noise,indices,symbols, ...
                    'CDMLengths',[2 1]);
                row=struct('NRB',bandwidth,'Seed',73512+seed,'ChannelCycles',cycles, ...
                    'InjectedVarianceValidationOnly',noiseVariance, ...
                    'ObservedReferenceNoiseValidationOnly',mean(abs(noise(port0)).^2), ...
                    'KnownReferenceSignalValidationOnly',mean(abs(signal(port0)).^2), ...
                    'EstimatedSignal',actual.DesiredPowerPerReceiveAntenna, ...
                    'EstimatedDisturbance',actual.NoiseInterferencePowerPerReceiveAntenna, ...
                    'IndicesInterfaceDisturbance',indexNoise, ...
                    'MeasuredCSI_SINR_dB',actual.CSI_SINR_dB, ...
                    'ValidationFieldsUsedByReceiver',false);
                if isempty(rows), rows=row; else, rows(end+1)=row; end %#ok<AGROW>
            end
        end
    end
    subset=rows([rows.NRB]==bandwidth);
    for cycles=[0 2]
        clean=subset([subset.ChannelCycles]==cycles & [subset.InjectedVarianceValidationOnly]==0);
        noisy=subset([subset.ChannelCycles]==cycles & [subset.InjectedVarianceValidationOnly]>0);
        fprintf('CSI_NOISE_DIAG NRB=%d cycles=%d noiseless_estimate=%g noisy_mean_estimate=%g actual_mean_noise=%g mean_SINR=%g\n', ...
            bandwidth,cycles,mean([clean.EstimatedDisturbance]), ...
            mean([noisy.EstimatedDisturbance]),mean([noisy.ObservedReferenceNoiseValidationOnly]), ...
            mean([noisy.MeasuredCSI_SINR_dB]));
    end
end
tableOut=struct2table(rows);
folder=fullfile(pwd,'results','lls','csirs_noise_estimator_diagnostic', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(folder); writetable(tableOut,fullfile(folder,'receiver_noise.csv'));
fprintf('CSI_NOISE_DIAG_COMPLETE cases=%d output=%s\n',height(tableOut),folder);
end
