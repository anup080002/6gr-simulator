function observation = stateObservationModel(profile, x, noise, commonOffset)
%STATEOBSERVATIONMODEL Apply y=H(S)x+g(S,t)+n for a known state.

sixgr.ntn.resilientsync.state.validateCompensationStateProfile(profile);
H = double(profile.H);
x = double(x(:));
if numel(x) ~= 2
    error("sixgr:ntn:resilientsync:InvalidEstimatorState", ...
        "Estimator state x must contain [rho; epsilon].");
end
if nargin < 3 || isempty(noise), noise = zeros(size(H,1),1); end
if nargin < 4 || isempty(commonOffset), commonOffset = zeros(size(H,1),1); end
noise = double(noise(:)); commonOffset = double(commonOffset(:));
if numel(noise) ~= size(H,1) || numel(commonOffset) ~= size(H,1)
    error("sixgr:ntn:resilientsync:ObservationDimensionMismatch", ...
        "Noise and g(S,t) must match the row count of H(S).");
end
observation = struct("Y", H*x + commonOffset + noise, "H", H, ...
    "G", commonOffset, "Noise", noise, "StateVersion", double(profile.state_version), ...
    "ProfileId", string(profile.id));
end
