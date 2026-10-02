function out=evaluateSpatialSINR(channel,precoder,transmitPower,externalCovariance,receiverType)
%EVALUATESPATIALSINR Per-resource, per-layer LMMSE or zero-forcing estimates.
% channel: Nrx x Ntx x Nresource, including propagation/array gain exactly once.
% precoder: Ntx x Nlayer x (1 or Nresource), Frobenius norm one on each page.
% transmitPower: scalar or Nresource vector of total desired-link power.
% externalCovariance: Nrx x Nrx x (1 or Nresource), thermal noise plus
% OTHER transmissions only. Desired-link inter-layer interference is computed
% here, not supplied a second time in externalCovariance. Power/covariance
% must share one linear power plane; this function never applies MPR or loss.
%
% These are channel-model calculations, NOT measured waveform SINR or SRS.
arguments
    channel {mustBeNumeric,mustBeFinite,mustBeNonempty}
    precoder {mustBeNumeric,mustBeFinite,mustBeNonempty}
    transmitPower {mustBeNumeric,mustBeReal,mustBeFinite,mustBePositive}
    externalCovariance {mustBeNumeric,mustBeFinite,mustBeNonempty}
    receiverType (1,1) string {mustBeMember(receiverType,["lmmse","zf"])} = "lmmse"
end
H=double(channel); F=double(precoder); R=double(externalCovariance);
[nr,nt,nres]=size(H); layers=size(F,2);
assert(ndims(H)<=3 && ndims(F)<=3 && ndims(R)<=3 && ...
    size(F,1)==nt && layers<=min(nt,nr) && ...
    ismember(size(F,3),[1 nres]) && size(R,1)==nr && size(R,2)==nr && ...
    ismember(size(R,3),[1 nres]), ...
    'sixgr:abstraction:SpatialDimensions','Channel, precoder, covariance and rank dimensions disagree.');
power=double(transmitPower(:));
assert(isscalar(power) || numel(power)==nres, ...
    'sixgr:abstraction:PowerDimensions','Provide one total power or one value per resource.');
for j=1:size(F,3)
    assert(abs(sum(abs(F(:,:,j)).^2,'all')-1)<=1e-10, ...
        'sixgr:abstraction:PrecoderPower', ...
        'Precoder Frobenius norm must be one; do not multiply total power by rank.');
end
desired=zeros(nres,layers); interLayer=desired; external=desired;
for k=1:nres
    covariance=R(:,:,min(k,size(R,3)));
    scale=norm(covariance,'fro');
    assert(scale>0 && norm(covariance-covariance','fro')<=1e-10*scale, ...
        'sixgr:abstraction:Covariance','Noise/interference covariance must be Hermitian positive definite.');
    [~,notPositive]=chol(covariance);
    assert(notPositive==0,'sixgr:abstraction:Covariance', ...
        'Noise/interference covariance must be positive definite; no hidden diagonal loading is applied.');
    G=H(:,:,k)*F(:,:,min(k,size(F,3)))*sqrt(power(min(k,numel(power))));
    % Solves rather than matrix inversion. No scalar grid-channel surrogate.
    if receiverType=="lmmse"
        W=(G*G'+covariance)\G;
    else
        % QR implements the full-column-rank pseudoinverse without forming
        % normal equations (which square the condition number). Do not
        % silently change to MMSE or drop layers on a singular ZF grant.
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
% A zero channel produces the zero filter and zero SINR, not 0/0 or a
% fabricated positive estimate. Do not floor -Inf dB in the exported value.
assert(all(isfinite(sinr),'all') && all(external>=0,'all'), ...
    'sixgr:abstraction:SpatialNumerics','Nonfinite SINR or negative covariance power.');
out=struct('SINRLinear',sinr,'SINR_dB',10*log10(sinr), ...
    'DesiredOutputPower',desired,'InterLayerInterferencePower',interLayer, ...
    'ExternalNoiseInterferencePower',external, ...
    'ExecutionBackend',"calibrated_link_abstraction", ...
    'Source',"modeled_per_resource_channel_"+receiverType, ...
    'ReceiverType',receiverType, ...
    'SourceClassification',"sls_spatial_estimate_not_waveform_measurement", ...
    'WaveformBacked',false,'CalibrationApplied',false);
end
