function ok = testMeasuredCSIReceiverSNRSweep(numReceiveAntennas,estimator)
% Actual four-port CSI-RS receiver across the requested eight AWGN points.
% This is an isolated receiver/codebook component, not an access, BLER or
% shared-feedback scenario qualification. The known channel/noiseless grid
% is used only for independent calibration/error checks, never CSI selection.
setup6GRSimToolkit('Verbose',false);
if nargin<1, numReceiveAntennas=4; end
if nargin<2, estimator="nrChannelEstimate"; end
estimator=string(estimator);
assert(isscalar(estimator) && any(estimator==["nrChannelEstimate","flat_static_awgn_ls"]));
validateattributes(numReceiveAntennas,{'numeric'},{'scalar','integer'});
assert(ismember(numReceiveAntennas,[2 4]), ...
    'Use the declared 4x4 identity or 4x2 fixed-matrix receiver fixture.');
carrier=nrCarrierConfig('NSizeGrid',25,'SubcarrierSpacing',15,'NCellID',17);
csirs=nrCSIRSConfig('CSIRSType','nzp','RowNumber',4,'Density','one', ...
    'SymbolLocations',6,'SubcarrierLocations',0,'NumRB',25);
dmrs=nrPDSCHDMRSConfig;
indices=nrCSIRSIndices(carrier,csirs); symbols=nrCSIRS(carrier,csirs);
txGrid=nrResourceGrid(carrier,4); txGrid(indices)=symbols;
physicalChannel=eye(4);
if numReceiveAntennas==2
    physicalChannel=[.8 0 .6 0;0 .6 0 .8];
