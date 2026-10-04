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
effective=complex(zeros(nr,layers,nres));
for k=1:nres
    effective(:,:,k)=H(:,:,k)*F(:,:,min(k,size(F,3)))*sqrt(power(min(k,numel(power))));
end
out=sixgr.system.abstraction.evaluateEffectiveSpatialSINR(effective,R,receiverType);
% Retain the existing factored-channel public evidence identity.
out.Source="modeled_per_resource_channel_"+receiverType;
end
