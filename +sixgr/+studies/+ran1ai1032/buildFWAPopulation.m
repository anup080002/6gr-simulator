function population = buildFWAPopulation(cfg, profileID, nUE, seed)
%BUILDFWAPOPULATION Materialize the configured paired FWA population.
%
% The function uses fixed per-drop quotas with a seeded random permutation.
% This prevents comparator-to-comparator population drift while preserving
% random UE identity assignment. Outdoor LOS/NLOS remains a propagation
% result and is intentionally not fabricated here.

arguments
    cfg struct
    profileID (1,1) string
    nUE (1,1) double {mustBeInteger,mustBePositive}
    seed (1,1) double {mustBeInteger,mustBePositive}
end

definitions = cfg.sls.fwa_population_definitions;
ids = string({definitions.id});
idx = find(ids == profileID, 1, "first");
if isempty(idx)
    error("sixgr:ran1ai1032:UnknownFWAPopulation", ...
        "No configured FWA population definition exists for %s.", profileID);
end
definition = definitions(idx);
indoorFraction = double(definition.indoor_fraction);
lowLossFraction = double(definition.indoor_low_loss_fraction);
floorMin = double(definition.rooftop_floor_min);
floorMax = double(definition.rooftop_floor_max);
floorHeight_m = double(definition.floor_height_m);
indoorHeight_m = double(definition.indoor_cpe_height_m);
rooftopOffset_m = double(definition.rooftop_height_offset_m);
if ~(indoorFraction >= 0 && indoorFraction <= 1 && ...
        lowLossFraction >= 0 && lowLossFraction <= 1 && ...
        floorMin >= 1 && floorMax >= floorMin && ...
        floorMin == fix(floorMin) && floorMax == fix(floorMax) && ...
        floorHeight_m > 0 && indoorHeight_m > 0 && rooftopOffset_m >= 0)
    error("sixgr:ran1ai1032:InvalidFWAPopulationDefinition", ...
        "FWA population fractions, floor range and heights are invalid.");
end

stream = RandStream("mt19937ar", "Seed", seed);
permutation = randperm(stream, nUE).';
nIndoor = round(indoorFraction * nUE);
indoor = false(nUE, 1);
indoor(permutation(1:nIndoor)) = true;
outdoor = ~indoor;

o2iProfile = repmat("not_applicable_outdoor", nUE, 1);
indoorIDs = find(indoor);
nLow = round(lowLossFraction * nIndoor);
if nIndoor > 0
    indoorOrder = indoorIDs(randperm(stream, nIndoor));
    o2iProfile(indoorOrder(1:nLow)) = "low";
    o2iProfile(indoorOrder(nLow+1:end)) = "high";
end

floorNumber = NaN(nUE, 1);
height_m = repmat(indoorHeight_m, nUE, 1);
nOutdoor = nnz(outdoor);
if nOutdoor > 0
    floorNumber(outdoor) = randi(stream, [floorMin floorMax], nOutdoor, 1);
    height_m(outdoor) = floorNumber(outdoor) .* floorHeight_m + rooftopOffset_m;
end

populationClass = repmat("indoor_cpe", nUE, 1);
populationClass(outdoor) = "outdoor_rooftop_cpe";
UEID = (1:nUE).';
PopulationProfile = repmat(profileID, nUE, 1);
Indoor = indoor;
Outdoor = outdoor;
O2IProfile = o2iProfile;
FloorNumber = floorNumber;
Height_m = height_m;
PopulationClass = populationClass;
PopulationSeed = repmat(seed, nUE, 1);
AssignmentSource = repmat( ...
    "configured_fixed_quota_seeded_permutation", nUE, 1);
population = table(UEID, PopulationProfile, PopulationClass, Indoor, ...
    Outdoor, O2IProfile, FloorNumber, Height_m, PopulationSeed, ...
    AssignmentSource);
end
