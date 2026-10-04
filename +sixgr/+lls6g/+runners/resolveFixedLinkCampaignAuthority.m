function [useValidation, enabled] = resolveFixedLinkCampaignAuthority(cfg)
%RESOLVEFIXEDLINKCAMPAIGNAUTHORITY Select an explicitly configured campaign.
% A reference-SNR diagnostic is not permission to launch a separate fixed-
% link calibration. Preserve legacy opt-in, but master_yaml owns both its
% enabled and disabled states.
validation = sixgr.util.structGet(cfg, "validation.fixed_link_campaign", struct());
legacy = sixgr.util.structGet(cfg, "sweeps_and_matrix.fixed_link_calibration", struct());
hasValidation = isstruct(validation) && isscalar(validation) && isfield(validation, "enabled");
hasLegacy = isstruct(legacy) && isscalar(legacy) && isfield(legacy, "enabled");
master = hasValidation && lower(strtrim(string(sixgr.util.structGet( ...
    validation, "configuration_authority", "")))) == "master_yaml";
useValidation = hasValidation && (master || logical(validation.enabled) || ~hasLegacy);
if useValidation
    enabled = logical(validation.enabled);
elseif hasLegacy
    enabled = logical(legacy.enabled);
else
    enabled = false;
end
end
