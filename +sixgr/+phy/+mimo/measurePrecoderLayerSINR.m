function sinr = measurePrecoderLayerSINR(H,W,disturbanceCovariance)
%MEASUREPRECODERLAYERSINR Receiver MMSE SINR of the selected measured channel.
% H is Nrx-by-Nport-by-Nresource, W is the selected Nport-by-Nlayer
% matrix and R includes the receiver's measured noise/interference. No
% transmitted symbols, perfect channel, configured SNR or rank score is used.
R=double(disturbanceCovariance);
assert(isnumeric(H) && isnumeric(W) && ndims(H)<=3 && ...
    ~isempty(H) && ismatrix(W) && ~isempty(W) && ...
    size(H,2)==size(W,1) && all(isfinite(H(:))) && all(isfinite(W(:))), ...
    'sixgr:mimo:MissingLayerMeasurement','Invalid measured channel/precoder dimensions.');
assert(isequal(size(R),[size(H,1) size(H,1)]) && all(isfinite(R(:))) && ...
    norm(R-R','fro')<=1e-12*max(norm(R,'fro'),realmin), ...
    'sixgr:mimo:InvalidInterferenceCovariance','A finite Hermitian disturbance covariance is required.');
[U,notPositiveDefinite]=chol((R+R')/2);
assert(notPositiveDefinite==0, 'sixgr:mimo:InvalidInterferenceCovariance', ...
    'Finite MMSE layer SINR requires positive-definite measured disturbance covariance.');
rankValue=size(W,2);
sinr=zeros(size(H,3),rankValue);
for resource=1:size(H,3)
    G=U'\(double(H(:,:,resource))*double(W));
    errorCovariance=(eye(rankValue)+G'*G)\eye(rankValue);
    diagonal=real(diag(errorCovariance));
    assert(all(isfinite(diagonal) & diagonal>0), ...
        'sixgr:mimo:MissingLayerMeasurement','MMSE layer error covariance is invalid.');
    % Exact zero-energy layers have SINR zero; max only removes negative
    % round-off from the unit-error boundary, not missing measurements.
    sinr(resource,:)=max(1./diagonal-1,0).';
end
end