end
waveform=nrOFDMModulate(carrier,txGrid)*physicalChannel.';
noiselessGrid=nrOFDMDemodulate(carrier,waveform);
points=[-30 -20 -10 0 10 20 30 40];
rows=struct([]);
folder=fullfile(pwd,'results','lls','measured_csi_receiver_snr_sweep', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(folder);
for snr=points
    % Reset the independent noise stream for a paired calibration sweep.
    % The physical channel and transmitted CSI-RS are identical at each point.
    [capture,noise]=sixgr.phy.waveform.addOccupiedREAWGN( ...
        waveform,carrier,snr,'Seed',38214225, ...
        'SignalEnergyPerOccupiedRE',mean(abs(symbols).^2));
    receivedGrid=nrOFDMDemodulate(carrier,capture);
    physicalNoise=mean(abs(receivedGrid-noiselessGrid).^2,'all');
    assert(noise.RequestedEsN0_dB==snr);
    expectedNoise=mean(abs(symbols).^2)*10^(-snr/10);
    assert(abs(noise.GridNoiseVariance-expectedNoise)<=1e-12*expectedNoise);
    noiseError=10*log10(physicalNoise/expectedNoise);
    assert(abs(noiseError)<1,'Actual demodulated noise does not match occupied-RE calibration.');
    if estimator=="flat_static_awgn_ls"
        % This fixture executes a constant matrix and white sample noise,
        % without RF impairments. No such assumption is made for fading.
        [H,nVar]=sixgr.phy.rx.estimateFlatAWGNReferenceGrid( ...
            carrier,receivedGrid,indices,symbols,4);
    else
        [H,nVar]=nrChannelEstimate(carrier,receivedGrid,indices,symbols,'CDMLengths',[2 1]);
    end
    snapshots=reshape(permute(H,[3 4 1 2]),numReceiveAntennas,4,[]);
    measurement=sixgr.phy.mimo.CSIMeasurementState( ...
        MeasurementID="measured_csirs_snr_"+string(snr),UEID="UE-1", ...
        ResourceType="NZP-CSI-RS",ResourceID="CSI-RS-0",ResourceOrdinal=0, ...
        Slot=0,MaxAgeSlots=4,ChannelEstimate=snapshots,NoiseVariance=nVar, ...
        Provenance="measured_noisy_csirs_component_sweep");
    assert(isfinite(nVar) && nVar>0);
    trueChannel=reshape(physicalChannel,numReceiveAntennas,4,1);
    nmse=mean(sum(abs(snapshots-trueChannel).^2,[1 2]),'all')/sum(abs(physicalChannel).^2,'all');
    for codebook=["typeI-SinglePanel","typeII"]
        request=struct('ReportConfigID',"csirs_sweep",'Epoch',0, ...
            'CodebookType',codebook,'CodebookMode',1,'Panels',1, ...
            'Ports',4,'Rank',1,'MaxRank',2,'AllowedRanks',[1 2], ...
            'N1',2,'N2',1,'O1',4,'O2',1,'NumberOfBeams',2,'PhaseAlphabetSize',4, ...
            'ReportQuantity',"cri-ri-li-pmi-cqi",'NumCSIResources',1, ...
            'FrequencyGranularity',"wideband",'UCIChannel',"PUSCH");
        cfg=struct('Strict',true,'RankDomain',[1 2],'CQITable',"table1", ...
            'ReportConfiguration',request,'CurrentSlot',0);
        actual=sixgr.phy.mimo.NRCSIReportEngine.run(carrier,csirs,dmrs,H,nVar,cfg,measurement);
        assert(ismember(actual.RI,[1 2]) && actual.CQI>=0 && actual.CQI<=15);
        assert(~actual.ConfiguredSNRUsed && ~actual.ConfiguredOracleUsed && ~actual.SVDThresholdUsed);
        assert(abs(sum(abs(actual.Precoder_W).^2,'all')-1)<1e-12);
        installed=request; installed.Rank=3-actual.RI;
        decoder=sixgr.phy.mimo.CSIReportConfiguration(installed,0);
        decoded=decoder.decode(actual.CSIPart1Bits,actual.CSIPart2Bits);
        assert(decoded.RI==actual.RI && decoded.CQI_CW0==actual.CQI);
        % Validation-only reference: score the ALREADY selected precoder on
        % the known physical channel with the independently measured noise.
        % It must never feed RI/PMI/CQI selection or replace its observation.
        % This exposes the low-SNR |Hhat|^2 noise bias that a correct AWGN
        % calibration check alone cannot qualify.
        G=physicalChannel*actual.Precoder_W;
        gram=G'*G;
        errorCovariance=(eye(actual.RI)+gram/physicalNoise)\eye(actual.RI);
        oracleLayerSINR=1./real(diag(errorCovariance))-1;
        oracleSINR=10*log10(expm1(mean(log1p(oracleLayerSINR))));
        % Independent linear-combiner expression includes inter-layer
        % interference and receive-noise enhancement, not rank*Es/N0.
        combiner=(gram+physicalNoise*eye(actual.RI))\G';
        combined=combiner*G;
        desired=abs(diag(combined)).^2;
        interference=combined-diag(diag(combined));
        directSINR=desired./(sum(abs(interference).^2,2)+ ...
            physicalNoise*sum(abs(combiner).^2,2));
        assert(max(abs(oracleLayerSINR-directSINR)./max(directSINR,eps))<1e-8, ...
            'Validation MMSE covariance and explicit signal/interference/noise powers disagree.');
        row=struct('NumTransmitAntennas',4,'NumReceiveAntennas',numReceiveAntennas, ...
            'ChannelEstimator',estimator, ...
            'ConfiguredSNR_dB',snr,'AppliedAWGNSNR_dB',noise.RequestedEsN0_dB, ...
            'Codebook',codebook,'ConfiguredGridNoiseVariance',noise.GridNoiseVariance, ...
            'MeasuredGridNoiseVariance',physicalNoise,'GridNoiseError_dB',noiseError, ...
            'EstimatedNoiseVariance',nVar,'ChannelNMSE_dB',10*log10(nmse), ...
            'SelectedRI',actual.RI,'CQI',actual.CQI,'CSIObjectiveSINR_dB',actual.WidebandSINR_dB, ...
            'CQIEffectiveSINR_dB',actual.CQIEffectiveSINR_dB, ...
            'CQIEffectiveSINRSource',actual.CQIEffectiveSINRSource, ...
            'ValidationKnownChannelMMSESINR_dB',oracleSINR, ...
            'ValidationCSIObjectiveError_dB',actual.WidebandSINR_dB-oracleSINR, ...
            'ValidationReferenceSource',"known_channel_selected_precoder_measured_noise_not_receiver_measurement", ...
            'ValidationReferenceUsedForCSISelection',false, ...
            'CalibratedReferenceEsN0_dB',10*log10(noise.SignalEnergyPerOccupiedRE/physicalNoise), ...
            'CSIObjectiveSource',actual.RuntimeEvidenceSource, ...
            'NoiseSeed',noise.Seed,'EvidenceScope',"physical_csirs_receiver_component_not_integrated_scenario", ...
            'ConfiguredSNRUsedForCSISelection',actual.ConfiguredSNRUsed);
        if isempty(rows), rows=row; else, rows(end+1)=row; end %#ok<AGROW>
        % Preserve completed physical evidence even if a later gate fails.
        writetable(struct2table(rows),fullfile(folder,'receiver_measurements.csv'));
        if snr==40 && numReceiveAntennas==4
            assert(actual.WidebandSINR_dB>35 && ...
                actual.WidebandSINR_dB-actual.CQIEffectiveSINR_dB>8, ...
                'Receiver SINR was clipped to the CQI effective-SINR mapping range.');
        elseif snr==40
            % A rectangular channel need not attain the identity channel's
            % SINR: the selected finite codebook can have unequal modes.
            % Compare the SAME selected precoder against the applied H.
            assert(abs(actual.WidebandSINR_dB-oracleSINR)<1, ...
                'High-SNR rectangular-channel SINR disagrees with independent MMSE: measured=%g reference=%g.', ...
                actual.WidebandSINR_dB,oracleSINR);
        end
        fprintf('CSI_SWEEP_POINT snr=%g codebook=%s RI=%g CQI=%g objectiveSINR=%g noiseError=%g NMSE=%g\n', ...
            snr,codebook,actual.RI,actual.CQI,actual.WidebandSINR_dB,noiseError,row.ChannelNMSE_dB);
    end
end
T=struct2table(rows);
writetable(T,fullfile(folder,'receiver_measurements.csv'));
fig=figure('Visible','off','Color','w'); cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
% Keep the black reference curve legible regardless of desktop dark theme.
if isprop(fig,'Theme'), fig.Theme='light'; end
tiledlayout(fig,2,1);
ax=nexttile; hold(ax,'on');
first=T(T.Codebook=="typeI-SinglePanel",:);
plot(ax,first.ConfiguredSNR_dB,first.CalibratedReferenceEsN0_dB,'k-o', ...
    'DisplayName','Reference Es/N0 from measured grid noise');
for codebook=["typeI-SinglePanel","typeII"]
    selected=T(T.Codebook==codebook,:);
    plot(ax,selected.ConfiguredSNR_dB,selected.CSIObjectiveSINR_dB,'-o', ...
        'DisplayName',codebook+" estimated receiver SINR");
    plot(ax,selected.ConfiguredSNR_dB,selected.CQIEffectiveSINR_dB,'--x', ...
        'DisplayName',codebook+" CQI-model effective SINR (not measurement)");
    plot(ax,selected.ConfiguredSNR_dB,selected.ValidationKnownChannelMMSESINR_dB,':s', ...
        'DisplayName',codebook+" known-channel MMSE validation reference");
end
xlabel(ax,'Configured occupied-RE Es/N0 (dB)'); ylabel(ax,'dB (distinct quantities)');
title(ax,"CSI-RS receiver component: "+estimator+"; not scenario/BLER qualification",'Interpreter','none');
legend(ax,'Location','northwest','Interpreter','none'); grid(ax,'on');
ax=nexttile;
plot(ax,first.ConfiguredSNR_dB,first.ChannelNMSE_dB,'-o'); grid(ax,'on');
xlabel(ax,'Configured occupied-RE Es/N0 (dB)'); ylabel(ax,'Channel estimate NMSE (dB)');
title(ax,'Known channel used only for error scoring, never CSI selection');
fig.Position=[100 100 1200 900];
exportgraphics(fig,fullfile(folder,'receiver_measurements.png'),'Resolution',150);
fprintf('CSI_RECEIVER_SWEEP_COMPONENT_PASS cases=%d output=%s\n',numel(rows),folder);
ok=true;
end
