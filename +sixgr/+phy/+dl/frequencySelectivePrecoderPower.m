function metric = frequencySelectivePrecoderPower(H, W)
%FREQUENCYSELECTIVEPRECODERPOWER Mean received power per precoded layer.
%
% H is Nrx-by-Ntx or Nrx-by-Ntx-by-Nsnapshot. W is the explicit
% Ntx-by-Nlayer precoder for one PMI candidate. The returned value is one
% scalar candidate score: total projected receive power, averaged over
% snapshots and layers. Keeping the layer reduction here prevents a rank-R
% candidate from being mistaken for R independent scalar candidates.

if ~(isnumeric(H) && ~isempty(H) && ndims(H) <= 3 && ...
        all(isfinite(real(H(:)))) && all(isfinite(imag(H(:)))))
    error("sixgr:phy:dl:InvalidFrequencySelectiveChannel", ...
        "H must be a finite nonempty Nrx-by-Ntx[-by-Nsnapshot] array.");
end
if ~(isnumeric(W) && ismatrix(W) && ~isempty(W) && ...
        all(isfinite(real(W(:)))) && all(isfinite(imag(W(:)))))
    error("sixgr:phy:dl:InvalidFrequencySelectivePrecoder", ...
        "W must be a finite nonempty Ntx-by-Nlayer matrix.");
end
if size(H, 2) ~= size(W, 1)
    error("sixgr:phy:dl:FrequencySelectivePrecoderDimensionMismatch", ...
        "H has %d transmit ports but W has %d rows.", ...
        size(H, 2), size(W, 1));
end

if ismatrix(H)
    H = reshape(H, size(H, 1), size(H, 2), 1);
end
nSnapshots = size(H, 3);
nLayers = size(W, 2);
accumulatedPower = 0;
for snapshot = 1:nSnapshots
    projected = double(H(:,:,snapshot)) * double(W);
    accumulatedPower = accumulatedPower + sum(abs(projected(:)).^2);
end
metric = double(accumulatedPower) / double(nSnapshots * nLayers);
end
