function ch = estimateTRSChannel(rx, cfg, tx, det)
% Practical channel estimation ONLY. Independent NMSE is scored afterwards.
sixgr.runtime.RuntimeCallLedger.record("sixgr.phy.trs.estimateTRSChannel", ...
    "TRS","DL",struct("Stage","CHANNEL_TRACKING"));
estimator=string(sixgr.util.structGet(cfg,'RuntimeChannelEstimator','nr_channel_estimate'));
assert(isscalar(estimator) && any(estimator==["nr_channel_estimate","flat_static_awgn_ls"]), ...
    'sixgr:phy:trs:InvalidChannelEstimator','Select a supported explicit TRS estimator.');
modelEvidence=struct();
if estimator=="flat_static_awgn_ls"
    assert(strcmpi(string(cfg.ChannelModel),'AWGN') && ...
        sixgr.channel.IdentityAWGNRuntime.enabled(cfg.BaseConfig), ...
        'sixgr:phy:rx:FlatAWGNObservationRequired','Flat TRS LS requires the explicit AWGN operator.');
    modelEvidence=sixgr.phy.rx.assertFlatStaticAWGNObservation( ...
        sixgr.util.structGet(rx,'ReceivedExecutionEvidence',struct()));
end
rows=repmat(localRow(),numel(det.SlotDetections),1);
estimates=cell(numel(rows),1); pilots=estimates; powerEvidence=estimates;
for k=1:numel(rows)
    d=det.SlotDetections(k); row=localRow();
    row.RunId=string(cfg.RunId); row.ConfigHash=string(cfg.ConfigHash);
    row.Slot=d.Slot; row.ChannelEstimationAttempted=true;
    row.ChannelNMSEThreshold_dB=double(cfg.ChannelNMSEThresholddB);
    try
        assert(d.Detected && ~isempty(d.RxGrid),'sixgr:phy:trs:MissingDetectedChannelResources', ...
            'Channel estimation requires detected, actually demodulated TRS samples.');
        grid=d.RxGrid; ind=double(d.ReferenceIndices(:)); ref=d.ReferenceSymbols(:);
        K=size(grid,1); L=size(grid,2); R=size(grid,3);
        assert(numel(ind)==numel(ref) && numel(unique(ind))==numel(ind) && ...
            all(ind>=1 & ind<=K*L) && all(isfinite(grid(:))), ...
            'sixgr:phy:trs:IncompleteChannelPilotResources','Do not truncate or discard pilot/receive-branch samples.');
        reference=zeros(K,L,'like',grid); reference(ind)=ref;
        if estimator=="flat_static_awgn_ls"
            samples=reshape(grid,K*L,R);
            fit=sixgr.phy.rx.estimateFlatAWGNMultiportChannel(samples(ind,:),ref);
            hest=repmat(reshape(fit.GainPerPortReceiveBranch,1,1,R),K,L,1);
            noise=fit.NoiseVariance;
            row.ChannelEstimator="received_flat_static_awgn_ls_dof_corrected";
            evidence=fit.ReferencePowerMeasurement;
            powerEvidence{k}=evidence;
            row.DesiredPilotPower=mean(evidence.SignedSignalPowerPerReceiveBranch);
            row.ResidualPilotPower=mean(evidence.NoisePowerPerReceiveBranch);
            row.SignedPilotSINRLinear=mean(evidence.SignedReferenceSNRLinearPerReceiveBranch);
            if row.SignedPilotSINRLinear>0 && isfinite(row.SignedPilotSINRLinear)
                row.PilotSINR_dB=10*log10(row.SignedPilotSINRLinear);
            end
            row.SINRMeasurementDomain="received_TRS_pilot_RE_equal_branch_mean_signed_linear_SNR";
            row.PilotPowerEvidenceJSON=string(jsonencode(evidence));
        else
            [hest,noise]=nrChannelEstimate(tx.GridSlots(k).Carrier,grid,reference);
        end
        assert(size(hest,1)==K && size(hest,2)==L && size(hest,3)==R && size(hest,4)==1 && ...
            all(isfinite(hest(:))),'sixgr:phy:trs:InvalidPracticalChannelGrid', ...
            'Keep the complete per-resource/per-RX practical channel estimate.');
        received=reshape(grid,K*L,R); fitted=reshape(hest,K*L,R);
        received=received(ind,:); fitted=fitted(ind,:).*ref;
        residual=received-fitted;
        receivedEnergy=sum(abs(received).^2,'all');
        assert(receivedEnergy>0,'sixgr:phy:trs:NoReceivedPilotEnergy','No received pilot energy.');
        row.PilotFitResidualRatio_dB=10*log10(sum(abs(residual).^2,'all')/receivedEnergy);
        row.PilotFitSignalToResidual_dB=10*log10(sum(abs(fitted).^2,'all')/sum(abs(residual).^2,'all'));
        row.NoiseEstimate=double(noise);
        row.HestDimensions=strjoin(string(size(hest)),'x');
        row.HestRxPorts=R; row.HestTxPorts=1;
        row.TRSChannelEstimateAvailable=true;
        row.Status="practical_channel_available_independent_NMSE_not_yet_scored";
        estimates{k}=hest; pilots{k}=ind;
    catch ME
        row.Status="channel_estimate_failed:"+string(ME.identifier);
    end
    rows(k)=row;
