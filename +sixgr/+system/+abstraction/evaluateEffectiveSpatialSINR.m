function out=evaluateEffectiveSpatialSINR(effectiveChannel,noiseInterferenceCovariance,receiverType)
% Per-RE detector for an already power-weighted RX-by-layer channel.
% No extra transmit power, rank gain, loss, normalization or loading is
% applied here. Other layers on the SAME RE are accounted for exactly once.
% Independent other-RE/other-transmitter interference belongs in covariance.
arguments
    effectiveChannel {mustBeNumeric,mustBeFinite,mustBeNonempty}
    noiseInterferenceCovariance {mustBeNumeric,mustBeFinite,mustBeNonempty}
    receiverType (1,1) string {mustBeMember(receiverType,["lmmse","zf"])}="lmmse"
end
channel=double(effectiveChannel); R=double(noiseInterferenceCovariance);
[nr,layers,nres]=size(channel);
assert(ndims(channel)<=3 && ndims(R)<=3 && layers<=nr && ...
    size(R,1)==nr && size(R,2)==nr && ismember(size(R,3),[1 nres]), ...
    'sixgr:abstraction:SpatialDimensions','Effective channel, covariance and rank dimensions disagree.');
desired=zeros(nres,layers); interLayer=desired; external=desired;
for k=1:nres
    covariance=R(:,:,min(k,size(R,3)));
    scale=norm(covariance,'fro');
    assert(scale>0 && norm(covariance-covariance','fro')<=1e-10*scale, ...
        'sixgr:abstraction:Covariance','Noise/interference covariance must be Hermitian positive definite.');
    [~,notPositive]=chol(covariance);
    assert(notPositive==0,'sixgr:abstraction:Covariance', ...
        'Noise/interference covariance must be positive definite; no hidden diagonal loading is applied.');
    G=channel(:,:,k);
    if receiverType=="lmmse"
        W=(G*G'+covariance)\G;
    else
        assert(rank(G)==layers,'sixgr:abstraction:ZFRankDeficient', ...
            'Issued layers are not independently observable by the configured ZF receiver.');
        [Q,U]=qr(G,0);
        W=Q/U';
    end
    response=W'*G;
    desired(k,:)=abs(diag(response)).^2;
    offDiagonal=response;
    offDiagonal(1:layers+1:end)=0;
    interLayer(k,:)=sum(abs(offDiagonal).^2,2).';
    external(k,:)=real(diag(W'*covariance*W)).';
end
denominator=interLayer+external;
sinr=zeros(size(desired)); nonzero=denominator>0;
sinr(nonzero)=desired(nonzero)./denominator(nonzero);
assert(all(isfinite(sinr),'all') && all(external>=0,'all'), ...
    'sixgr:abstraction:SpatialNumerics','Nonfinite SINR or negative covariance power.');
out=struct('SINRLinear',sinr,'SINR_dB',10*log10(sinr), ...
    'DesiredOutputPower',desired,'InterLayerInterferencePower',interLayer, ...
    'ExternalNoiseInterferencePower',external, ...
    'ExecutionBackend',"calibrated_link_abstraction", ...
    'Source',"modeled_per_resource_effective_channel_"+receiverType, ...
    'ReceiverType',receiverType, ...
    'SourceClassification',"sls_spatial_estimate_not_waveform_measurement", ...
    'WaveformBacked',false,'CalibrationApplied',false);
end
