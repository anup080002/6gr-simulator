function validatePUCCHDetectorPilotPolicy(v)
% Preserve the development-only public pilot contract.
assert(isstruct(v) && isscalar(v) && string(v.stage)=="development_pilot", ...
    'test:PilotPolicy','This entry point accepts development pilots only.');
validatePUCCHDetectorEpisodePolicy(v);
end
