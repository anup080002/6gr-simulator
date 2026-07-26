function drop = dropUEsStrict(profile, nUE, seed, parameters)
%DROP UESSTRICT Config-driven bounded UE placement with explicit RNG state.

arguments
    profile
    nUE (1,1) double {mustBeInteger,mustBePositive}
    seed (1,1) double {mustBeFinite}
    parameters struct
end

profile = upper(strtrim(string(profile)));
stream = RandStream("mt19937ar", "Seed", double(seed));
zone = zeros(nUE,1);
switch profile
    case "UNIFORM_HEX_SECTOR"
        radius = localRequired(parameters, "Radius_m");
        xy = zeros(nUE,2);
        accepted = 0;
        vertices = radius .* [cosd((0:5).*60).', sind((0:5).*60).'];
        while accepted < nUE
            candidate = (2 .* rand(stream, max(16,nUE), 2) - 1) .* radius;
            inside = inpolygon(candidate(:,1), candidate(:,2), ...
                vertices(:,1), vertices(:,2));
            take = min(nnz(inside), nUE-accepted);
            selected = candidate(find(inside, take, "first"), :);
            xy(accepted + (1:take), :) = selected;
            accepted = accepted + take;
        end
        z = repmat(1.5, nUE, 1);

    case "HOTSPOT_GAUSSIAN"
        center = [localRequired(parameters, "CenterX_m"), ...
            localRequired(parameters, "CenterY_m")];
        sigma = localRequired(parameters, "Sigma_m");
        radius = localRequired(parameters, "Radius_m");
        xy = center + sigma .* randn(stream, nUE, 2);
        radial = vecnorm(xy - center, 2, 2);
        outside = radial > radius;
        xy(outside,:) = center + (xy(outside,:) - center) ...
            .* (radius ./ radial(outside));
        z = repmat(1.5, nUE, 1);
        zone(:) = 1;

    case "STREET_CANYON"
        length_m = localRequired(parameters, "Length_m");
        width_m = localRequired(parameters, "Width_m");
        xy = [(rand(stream,nUE,1)-0.5).*length_m, ...
            (rand(stream,nUE,1)-0.5).*width_m];
        z = repmat(1.5, nUE, 1);
        zone(:) = 2;

    case "INDOOR_FLOOR_GRID"
        length_m = localRequired(parameters, "Length_m");
        width_m = localRequired(parameters, "Width_m");
        floors = localRequired(parameters, "Floors");
        xy = [(rand(stream,nUE,1)-0.5).*length_m, ...
            (rand(stream,nUE,1)-0.5).*width_m];
        floorIndex = randi(stream, [0 floors-1], nUE, 1);
        z = 1.5 + 3 .* floorIndex;
        zone = floorIndex;

    case "RMA_RING"
        rMin = localRequired(parameters, "Rmin_m");
        rMax = localRequired(parameters, "Rmax_m");
        if rMax <= rMin
            error("CHANNEL:InvalidDropDistribution", ...
                "RMA ring requires Rmax_m greater than Rmin_m.");
        end
        radius = sqrt(rMin.^2 + rand(stream,nUE,1) .* (rMax.^2-rMin.^2));
        angle = 2 .* pi .* rand(stream,nUE,1);
        xy = [radius.*cos(angle), radius.*sin(angle)];
        z = repmat(1.5, nUE, 1);
        zone(:) = 3;

    otherwise
        error("CHANNEL:InvalidDropDistribution", ...
            "Unsupported UE drop profile '%s'.", profile);
end

drop = table((0:nUE-1).', xy(:,1), xy(:,2), z, zone, ...
    'VariableNames', {'UEIndex0','X_m','Y_m','Z_m','ZoneID'});
end

function value = localRequired(parameters, field)
if ~isfield(parameters, field)
    error("CHANNEL:InvalidDropDistribution", ...
        "UE drop profile requires parameter %s.", field);
end
value = double(parameters.(field));
if ~(isscalar(value) && isfinite(value) && value > 0)
    error("CHANNEL:InvalidDropDistribution", ...
        "UE drop parameter %s must be finite and positive.", field);
end
end
