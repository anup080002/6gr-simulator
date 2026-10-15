function evidence=measureCSIRSCDMPortPower(carrier,reference,receivedGrid,cdm,disturbance)
% Port-3000 received power from local CDM despreading, not smoothed Hest.
% The disturbance must come from the disjoint configured CSI-IM resource.
% For one CDM tile, g=w*y and E|g|^2=|g_signal|^2+v*sum(abs(w).^2)
% under locally uncorrelated disturbance. Average powers of separate tiles;
% never coherently average a frequency-selective channel across the band.
% This is a practical measurement model, not a detector or a channel oracle.
K=12*double(carrier.NSizeGrid); L=double(carrier.SymbolsPerSlot);
nRx=size(receivedGrid,3); ports=size(reference,3);
assert(size(reference,1)==K && size(reference,2)==L && ...
    size(receivedGrid,1)==K && size(receivedGrid,2)==L && ...
    ndims(reference)<=3 && ndims(receivedGrid)<=3, ...
    'sixgr:refsig:CSICDMPowerDimensions','Require matching received and known-reference slot grids.');
validateattributes(cdm,{'numeric'},{'vector','numel',2,'integer','positive','finite'});
validateattributes(disturbance,{'numeric'},{'vector','numel',nRx,'nonnegative','finite'});
X=reshape(double(reference),K*L,ports);
Y=reshape(double(receivedGrid),K*L,nRx);
assert(all(isfinite(X),'all') && all(isfinite(Y),'all'), ...
    'sixgr:refsig:CSICDMPowerNonfinite','Reference and received samples must be finite.');
remaining=X(:,1)~=0; referenceCount=nnz(remaining);
assert(referenceCount>0,'sixgr:refsig:CSICDMPowerMissingPort','Port 3000 has no reference REs.');
rawSum=zeros(1,nRx); unitBiasSum=0; groups=0;
while any(remaining)
    first=find(remaining,1); [k,l]=ind2sub([K L],first);
    [kk,ll]=ndgrid(k+(0:cdm(1)-1),l+(0:cdm(2)-1));
    assert(all(kk<=K & ll<=L,'all'), ...
        'sixgr:refsig:CSICDMPowerTile','CDM tile exceeds the received slot.');
    tile=sub2ind([K L],kk(:),ll(:));
    assert(all(remaining(tile)), ...
        'sixgr:refsig:CSICDMPowerTile','Port-3000 reference must contain complete, nonoverlapping CDM tiles.');
    pilot=X(tile,1); energy=sum(abs(pilot).^2);
    weights=conj(pilot)/energy;
    projection=weights.'*X(tile,:);
    assert(abs(projection(1)-1)<1e-12 && all(abs(projection(2:end))<1e-12), ...
        'sixgr:refsig:CSICDMPowerOrthogonality','Installed CDM references must separate port 3000 from other ports.');
    coefficient=weights.'*Y(tile,:);
    % energy=tile RE count times its mean reference-symbol energy.
    rawSum=rawSum+energy*abs(coefficient).^2;
    unitBiasSum=unitBiasSum+energy*sum(abs(weights).^2);
    remaining(tile)=false; groups=groups+1;
end
raw=rawSum/referenceCount;
unitBias=unitBiasSum/referenceCount;
bias=unitBias*double(disturbance(:).');
evidence=struct('RawPort3000PowerPerBranch',raw, ...
    'EstimatedNoiseBiasPerBranch',bias,'SignedPort3000PowerPerBranch',raw-bias, ...
    'UnitDisturbancePowerBias',unitBias,'PilotCount',referenceCount, ...
    'CDMGroupCount',groups,'CDMLengths',double(cdm(:).'), ...
    'ClippedToNonnegative',false, ...
    'NoiseBiasModel',"locally_uncorrelated_disturbance_CSI_IM_matched_second_moment", ...
    'SignalModel',"per_CDM_tile_effective_channel_no_wideband_coherent_average", ...
    'RatioInterpretation',"signed_power_debiased_not_unbiased_ratio_dB_or_selected_max", ...
    'Source',"received_CDM_despread_CSI_IM_noise_debiased_port3000_reference_RE_power");
end
