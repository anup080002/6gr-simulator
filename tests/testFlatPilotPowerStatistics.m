function ok=testFlatPilotPowerStatistics()
% Actual CSI-RS/OFDM + independent AWGN episodes; receiver component only.
% Known H/noise score the estimator and NEVER enter its inputs. Not a
% shared-feedback, acquisition, detector or complete-scenario certificate.
setup6GRSimToolkit('Verbose',false);
carrier=nrCarrierConfig('NSizeGrid',25,'SubcarrierSpacing',15,'NCellID',17);
resource=nrCSIRSConfig('CSIRSType','nzp','CSIRSPeriod','on', ...
    'RowNumber',4,'Density','one','SymbolLocations',6, ...
    'SubcarrierLocations',0,'NumRB',25);
indices=nrCSIRSIndices(carrier,resource); symbols=nrCSIRS(carrier,resource);
tx=nrResourceGrid(carrier,4); tx(indices)=symbols;
H=[.8 0 .6 0;0 .6 0 .8];
signalWaveform=nrOFDMModulate(carrier,tx)*H.';
cleanGrid=nrOFDMDemodulate(carrier,signalWaveform);
physical=unique(mod(double(indices(:))-1,12*carrier.NSizeGrid*carrier.SymbolsPerSlot)+1);
flatClean=reshape(cleanGrid,[],2);
expectedPower=mean(abs(flatClean(physical,:)).^2,1);
N=numel(physical); P=4; d=N-P; episodes=256;
assert(d>2);
rows=struct([]); summary=struct([]); failures=0;
folder=fullfile(pwd,'results','lls','flat_pilot_power_statistics', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(folder);
points=[-30 -20 -10 0 10 20 30 40];
for group=0:numel(points)
    noiseOnly=group==0;
    if noiseOnly, snr=0; base=zeros(size(signalWaveform)); target=[0 0];
    else, snr=points(group); base=signalWaveform; target=expectedPower; end
    sigma2=10^(-snr/10); firstRow=numel(rows)+1;
    for episode=1:episodes
        seed=9243100+episode;
        [capture,noiseEvidence]=sixgr.phy.waveform.addOccupiedREAWGN( ...
            base,carrier,snr,'Seed',seed,'SignalEnergyPerOccupiedRE',1);
        assert(abs(noiseEvidence.GridNoiseVariance/sigma2-1)<1e-12);
        receivedGrid=nrOFDMDemodulate(carrier,capture);
        [~,~,fit]=sixgr.phy.rx.estimateFlatAWGNReferenceGrid(carrier,receivedGrid,indices,symbols,4);
        m=fit.ReferencePowerMeasurement;
        assert(~m.ClippedToNonnegative && ~m.ConfiguredSNROrChannelTruthUsed);
        if episode==1
            % Amplitude-unit conversion must not alter SNR or null-tail
            % probabilities, and signed powers must scale quadratically.
            [~,~,scaled]=sixgr.phy.rx.estimateFlatAWGNReferenceGrid(carrier,receivedGrid*1e-6,indices,symbols,4);
            q=scaled.ReferencePowerMeasurement;
            assert(max(abs(q.SignedSignalPowerPerReceiveBranch/1e-12- ...
                m.SignedSignalPowerPerReceiveBranch))<1e-10*max(1,max(abs(m.SignedSignalPowerPerReceiveBranch))));
            assert(max(abs(q.SignedReferenceSNRLinearPerReceiveBranch- ...
                m.SignedReferenceSNRLinearPerReceiveBranch))<1e-10*max(1,max(abs(m.SignedReferenceSNRLinearPerReceiveBranch))));
            assert(max(abs(q.NoiseOnlyNullTailProbabilityPerReceiveBranch- ...
                m.NoiseOnlyNullTailProbabilityPerReceiveBranch))<1e-10);
        end
        for branch=1:2
            row=struct('NoiseOnly',noiseOnly,'ReferenceSNR_dB',snr,'Episode',episode, ...
                'Seed',seed,'ReceiveBranch',branch,'PilotRECount',N,'ResidualComplexDOF',d, ...
                'RawReconstructedPower',m.RawReconstructedPowerPerReceiveBranch(branch), ...
                'EstimatedNoiseBias',m.EstimatedNoiseBiasPerReceiveBranch(branch), ...
                'SignedSignalPower',m.SignedSignalPowerPerReceiveBranch(branch), ...
                'EstimatedNoisePower',m.NoisePowerPerReceiveBranch(branch), ...
                'SignedReferenceSNRLinear',m.SignedReferenceSNRLinearPerReceiveBranch(branch), ...
                'NoiseOnlyNullTailProbability',m.NoiseOnlyNullTailProbabilityPerReceiveBranch(branch), ...
                'ValidationKnownSignalPower',target(branch),'ValidationNoisePower',sigma2, ...
                'ValidationReferenceUsedByReceiver',false, ...
                'Source',m.Source,'EvidenceScope',"physical_csirs_receiver_component_not_integrated_scenario");
            if isempty(rows), rows=row; else, rows(end+1)=row; end %#ok<AGROW>
        end
    end
    subset=struct2table(rows(firstRow:end));
    for branch=1:2
        b=subset(subset.ReceiveBranch==branch,:); rho=target(branch)/sigma2;
        powerSE=sqrt((2*sigma2*N*target(branch)+sigma2^2*(P+P^2/d))/(N^2*episodes));
        % Exact variance of the noncentral-F-derived signed linear ratio.
        ratioSE=sqrt(((d-1)*(P+2*N*rho)+(P+N*rho)^2)/((d-2)*N^2*episodes));
        powerZ=(mean(b.SignedSignalPower)-target(branch))/powerSE;
        ratioZ=(mean(b.SignedReferenceSNRLinear)-rho)/ratioSE;
        passed=abs(powerZ)<6 && abs(ratioZ)<6;
        if noiseOnly
            passed=passed && any(b.SignedSignalPower<0) && any(b.SignedReferenceSNRLinear<0) && ...
                abs(mean(b.NoiseOnlyNullTailProbability)-.5)<6/sqrt(12*episodes);
        end
        failures=failures+~passed;
        item=struct('NoiseOnly',noiseOnly,'ReferenceSNR_dB',snr,'ReceiveBranch',branch, ...
            'Episodes',episodes,'RawPowerMean',mean(b.RawReconstructedPower), ...
            'SignedPowerMean',mean(b.SignedSignalPower),'ValidationPower',target(branch), ...
            'ValidationPowerStandardError',powerSE,'PowerZScore',powerZ, ...
            'SignedSNRLinearMean',mean(b.SignedReferenceSNRLinear),'ValidationSNRLinear',rho, ...
            'ValidationSNRStandardError',ratioSE,'SNRZScore',ratioZ,'Pass',passed);
        if isempty(summary), summary=item; else, summary(end+1)=item; end %#ok<AGROW>
    end
    writetable(struct2table(rows),fullfile(folder,'receiver_episodes.csv'));
    writetable(struct2table(summary),fullfile(folder,'receiver_statistics.csv'));
    fprintf('FLAT_PILOT_POWER_GROUP noiseOnly=%d snr=%g episodes=%d failures=%d\n', ...
        noiseOnly,snr,episodes,failures);
end
% Degenerate data cannot manufacture a null probability or linear SNR.
X=[1 0;0 1;1 1]; empty=sixgr.phy.rx.estimateFlatAWGNMultiportChannel(zeros(3,1),X);
assert(empty.ReferencePowerMeasurement.SignedSignalPowerPerReceiveBranch==0 && ...
    isnan(empty.ReferencePowerMeasurement.NoiseOnlyNullTailProbabilityPerReceiveBranch) && ...
    isnan(empty.ReferencePowerMeasurement.SignedReferenceSNRLinearPerReceiveBranch));
T=struct2table(summary); S=T(~T.NoiseOnly,:);
fig=figure('Visible','off','Color','w'); cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
if isprop(fig,'Theme'), fig.Theme='light'; end
tiledlayout(fig,2,1);
for branch=1:2
    b=S(S.ReceiveBranch==branch,:); ax=nexttile; hold(ax,'on');
    plot(ax,b.ReferenceSNR_dB,b.RawPowerMean./b.ValidationPower,'--o','DisplayName','Raw fitted power');
    errorbar(ax,b.ReferenceSNR_dB,b.SignedPowerMean./b.ValidationPower, ...
        6*b.ValidationPowerStandardError./b.ValidationPower,'-s','DisplayName','Signed correction; validation 6-SE bounds');
    yline(ax,1,':','Independent known-signal reference'); grid(ax,'on');
    xlabel(ax,'Configured occupied-RE Es/N0 (dB)'); ylabel(ax,'Ensemble power / independent reference');
    title(ax,sprintf('Receive branch %d; %d independent waveform episodes per point',branch,episodes));
    legend(ax,'Location','best');
end
fig.Position=[100 100 1100 800];
exportgraphics(fig,fullfile(folder,'receiver_statistics.png'),'Resolution',150);
fprintf('FLAT_PILOT_POWER_STATISTICS cases=%d episodes=%d failures=%d output=%s\n', ...
    height(T),episodes*(numel(points)+1),failures,folder);
assert(failures==0,'sixgr:test:BiasedFlatPilotPower','Power/SNR ensemble verification failed.');
ok=true;
end
