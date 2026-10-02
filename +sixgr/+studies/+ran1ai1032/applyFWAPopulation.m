function ue = applyFWAPopulation(ue, population)
%APPLYFWAPOPULATION Bind a typed FWA population to a dropped UE geometry.

if ~isstruct(ue) || ~isfield(ue, "K") || ~isfield(ue, "pos_m")
    error("sixgr:ran1ai1032:InvalidUEGeometry", ...
        "UE input must contain K and pos_m.");
end
if ~istable(population) || height(population) ~= double(ue.K) || ...
        any(population.UEID ~= double(ue.id(:)))
    error("sixgr:ran1ai1032:FWAPopulationIdentityMismatch", ...
        "FWA population rows must match the dropped UE identities exactly.");
end
ue.indoor = logical(population.Indoor);
ue.pos_m(:, 3) = double(population.Height_m);
ue.fwa_population_profile = string(population.PopulationProfile);
ue.fwa_population_class = string(population.PopulationClass);
ue.o2i_model = string(population.O2IProfile);
ue.floor_number = double(population.FloorNumber);
ue.population_assignment_source = string(population.AssignmentSource);
ue.population_table = population;
end