end
% Average in linear space with equal slot/branch weights, not in dB and
% not by selecting the strongest noisy branch. Nonpositive estimates remain
% signed evidence; they are never clipped into a fabricated finite dB value.
linear=NaN; measuredDB=NaN; desired=NaN; disturbance=NaN;
source="unavailable_pilot_fit_is_not_independent_SINR";
domain=source;
if ~isempty(rows) && all([rows.TRSChannelEstimateAvailable]) && estimator=="flat_static_awgn_ls"
    linear=mean([rows.SignedPilotSINRLinear]);
    if isfinite(linear) && linear>0, measuredDB=10*log10(linear); end
    desired=mean([rows.DesiredPilotPower]); disturbance=mean([rows.ResidualPilotPower]);
    source="received_known_pilot_LS_projection_and_residual_degrees_of_freedom";
    domain="received_TRS_pilot_RE_equal_slot_branch_mean_signed_linear_SNR";
end
ch=struct('Table',struct2table(rows,'AsArray',true),'ChannelEstimates',{estimates}, ...
    'PilotPowerEvidence',{powerEvidence},'SignedPilotSINRLinear',linear, ...
    'PilotSINRSource',source,'SINRMeasurementDomain',domain, ...
    'EstimatorModelEvidence',modelEvidence, ...
    'PilotIndices',{pilots},'Attempted',~isempty(rows),'EstimateAvailable', ...
    ~isempty(rows) && all([rows.TRSChannelEstimateAvailable]), ...
    'MeanNMSE_dB',NaN,'NMSEScoringAvailable',false,'NMSEReferenceSource',"unavailable", ...
    'MeanPilotSINR_dB',measuredDB,'DesiredPilotPower',desired,'ResidualPilotPower',disturbance, ...
    'HestDimensions',strjoin(unique(string([rows.HestDimensions]),'stable'),'|'), ...
    'HestRxPorts',max([rows.HestRxPorts],[],'omitnan'),'HestTxPorts',max([rows.HestTxPorts],[],'omitnan'));
end
function row=localRow()
row=struct('RunId',"",'ConfigHash',"",'Slot',NaN,'ChannelEstimationAttempted',false, ...
    'TRSChannelEstimateAvailable',false,'NMSE_dB',NaN,'NMSEScoringAvailable',false, ...
    'NMSEReferenceSource',"unavailable",'NMSEComparedComplexValues',0, ...
    'ChannelErrorEnergy',NaN,'ChannelReferenceEnergy',NaN, ...
    'PilotFitResidualRatio_dB',NaN,'PilotFitSignalToResidual_dB',NaN, ...
    'NoiseEstimate',NaN,'ChannelNMSEThreshold_dB',NaN, ...
    'DesiredPilotPower',NaN,'ResidualPilotPower',NaN,'PilotSINR_dB',NaN, ...
    'SignedPilotSINRLinear',NaN,'PilotPowerEvidenceJSON',"", ...
    'SINRMeasurementDomain',"unavailable_pilot_fit_is_not_independent_SINR", ...
    'PowerReferencePlane',"received_grid_after_timing_correction", ...
    'HestDimensions',"",'HestRxPorts',NaN,'HestTxPorts',NaN, ...
    'ChannelEstimator',"nrChannelEstimate_received_TRS_reference_grid", ...
    'Status',"",'TruthStatus',"real_lls_evidence");
end
