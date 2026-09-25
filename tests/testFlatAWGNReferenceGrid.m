function ok=testFlatAWGNReferenceGrid()
% Real CSI-RS CDM/OFDM checks; channel/noise truth scores the receiver only.
setup6GRSimToolkit('Verbose',false);
carrier=nrCarrierConfig('NSizeGrid',25,'SubcarrierSpacing',15,'NCellID',17);
stream=RandStream('mt19937ar','Seed',9242503);
rows=struct([]);
for rowNumber=[2 3 4]
    resource=nrCSIRSConfig('CSIRSType','nzp','CSIRSPeriod','on', ...
        'RowNumber',rowNumber,'Density','one','SymbolLocations',6, ...
        'SubcarrierLocations',0,'NumRB',25);
    indices=nrCSIRSIndices(carrier,resource); symbols=nrCSIRS(carrier,resource);
    ports=double(resource.NumCSIRSPorts);
    reference=nrResourceGrid(carrier,ports); reference(indices)=symbols;
    K=size(reference,1); L=size(reference,2);
    physical=unique(mod(double(indices)-1,K*L)+1);
    X=reshape(reference,K*L,ports); X=X(physical,:);
    % Independent noise-only episodes expose the |Hhat|^2 signal floor.
    % The signed debiased estimate must retain negative observations and
    % have zero mean within a predeclared six-standard-error bound. The
    % bound includes uncertainty of the received-residual noise estimate.
    episodes=256; variance=10; noiseBranches=2;
    signedSum=zeros(ports,noiseBranches); rawSum=signedSum;
    negativeCount=0;
    unitCovariance=(X'*X)\eye(ports);
    coefficientVariance=variance*real(diag(unitCovariance));
    for episode=1:episodes
        noiseGrid=sqrt(variance/2)*(randn(stream,K,L,noiseBranches)+1i*randn(stream,K,L,noiseBranches));
        [~,~,noiseFit]=sixgr.phy.rx.estimateFlatAWGNReferenceGrid( ...
            carrier,noiseGrid,indices,symbols,ports);
        signed=noiseFit.UnbiasedCoefficientPowerEstimatePerPortReceiveBranch;
        signedSum=signedSum+signed;
        rawSum=rawSum+abs(noiseFit.GainPerPortReceiveBranch).^2;
        negativeCount=negativeCount+nnz(signed<0);
    end
    standardError=coefficientVariance*sqrt((1+1/(size(X,1)-ports))/episodes);
    assert(all(abs(signedSum/episodes)<6*standardError,'all') && negativeCount>0, ...
        'Noise-only channel power must not be clipped or called a detected signal.');
    assert(all(abs(rawSum/episodes-coefficientVariance)<6*coefficientVariance/sqrt(episodes),'all'));
    fprintf('FLAT_CSIRS_NOISE_BIAS_CHECK row=%d episodes=%d negative_observations=%d max_z=%g\n', ...
        rowNumber,episodes,negativeCount,max(abs(signedSum/episodes)./standardError,[],'all'));
    for branches=[1 2 4]
        applied=(randn(stream,branches,ports)+1i*randn(stream,branches,ports))/sqrt(2*ports);
        waveform=nrOFDMModulate(carrier,reference)*applied.';
        clean=nrOFDMDemodulate(carrier,waveform);
        [hClean,nClean]=sixgr.phy.rx.estimateFlatAWGNReferenceGrid( ...
            carrier,clean,indices,symbols,ports);
        assert(norm(squeeze(reshape(hClean(1,1,:,:),branches,ports))-applied,'fro')<1e-12);
        assert(nClean<1e-24);
        for snr=[-10 20]
            capture=sixgr.phy.waveform.addOccupiedREAWGN(waveform,carrier,snr, ...
                'Seed',9242504,'SignalEnergyPerOccupiedRE',mean(abs(symbols).^2));
            received=nrOFDMDemodulate(carrier,capture);
            [h,nVar,info]=sixgr.phy.rx.estimateFlatAWGNReferenceGrid( ...
                carrier,received,indices,symbols,ports);
            Y=reshape(received,K*L,branches); Y=Y(physical,:);
            independent=X\Y;
            assert(norm(reshape(h(1,1,:,:),branches,ports)-independent.','fro')<1e-12);
            expectedNoise=mean(sum(abs(Y-X*independent).^2,1)/(size(X,1)-ports));
            assert(abs(nVar-expectedNoise)<1e-12*max(1,nVar));
            assert(all(reshape(h,K*L,[])==reshape(h(1,1,:,:),1,[]),'all'));
            assert(info.PilotRECount==size(X,1) && ~info.UsedScoringReference);
            assert(isfinite(info.PilotResidualPower) && info.PilotResidualPower>=0 && ...
                isfinite(info.PilotSignalPower) && info.PilotSignalPower>0 && ...
                isfinite(info.PilotResidualNMSE_dB), ...
                'The flat CSI-RS estimator must publish measured pilot residual diagnostics.');
            mse=mean(abs(independent-applied.').^2,'all');
            changed=sixgr.phy.rx.estimateFlatAWGNReferenceGrid( ...
                carrier,.17i*received,indices,symbols,ports);
            assert(max(abs(changed-.17i*h),[],'all')<1e-12);
            reordered=sixgr.phy.rx.estimateFlatAWGNReferenceGrid( ...
                carrier,received,flipud(indices(:)),flipud(symbols(:)),ports);
            assert(isequal(h,reordered),'Reference enumeration must not change ownership.');
            entry=struct('CSI_RS_Row',rowNumber,'Ports',ports,'ReceiveBranches',branches, ...
                'ConfiguredSNR_dB',snr,'NoiseVariance',nVar,'ChannelMSE',mse, ...
                'PredictedCoefficientMSE',mean(info.CoefficientErrorVarianceEstimatePerPortReceiveBranch,'all'), ...
                'PilotCount',info.PilotRECount,'DegreesOfFreedom',info.ResidualComplexDegreesOfFreedomPerBranch, ...
                'Source',info.EngineUsed,'ReferenceUsedByReceiver',false);
            if isempty(rows), rows=entry; else, rows(end+1)=entry; end %#ok<AGROW>
        end
        localReject(@()sixgr.phy.rx.estimateFlatAWGNReferenceGrid( ...
            carrier,clean,[indices(:);indices(1)],[symbols(:);symbols(1)],ports));
        localReject(@()sixgr.phy.rx.estimateFlatAWGNReferenceGrid( ...
            carrier,clean,indices,symbols,ports+1)); % Missing port cannot be invented.
    end
end
folder=fullfile(pwd,'results','lls','flat_awgn_reference_grid',char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(folder); writetable(struct2table(rows),fullfile(folder,'receiver_measurements.csv'));
fprintf('FLAT_AWGN_REFERENCE_GRID_PASS cases=%d native_csirs_cdm=1 output=%s\n',numel(rows),folder);
ok=true;
end

function localReject(f)
try
    f();
catch ex
    assert(any(string(ex.identifier)==["sixgr:phy:rx:InvalidFlatReferencePilots", ...
        "sixgr:phy:rx:UnidentifiableFlatMultiportChannel"]));
    return;
end
error('test:InvalidFlatReferenceAccepted','Missing/duplicate port evidence must be rejected.');
end
