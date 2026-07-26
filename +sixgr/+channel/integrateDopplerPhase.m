function phase_rad = integrateDopplerPhase(time_s, signedDoppler_Hz)
%INTEGRATEDOPPLERPHASE Integrate the applied per-update signed Doppler.
%
% Each new observed Doppler state is applied over the interval that ends at
% its timestamp. This right-endpoint convention matches the runtime channel
% update order and keeps the sign/phase contract explicit.

arguments
    time_s double {mustBeFinite}
    signedDoppler_Hz double {mustBeFinite}
end
if ~isequal(size(time_s),size(signedDoppler_Hz))
    error("CHANNEL:InvalidDopplerState", ...
        "Time and signed Doppler arrays must have identical dimensions.");
end
if any(diff(time_s(:)) <= 0)
    error("CHANNEL:InvalidDopplerState", ...
        "Doppler timestamps must be strictly increasing.");
end
timeVector = time_s(:);
dopplerVector = signedDoppler_Hz(:);
phaseVector = zeros(size(timeVector));
phaseVector(2:end) = cumsum(2.*pi.*dopplerVector(2:end).*diff(timeVector));
phase_rad = reshape(phaseVector,size(time_s));
end
