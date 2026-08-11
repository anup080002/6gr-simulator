function validateCompensationStateProfile(profile)
%VALIDATECOMPENSATIONSTATEPROFILE Enforce the four-domain state contract.

required = ["id","research_taxonomy","payload_architecture","scope", ...
    "state_version","activation_time_s","validity_s","coefficient_rule_id", ...
    "H","g_model","k_rho","k_epsilon","fdd_scaling", ...
    "step_handling_rule","external_input","dl_timing","dl_frequency", ...
    "ul_timing","ul_frequency"];
for name = required
    if ~isfield(profile, name) || isempty(profile.(name))
        error("sixgr:ntn:resilientsync:IncompleteStateProfile", ...
            "State profile %s is missing %s.", localId(profile), char(name));
    end
end
domainRequired = ["status","responsible_entity","reference_point", ...
    "component","update_mode","derivative_order"];
for domain = ["dl_timing","dl_frequency","ul_timing","ul_frequency"]
    value = profile.(domain);
    if ~isstruct(value)
        error("sixgr:ntn:resilientsync:InvalidStateDomain", ...
            "%s.%s must be a mapping.", localId(profile), char(domain));
    end
    for field = domainRequired
        if ~isfield(value, field) || isempty(value.(field))
            error("sixgr:ntn:resilientsync:IncompleteStateDomain", ...
                "%s.%s is missing %s.", localId(profile), char(domain), char(field));
        end
    end
end
if ~(isscalar(profile.state_version) && isfinite(profile.state_version) && profile.state_version >= 1)
    error("sixgr:ntn:resilientsync:InvalidStateVersion", ...
        "State profile %s has an invalid state_version.", localId(profile));
end
if ~(isscalar(profile.activation_time_s) && isfinite(profile.activation_time_s) && profile.activation_time_s >= 0)
    error("sixgr:ntn:resilientsync:InvalidActivationTime", ...
        "State profile %s has an invalid activation_time_s.", localId(profile));
end
if ~(isscalar(profile.validity_s) && isfinite(profile.validity_s) && profile.validity_s > 0)
    error("sixgr:ntn:resilientsync:InvalidStateValidity", ...
        "State profile %s has an invalid validity_s.", localId(profile));
end
H = double(profile.H);
if size(H,2) ~= 2 || size(H,1) < 2
    error("sixgr:ntn:resilientsync:InvalidObservationMatrix", ...
        "State profile %s requires an H matrix with two columns and at least two rows.", localId(profile));
end
if rank(H) < 2 && string(profile.external_input) == "none"
    error("sixgr:ntn:resilientsync:RankDeficientObservationModel", ...
        "State profile %s has rank-deficient H and no external input.", localId(profile));
end
if ~(isscalar(profile.fdd_scaling) && isfinite(profile.fdd_scaling) && profile.fdd_scaling > 0)
    error("sixgr:ntn:resilientsync:MissingFDDScaling", ...
        "State profile %s requires a positive FDD scaling coefficient.", localId(profile));
end
networkFeeder = contains(string(profile.dl_timing.status), "network_feeder_compensated") || ...
    contains(string(profile.dl_frequency.status), "network_feeder_compensated");
ueFeeder = contains(string(profile.ul_timing.status), "service_plus_feeder") || ...
    contains(string(profile.ul_frequency.status), "service_plus_feeder");
if networkFeeder && ueFeeder
    error("sixgr:ntn:resilientsync:DuplicateFeederCompensation", ...
        "State profile %s assigns feeder compensation to both network and UE.", localId(profile));
end
end

function id = localId(profile)
id = "<unknown>";
if isstruct(profile) && isfield(profile, "id")
    id = char(string(profile.id));
else
    id = char(id);
end
end
