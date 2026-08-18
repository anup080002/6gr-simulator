function catalog = frcCatalog(catalogPath)
%FRCCATALOG Load and validate the selected Release 18 FRC operating points.
%
%   CATALOG = sixgr.conformance.frcCatalog() loads the repository catalog
%   simulator/configs/conformance/nr_frc_release18.yaml. The catalog
%   contains the Phase 1 gate anchors plus selected representative
%   coverage; it is not a complete transcription of either standard's
%   Annex A.
%
%   CATALOG = sixgr.conformance.frcCatalog(PATH) loads an alternate catalog.
%   Alternate paths are useful for schema-negative tests; the same strict
%   validation is always applied.

if nargin < 1
    catalogPath = "";
end
if ~(ischar(catalogPath) || (isstring(catalogPath) && isscalar(catalogPath)))
    error("sixgr:conformance:InvalidCatalogPath", ...
        "FRC catalog path must be a character vector or string scalar.");
end

catalogPath = string(catalogPath);
if strlength(catalogPath) == 0
    catalogPath = localDefaultCatalogPath();
end
catalogPath = localResolveCatalogPath(catalogPath);

if exist(char(catalogPath), "file") ~= 2
    error("sixgr:conformance:FRCatalogNotFound", ...
        "FRC catalog file not found: %s", catalogPath);
end

try
    catalog = sixgr.lls6g.config.readConfigFile(catalogPath);
catch cause
    failure = MException("sixgr:conformance:FRCatalogReadFailed", ...
        "Unable to read FRC catalog '%s'.", catalogPath);
    failure = addCause(failure, cause);
    throwAsCaller(failure);
end

catalog = localInstallRuntimeFeatureDefaults(catalog, catalogPath);
localValidateCatalog(catalog, catalogPath);
end

function catalog = localInstallRuntimeFeatureDefaults(catalog, catalogPath)
if ~isstruct(catalog) || ~isfield(catalog, "runtime_feature_defaults")
    localInvalid(catalogPath, "catalog.runtime_feature_defaults", ...
        "is required so conformance waveform features are YAML-owned");
end
defaults = catalog.runtime_feature_defaults;
localRequireScalarStruct(defaults, "catalog.runtime_feature_defaults", catalogPath);
localRequireFields(defaults, {"authority", "ssb_enabled", ...
    "csi_rs_enabled", "pdsch_precoder_normalization_convention", ...
    "standard_downlink_timeline", "ptrs"}, ...
    "catalog.runtime_feature_defaults", catalogPath);
if localRequireNonemptyText(defaults.authority, ...
        "catalog.runtime_feature_defaults.authority", catalogPath) ~= ...
        "frc_catalog_yaml"
    localInvalid(catalogPath, "catalog.runtime_feature_defaults.authority", ...
        "must be 'frc_catalog_yaml'");
end
localRequireLogicalScalar(defaults.ssb_enabled, ...
    "catalog.runtime_feature_defaults.ssb_enabled", catalogPath);
localRequireLogicalScalar(defaults.csi_rs_enabled, ...
    "catalog.runtime_feature_defaults.csi_rs_enabled", catalogPath);
localRequireEnumText(defaults.pdsch_precoder_normalization_convention, ...
    "unit_total_power", ...
    "catalog.runtime_feature_defaults.pdsch_precoder_normalization_convention", ...
    catalogPath);
localValidatePTRS(defaults.ptrs, "catalog.runtime_feature_defaults", catalogPath);
localValidateStandardDownlinkTimeline(defaults.standard_downlink_timeline, ...
    "catalog.runtime_feature_defaults.standard_downlink_timeline", catalogPath);

entries = catalog.entries;
for idx = 1:numel(entries)
    if iscell(entries)
        entry = entries{idx};
    else
        entry = entries(idx);
    end
    if ~isfield(entry, "ptrs")
        entry.ptrs = defaults.ptrs;
    end
    entry.runtime_feature_authority = struct( ...
        "source", "frc_catalog_yaml", ...
        "ssb_enabled", logical(defaults.ssb_enabled), ...
        "csi_rs_enabled", logical(defaults.csi_rs_enabled), ...
        "pdsch_precoder_normalization_convention", string( ...
            defaults.pdsch_precoder_normalization_convention));
    if string(entry.direction) == "downlink"
        entry.standard_downlink_timeline = defaults.standard_downlink_timeline;
    end
    if iscell(entries)
        entries{idx} = entry;
    else
        entries(idx) = entry;
    end
end
catalog.entries = entries;
end

function localValidateStandardDownlinkTimeline(input, scope, catalogPath)
localRequireScalarStruct(input, scope, catalogPath);
localRequireFields(input, {"enabled", "standard_reference", ...
    "applicable_duplex_mode", "applicable_subcarrier_spacing_khz", ...
    "reference_carrier_frequency_hz", "period_slots", "ssb_pbch", ...
    "pdcch", "tracking_csirs", ...
    "acquisition_nzp_csirs", "acquisition_zp_csirs", "ocng"}, ...
    scope, catalogPath);
localRequireLogicalScalar(input.enabled, scope + ".enabled", catalogPath);
localRequireNonemptyText(input.standard_reference, ...
    scope + ".standard_reference", catalogPath);
localRequireEnumText(input.applicable_duplex_mode, "FDD", ...
    scope + ".applicable_duplex_mode", catalogPath);
localRequireEnumNumber(input.applicable_subcarrier_spacing_khz, 15, ...
    scope + ".applicable_subcarrier_spacing_khz", catalogPath);
localRequirePositiveFiniteScalar(input.reference_carrier_frequency_hz, ...
    scope + ".reference_carrier_frequency_hz", catalogPath);
if localRequirePositiveInteger(input.period_slots, ...
        scope + ".period_slots", catalogPath) ~= 20
    localInvalid(catalogPath, scope + ".period_slots", ...
        "must be 20 for the selected 15 kHz FDD timeline");
end

ssb = input.ssb_pbch;
localRequireScalarStruct(ssb, scope + ".ssb_pbch", catalogPath);
localRequireFields(ssb, {"enabled", "slot", "periodicity_ms", ...
    "selected_ssb_index", "block_pattern", "lmax", "active_bitmap", ...
    "n_crb_ssb", "k_ssb", ...
    "physical_antenna_index", "epre_relative_to_sss_db"}, ...
    scope + ".ssb_pbch", catalogPath);
localRequireLogicalScalar(ssb.enabled, scope + ".ssb_pbch.enabled", catalogPath);
localRequireNonnegativeInteger(ssb.slot, scope + ".ssb_pbch.slot", catalogPath);
localRequirePositiveFiniteScalar(ssb.periodicity_ms, ...
    scope + ".ssb_pbch.periodicity_ms", catalogPath);
localRequireNonnegativeInteger(ssb.selected_ssb_index, ...
    scope + ".ssb_pbch.selected_ssb_index", catalogPath);
localRequireEnumText(ssb.block_pattern, "Case A", ...
    scope + ".ssb_pbch.block_pattern", catalogPath);
localRequireEnumNumber(ssb.lmax, 8, scope + ".ssb_pbch.lmax", catalogPath);
activeBitmap = localRequireIntegerVector(ssb.active_bitmap, ...
    scope + ".ssb_pbch.active_bitmap", catalogPath, false);
if ~isequal(double(activeBitmap(:).'), [1 0 0 0 0 0 0 0])
    localInvalid(catalogPath, scope + ".ssb_pbch.active_bitmap", ...
        "must select only the first of eight Case-A candidates");
end
localRequireNonnegativeInteger(ssb.n_crb_ssb, ...
    scope + ".ssb_pbch.n_crb_ssb", catalogPath);
localRequireNonnegativeInteger(ssb.k_ssb, ...
    scope + ".ssb_pbch.k_ssb", catalogPath);
localRequireNonnegativeInteger(ssb.physical_antenna_index, ...
    scope + ".ssb_pbch.physical_antenna_index", catalogPath);
localRequireFiniteScalar(ssb.epre_relative_to_sss_db, ...
    scope + ".ssb_pbch.epre_relative_to_sss_db", catalogPath);

pdcch = input.pdcch;
localRequireScalarStruct(pdcch, scope + ".pdcch", catalogPath);
localRequireFields(pdcch, {"enabled", "monitoring_slots", ...
    "symbol_indices", "coreset_prbs", "aggregation_level", ...
    "candidate_count", "cce_to_reg_mapping", "reg_bundle_size", ...
    "dci_format", "tci_state", "epre_relative_to_sss_db", ...
    "precoder_selection"}, scope + ".pdcch", catalogPath);
localRequireLogicalScalar(pdcch.enabled, scope + ".pdcch.enabled", catalogPath);
localRequireEnumText(pdcch.monitoring_slots, "every_slot", ...
    scope + ".pdcch.monitoring_slots", catalogPath);
symbols = localRequireIntegerVector(pdcch.symbol_indices, ...
    scope + ".pdcch.symbol_indices", catalogPath, false);
if ~isequal(double(symbols(:).'), [0 1])
    localInvalid(catalogPath, scope + ".pdcch.symbol_indices", ...
        "must be [0,1]");
end
if localRequirePositiveInteger(pdcch.coreset_prbs, ...
        scope + ".pdcch.coreset_prbs", catalogPath) ~= 48
    localInvalid(catalogPath, scope + ".pdcch.coreset_prbs", ...
        "must be 48 for the selected 10 MHz, 15 kHz FRCs");
end
localRequireEnumNumber(pdcch.aggregation_level, 8, ...
    scope + ".pdcch.aggregation_level", catalogPath);
localRequireEnumNumber(pdcch.candidate_count, 1, ...
    scope + ".pdcch.candidate_count", catalogPath);
localRequireEnumText(pdcch.cce_to_reg_mapping, "noninterleaved", ...
    scope + ".pdcch.cce_to_reg_mapping", catalogPath);
localRequireEnumNumber(pdcch.reg_bundle_size, 6, ...
    scope + ".pdcch.reg_bundle_size", catalogPath);
localRequireEnumText(pdcch.dci_format, "1_1", ...
    scope + ".pdcch.dci_format", catalogPath);
localRequireNonnegativeInteger(pdcch.tci_state, ...
    scope + ".pdcch.tci_state", catalogPath);
localRequireFiniteScalar(pdcch.epre_relative_to_sss_db, ...
    scope + ".pdcch.epre_relative_to_sss_db", catalogPath);
localRequireEnumText(pdcch.precoder_selection, ...
    "single_panel_type1_random_per_reg_bundle_per_slot", ...
    scope + ".pdcch.precoder_selection", catalogPath);

tracking = input.tracking_csirs;
localRequireScalarStruct(tracking, scope + ".tracking_csirs", catalogPath);
localRequireFields(tracking, {"enabled", "row_number", "port_count", ...
    "density", "subcarrier_location", "symbol_locations", ...
    "period_slots", "slot_offsets", "rb_offset", "num_rbs", ...
    "physical_antenna_index", "epre_relative_to_sss_db"}, ...
    scope + ".tracking_csirs", catalogPath);
localRequireLogicalScalar(tracking.enabled, ...
    scope + ".tracking_csirs.enabled", catalogPath);
localRequireEnumNumber(tracking.row_number, 1, ...
    scope + ".tracking_csirs.row_number", catalogPath);
localRequireEnumNumber(tracking.port_count, 1, ...
    scope + ".tracking_csirs.port_count", catalogPath);
localRequireEnumText(tracking.density, "three", ...
    scope + ".tracking_csirs.density", catalogPath);
localRequireNonnegativeInteger(tracking.subcarrier_location, ...
    scope + ".tracking_csirs.subcarrier_location", catalogPath);
trackingSymbols = localRequireIntegerVector(tracking.symbol_locations, ...
    scope + ".tracking_csirs.symbol_locations", catalogPath, false);
trackingOffsets = localRequireIntegerVector(tracking.slot_offsets, ...
    scope + ".tracking_csirs.slot_offsets", catalogPath, false);
if ~isequal(double(trackingSymbols(:).'), [6 10]) || ...
        ~isequal(double(trackingOffsets(:).'), [10 11])
    localInvalid(catalogPath, scope + ".tracking_csirs", ...
        "must encode symbols [6,10] and slot offsets [10,11]");
end
localRequireEnumNumber(tracking.period_slots, 20, ...
    scope + ".tracking_csirs.period_slots", catalogPath);
localRequireNonnegativeInteger(tracking.rb_offset, ...
    scope + ".tracking_csirs.rb_offset", catalogPath);
localRequirePositiveInteger(tracking.num_rbs, ...
    scope + ".tracking_csirs.num_rbs", catalogPath);
localRequireNonnegativeInteger(tracking.physical_antenna_index, ...
    scope + ".tracking_csirs.physical_antenna_index", catalogPath);
localRequireFiniteScalar(tracking.epre_relative_to_sss_db, ...
    scope + ".tracking_csirs.epre_relative_to_sss_db", catalogPath);

localValidateAcquisitionCSIRS(input.acquisition_nzp_csirs, true, ...
    scope + ".acquisition_nzp_csirs", catalogPath);
localValidateAcquisitionCSIRS(input.acquisition_zp_csirs, false, ...
    scope + ".acquisition_zp_csirs", catalogPath);

ocng = input.ocng;
localRequireScalarStruct(ocng, scope + ".ocng", catalogPath);
localRequireFields(ocng, {"enabled", "pattern", "content", ...
    "control_region_transmission", "data_region_transmission", ...
    "epre_relative_to_sss_db"}, scope + ".ocng", catalogPath);
localRequireLogicalScalar(ocng.enabled, scope + ".ocng.enabled", catalogPath);
localRequireEnumText(ocng.pattern, "OP.1 FDD", ...
    scope + ".ocng.pattern", catalogPath);
localRequireEnumText(ocng.content, "uncorrelated_pseudorandom_qpsk", ...
    scope + ".ocng.content", catalogPath);
localRequireEnumText(ocng.control_region_transmission, "single_tx_port", ...
    scope + ".ocng.control_region_transmission", catalogPath);
localRequireEnumText(ocng.data_region_transmission, ...
    "spatial_multiplexing_same_precoder_dimensions_as_pdsch", ...
    scope + ".ocng.data_region_transmission", catalogPath);
localRequireFiniteScalar(ocng.epre_relative_to_sss_db, ...
    scope + ".ocng.epre_relative_to_sss_db", catalogPath);
end

function localValidateAcquisitionCSIRS(input, nzp, scope, catalogPath)
localRequireScalarStruct(input, scope, catalogPath);
common = {"enabled", "first_subcarrier_index", "first_symbol_index", ...
    "density", "period_slots", "slot_offset", "rb_offset", "num_rbs"};
if nzp
    localRequireFields(input, [common, {"port_count_source", ...
        "row_by_port_count", "cdm_type_by_port_count", "qcl_tci_state", ...
        "direct_port_to_physical_antenna_mapping"}], scope, catalogPath);
else
    localRequireFields(input, [common, {"row_number", "port_count", ...
        "cdm_type"}], scope, catalogPath);
end
localRequireLogicalScalar(input.enabled, scope + ".enabled", catalogPath);
localRequireNonnegativeInteger(input.first_subcarrier_index, ...
    scope + ".first_subcarrier_index", catalogPath);
localRequireNonnegativeInteger(input.first_symbol_index, ...
    scope + ".first_symbol_index", catalogPath);
localRequireEnumText(input.density, "one", scope + ".density", catalogPath);
localRequireEnumNumber(input.period_slots, 20, ...
    scope + ".period_slots", catalogPath);
localRequireNonnegativeInteger(input.slot_offset, ...
    scope + ".slot_offset", catalogPath);
localRequireNonnegativeInteger(input.rb_offset, ...
    scope + ".rb_offset", catalogPath);
localRequirePositiveInteger(input.num_rbs, scope + ".num_rbs", catalogPath);
if nzp
    localRequireEnumText(input.port_count_source, ...
        "number_of_transmit_antennas", scope + ".port_count_source", catalogPath);
    rows = localRequireIntegerVector(input.row_by_port_count, ...
        scope + ".row_by_port_count", catalogPath, false);
    cdm = localRequireTextVector(input.cdm_type_by_port_count, ...
        scope + ".cdm_type_by_port_count", catalogPath);
    if numel(rows) ~= 8 || numel(cdm) ~= 8
        localInvalid(catalogPath, scope, ...
            "must contain eight row/CDM entries for port counts 1 through 8");
    end
    localRequireNonnegativeInteger(input.qcl_tci_state, ...
        scope + ".qcl_tci_state", catalogPath);
    localRequireLogicalScalar(input.direct_port_to_physical_antenna_mapping, ...
        scope + ".direct_port_to_physical_antenna_mapping", catalogPath);
else
    localRequireEnumNumber(input.row_number, 5, ...
        scope + ".row_number", catalogPath);
    localRequireEnumNumber(input.port_count, 4, ...
        scope + ".port_count", catalogPath);
    localRequireEnumText(input.cdm_type, "fd-CDM2", ...
        scope + ".cdm_type", catalogPath);
end
end

function localValidateCatalog(catalog, catalogPath)
localRequireScalarStruct(catalog, "catalog", catalogPath);
localRequireFields(catalog, { ...
    "schema_version", "catalog_id", "research_class", "catalog_status", ...
    "expected_entry_count", "coverage", "standards", "project_diagnostic_policy", ...
    "runtime_feature_defaults", "entries"}, "catalog", catalogPath);

localRequireNonemptyText(catalog.schema_version, "catalog.schema_version", catalogPath);
localRequireNonemptyText(catalog.catalog_id, "catalog.catalog_id", catalogPath);
researchClass = localRequireNonemptyText( ...
    catalog.research_class, "catalog.research_class", catalogPath);
if researchClass ~= "baseline_benchmark"
    localInvalid(catalogPath, "catalog.research_class", ...
        "must be 'baseline_benchmark' for normative FRC reference data");
end
localRequireNonemptyText(catalog.catalog_status, "catalog.catalog_status", catalogPath);

expectedCount = localRequirePositiveInteger(catalog.expected_entry_count, ...
    "catalog.expected_entry_count", catalogPath);
localValidateStandards(catalog.standards, catalogPath);
localValidateProjectPolicy(catalog.project_diagnostic_policy, catalogPath);

entries = catalog.entries;
if ~(isstruct(entries) || iscell(entries)) || isempty(entries)
    localInvalid(catalogPath, "catalog.entries", ...
        "must be a nonempty sequence of entry objects");
end

if numel(entries) ~= expectedCount
    localInvalid(catalogPath, "catalog.entries", sprintf( ...
        "contains %d entries but expected_entry_count is %d", ...
        numel(entries), expectedCount));
end

entryIds = strings(numel(entries), 1);
lookupKeys = strings(numel(entries), 1);
for idx = 1:numel(entries)
    entry = localSequenceItem(entries, idx, "catalog.entries", catalogPath);
    [entryIds(idx), lookupKeys(idx)] = localValidateEntry(entry, idx, ...
        catalog.standards, catalogPath);
end

if numel(unique(entryIds)) ~= numel(entryIds)
    duplicates = localDuplicates(entryIds);
    localInvalid(catalogPath, "catalog.entries.id", ...
        "must be unique; duplicate value(s): " + strjoin(duplicates, ", "));
end
if numel(unique(lookupKeys)) ~= numel(lookupKeys)
    duplicates = localDuplicates(lookupKeys);
    localInvalid(catalogPath, "catalog.entries", ...
        "must have unique frc_id + condition_id pairs; duplicate pair(s): " + ...
        strjoin(duplicates, ", "));
end
localValidateCoverage(catalog.coverage, entries, expectedCount, catalogPath);
end

function localValidateCoverage(coverage, entries, expectedCount, catalogPath)
scope = "catalog.coverage";
localRequireScalarStruct(coverage, scope, catalogPath);
localRequireFields(coverage, { ...
    "scope_kind", "complete_annex_catalog", "scope_statement", ...
    "operating_point_count", "unique_frc_count", "downlink", "uplink", ...
    "standards_role_boundary"}, scope, catalogPath);

scopeKind = localRequireNonemptyText(coverage.scope_kind, ...
    scope + ".scope_kind", catalogPath);
if scopeKind ~= "selected_phase1_conformance_operating_points"
    localInvalid(catalogPath, scope + ".scope_kind", ...
        "must be 'selected_phase1_conformance_operating_points'");
end
isComplete = localRequireLogicalScalar(coverage.complete_annex_catalog, ...
    scope + ".complete_annex_catalog", catalogPath);
if isComplete
    localInvalid(catalogPath, scope + ".complete_annex_catalog", ...
        "must be false because this selected catalog is not a complete transcription of either Annex A");
end
localRequireNonemptyText(coverage.scope_statement, ...
    scope + ".scope_statement", catalogPath);
operatingPointCount = localRequirePositiveInteger(coverage.operating_point_count, ...
    scope + ".operating_point_count", catalogPath);
if operatingPointCount ~= expectedCount
    localInvalid(catalogPath, scope + ".operating_point_count", ...
        "must equal catalog.expected_entry_count");
end

[directions, frcIds, modulations, layers] = localCoverageVectors(entries, catalogPath);
uniqueCount = localRequirePositiveInteger(coverage.unique_frc_count, ...
    scope + ".unique_frc_count", catalogPath);
if uniqueCount ~= numel(unique(frcIds))
    localInvalid(catalogPath, scope + ".unique_frc_count", ...
        "must equal the number of unique catalog.entries.frc_id values");
end

localValidateDirectionCoverage(coverage.downlink, "downlink", ...
    "ts_38_101_4", directions, frcIds, modulations, layers, catalogPath);
localValidateDirectionCoverage(coverage.uplink, "uplink", ...
    "ts_38_104", directions, frcIds, modulations, layers, catalogPath);
localRequireNonemptyText(coverage.standards_role_boundary, ...
    scope + ".standards_role_boundary", catalogPath);
end

function localValidateDirectionCoverage(input, direction, standardKey, ...
        directions, frcIds, modulations, layers, catalogPath)
scope = "catalog.coverage." + direction;
localRequireScalarStruct(input, scope, catalogPath);
localRequireFields(input, { ...
    "standard_key", "standards_role", "operating_point_count", ...
    "unique_frc_count", "represented_modulations", ...
    "represented_layers", "known_gaps"}, scope, catalogPath);

actualStandardKey = localRequireNonemptyText(input.standard_key, ...
    scope + ".standard_key", catalogPath);
if actualStandardKey ~= standardKey
    localInvalid(catalogPath, scope + ".standard_key", ...
        "must be '" + standardKey + "'");
end
localRequireNonemptyText(input.standards_role, ...
    scope + ".standards_role", catalogPath);
selected = directions == direction;
operatingPointCount = localRequirePositiveInteger(input.operating_point_count, ...
    scope + ".operating_point_count", catalogPath);
if operatingPointCount ~= nnz(selected)
    localInvalid(catalogPath, scope + ".operating_point_count", ...
        "must equal the number of entries with direction='" + direction + "'");
end
uniqueCount = localRequirePositiveInteger(input.unique_frc_count, ...
    scope + ".unique_frc_count", catalogPath);
if uniqueCount ~= numel(unique(frcIds(selected)))
    localInvalid(catalogPath, scope + ".unique_frc_count", ...
        "must equal the number of unique FRC ids for this direction");
end

representedModulations = sort(localRequireTextVector( ...
    input.represented_modulations, scope + ".represented_modulations", catalogPath));
actualModulations = sort(unique(modulations(selected)));
if ~isequal(representedModulations(:), actualModulations(:))
    localInvalid(catalogPath, scope + ".represented_modulations", ...
        "must exactly describe the modulations present in catalog.entries");
end
representedLayers = sort(localRequireIntegerVector(input.represented_layers, ...
    scope + ".represented_layers", catalogPath, false));
actualLayers = sort(unique(layers(selected)));
if ~isequal(representedLayers(:), actualLayers(:))
    localInvalid(catalogPath, scope + ".represented_layers", ...
        "must exactly describe the layer counts present in catalog.entries");
end
localRequireNonemptyTextSequence(input.known_gaps, ...
    scope + ".known_gaps", catalogPath);
end

function [directions, frcIds, modulations, layers] = ...
        localCoverageVectors(entries, catalogPath)
n = numel(entries);
directions = strings(n, 1);
frcIds = strings(n, 1);
modulations = strings(n, 1);
layers = zeros(n, 1);
for idx = 1:n
    entry = localSequenceItem(entries, idx, "catalog.entries", catalogPath);
    directions(idx) = localRequireEnumText(entry.direction, ...
        ["downlink", "uplink"], sprintf("catalog.entries(%d).direction", idx), ...
        catalogPath);
    frcIds(idx) = localRequireNonemptyText(entry.frc_id, ...
        sprintf("catalog.entries(%d).frc_id", idx), catalogPath);
    localRequireScalarStruct(entry.coding, ...
        sprintf("catalog.entries(%d).coding", idx), catalogPath);
    modulations(idx) = localRequireEnumText(entry.coding.modulation, ...
        ["QPSK", "16QAM", "64QAM", "256QAM"], ...
        sprintf("catalog.entries(%d).coding.modulation", idx), catalogPath);
    localRequireScalarStruct(entry.mimo, ...
        sprintf("catalog.entries(%d).mimo", idx), catalogPath);
    layers(idx) = localRequirePositiveInteger(entry.mimo.layers, ...
        sprintf("catalog.entries(%d).mimo.layers", idx), catalogPath);
end
end

function localValidateStandards(standards, catalogPath)
localRequireScalarStruct(standards, "catalog.standards", catalogPath);
localRequireFields(standards, {"ts_38_101_4", "ts_38_104"}, ...
    "catalog.standards", catalogPath);

keys = ["ts_38_101_4", "ts_38_104"];
for idx = 1:numel(keys)
    key = keys(idx);
    entry = standards.(key);
    scope = "catalog.standards." + key;
    localRequireScalarStruct(entry, scope, catalogPath);
    localRequireFields(entry, ...
        {"document", "version", "release", "source_url", "retrieved_on"}, ...
        scope, catalogPath);
    localRequireNonemptyText(entry.document, scope + ".document", catalogPath);
    localRequireNonemptyText(entry.version, scope + ".version", catalogPath);
    localRequirePositiveInteger(entry.release, scope + ".release", catalogPath);
    sourceUrl = localRequireNonemptyText( ...
        entry.source_url, scope + ".source_url", catalogPath);
    if ~startsWith(sourceUrl, "https://")
        localInvalid(catalogPath, scope + ".source_url", ...
            "must be an HTTPS URL to the normative document");
    end
    localRequireNonemptyText(entry.retrieved_on, scope + ".retrieved_on", catalogPath);
end
end

function localValidateProjectPolicy(policy, catalogPath)
scope = "catalog.project_diagnostic_policy";
localRequireScalarStruct(policy, scope, catalogPath);
localRequireFields(policy, { ...
    "policy_id", "normative", "comparison_mode", "tolerance_db", ...
    "normative_requirement_semantics", "warning"}, scope, catalogPath);

localRequireNonemptyText(policy.policy_id, scope + ".policy_id", catalogPath);
isNormative = localRequireLogicalScalar(policy.normative, ...
    scope + ".normative", catalogPath);
if isNormative
    localInvalid(catalogPath, scope + ".normative", ...
        "must be false because symmetric waterfall crossing is a project diagnostic, not a 3GPP requirement");
end
comparisonMode = localRequireNonemptyText( ...
    policy.comparison_mode, scope + ".comparison_mode", catalogPath);
if comparisonMode ~= "symmetric_snr_at_target_crossing"
    localInvalid(catalogPath, scope + ".comparison_mode", ...
        "must be 'symmetric_snr_at_target_crossing'");
end
localRequirePositiveFiniteScalar(policy.tolerance_db, ...
    scope + ".tolerance_db", catalogPath);
semantics = localRequireNonemptyText(policy.normative_requirement_semantics, ...
    scope + ".normative_requirement_semantics", catalogPath);
if semantics ~= "one_sided_minimum_performance_at_required_snr"
    localInvalid(catalogPath, scope + ".normative_requirement_semantics", ...
        "must explicitly preserve the one-sided 3GPP operating-point requirement");
end
localRequireNonemptyText(policy.warning, scope + ".warning", catalogPath);
end

function [entryId, lookupKey] = localValidateEntry(entry, index, standards, catalogPath)
scope = sprintf("catalog.entries(%d)", index);
localRequireScalarStruct(entry, scope, catalogPath);
localRequireFields(entry, { ...
    "id", "frc_id", "research_class", ...
    "direction", "physical_channel", "receiver_role", "test_interface", ...
    "standard", "carrier", "allocation", "waveform", "coding", "dmrs", ...
    "mimo", "condition", "harq", "requirement"}, ...
    scope, catalogPath);

entryId = localRequireNonemptyText(entry.id, scope + ".id", catalogPath);
frcId = localRequireNonemptyText(entry.frc_id, scope + ".frc_id", catalogPath);

recordClass = localRequireNonemptyText(entry.research_class, ...
    scope + ".research_class", catalogPath);
if recordClass ~= "baseline_benchmark"
    localInvalid(catalogPath, scope + ".research_class", ...
        "must be 'baseline_benchmark'");
end

direction = localRequireEnumText(entry.direction, ["downlink", "uplink"], ...
    scope + ".direction", catalogPath);
physicalChannel = localRequireEnumText(entry.physical_channel, ...
    ["PDSCH", "PUSCH"], scope + ".physical_channel", catalogPath);
receiverRole = localRequireEnumText(entry.receiver_role, ...
    ["UE-Rx", "gNB-Rx"], scope + ".receiver_role", catalogPath);
localRequireEnumText(entry.test_interface, ["conducted", "radiated_RIB"], ...
    scope + ".test_interface", catalogPath);

if direction == "downlink"
    if physicalChannel ~= "PDSCH" || receiverRole ~= "UE-Rx"
        localInvalid(catalogPath, scope, ...
            "downlink records must use physical_channel='PDSCH' and receiver_role='UE-Rx'");
    end
else
    if physicalChannel ~= "PUSCH" || receiverRole ~= "gNB-Rx"
        localInvalid(catalogPath, scope, ...
            "uplink records must use physical_channel='PUSCH' and receiver_role='gNB-Rx'");
    end
end

localValidateStandard(entry.standard, standards, direction, scope, catalogPath);
carrier = localValidateCarrier(entry.carrier, scope, catalogPath);
allocation = localValidateAllocation(entry.allocation, direction, scope, catalogPath);
localValidateWaveform(entry.waveform, direction, scope, catalogPath);
coding = localValidateCoding(entry.coding, direction, scope, catalogPath);
dmrs = localValidateDMRS(entry.dmrs, direction, scope, catalogPath);
if isfield(entry, "ptrs")
    localValidatePTRS(entry.ptrs, scope, catalogPath);
end
mimo = localValidateMIMO(entry.mimo, scope, catalogPath);
condition = localValidateCondition(entry.condition, scope, catalogPath);
conditionId = localRequireNonemptyText(entry.condition.id, ...
    scope + ".condition.id", catalogPath);
lookupKey = frcId + " | " + conditionId;
localValidateHARQ(entry.harq, scope, catalogPath);
localValidateRequirement(entry.requirement, scope, catalogPath);

if carrier.prb_end ~= carrier.prb_start + carrier.n_prb - 1
    localInvalid(catalogPath, scope + ".carrier.prb_end", ...
        "must equal prb_start + n_prb - 1");
end
if allocation.start_symbol + allocation.symbol_length > 14
    localInvalid(catalogPath, scope + ".allocation", ...
        "start_symbol + symbol_length must not exceed a normal-CP 14-symbol slot");
end
if allocation.data_bearing_symbols > allocation.symbol_length
    localInvalid(catalogPath, scope + ".allocation.data_bearing_symbols", ...
        "must not exceed allocation.symbol_length");
end
if mimo.layers ~= numel(dmrs.ports)
    localInvalid(catalogPath, scope + ".dmrs.ports", ...
        "must contain exactly one port per MIMO layer");
end
if mimo.tx_antennas < mimo.layers
    localInvalid(catalogPath, scope + ".mimo.tx_antennas", ...
        "must be at least the configured number of layers");
end
if condition.model == "AWGN" && ...
        (condition.delay_spread_ns ~= 0 || condition.max_doppler_hz ~= 0)
    localInvalid(catalogPath, scope + ".condition", ...
        "AWGN records must have zero delay spread and zero Doppler");
end
if startsWith(condition.model, "TDL-") && ...
        (condition.delay_spread_ns <= 0 || condition.max_doppler_hz < 0)
    localInvalid(catalogPath, scope + ".condition", ...
        "TDL records require a positive delay spread and a nonnegative Doppler");
end
if coding.code_blocks > 1 && coding.code_block_crc_bits ~= 24
    localInvalid(catalogPath, scope + ".coding.code_block_crc_bits", ...
        "must be 24 when more than one LDPC code block is present");
end
if coding.code_blocks == 1 && coding.code_block_crc_bits ~= 0
    localInvalid(catalogPath, scope + ".coding.code_block_crc_bits", ...
        "must be 0 when no code-block CRC is present");
end
end

function localValidateStandard(standardInput, standards, direction, recordScope, catalogPath)
scope = recordScope + ".standard";
localRequireScalarStruct(standardInput, scope, catalogPath);
localRequireFields(standardInput, { ...
    "standard_key", "document", "version", "release", "source_url", ...
    "frc_definition_clause", "frc_definition_table", ...
    "requirement_clause", "test_parameter_tables", "requirement_tables", ...
    "snr_definition_clause"}, ...
    scope, catalogPath);

standardKey = localRequireNonemptyText( ...
    standardInput.standard_key, scope + ".standard_key", catalogPath);
if ~isfield(standards, char(standardKey))
    localInvalid(catalogPath, scope + ".standard_key", ...
        "must name an entry in catalog.standards");
end
if direction == "downlink" && standardKey ~= "ts_38_101_4"
    localInvalid(catalogPath, scope + ".standard_key", ...
        "downlink UE-Rx PDSCH requirements must cite ts_38_101_4");
elseif direction == "uplink" && standardKey ~= "ts_38_104"
    localInvalid(catalogPath, scope + ".standard_key", ...
        "uplink gNB-Rx PUSCH requirements must cite ts_38_104");
end

standard = standards.(standardKey);
document = localRequireNonemptyText(standardInput.document, scope + ".document", catalogPath);
version = localRequireNonemptyText(standardInput.version, scope + ".version", catalogPath);
release = localRequirePositiveInteger(standardInput.release, scope + ".release", catalogPath);
sourceUrl = localRequireNonemptyText(standardInput.source_url, ...
    scope + ".source_url", catalogPath);
if document ~= string(standard.document) || version ~= string(standard.version) || ...
        release ~= standard.release || sourceUrl ~= string(standard.source_url)
    localInvalid(catalogPath, scope, ...
        "document, version, release, and source_url must match the selected catalog.standards entry");
end

localRequireNonemptyText(standardInput.frc_definition_clause, ...
    scope + ".frc_definition_clause", catalogPath);
localRequireNonemptyText(standardInput.frc_definition_table, ...
    scope + ".frc_definition_table", catalogPath);
localRequireNonemptyText(standardInput.requirement_clause, ...
    scope + ".requirement_clause", catalogPath);
localRequireNonemptyTextSequence(standardInput.test_parameter_tables, ...
    scope + ".test_parameter_tables", catalogPath);
localRequireNonemptyTextSequence(standardInput.requirement_tables, ...
    scope + ".requirement_tables", catalogPath);
localRequireNonemptyText(standardInput.snr_definition_clause, ...
    scope + ".snr_definition_clause", catalogPath);
end

function carrier = localValidateCarrier(carrierInput, recordScope, catalogPath)
scope = recordScope + ".carrier";
localRequireScalarStruct(carrierInput, scope, catalogPath);
localRequireFields(carrierInput, { ...
    "frequency_range", "duplex_mode", "channel_bandwidth_mhz", ...
    "subcarrier_spacing_khz", "cyclic_prefix", "n_prb", ...
    "prb_start", "prb_end"}, scope, catalogPath);

frequencyRange = localRequireEnumText( ...
    carrierInput.frequency_range, ["FR1", "FR2"], ...
    scope + ".frequency_range", catalogPath);
if isfield(carrierInput, "frequency_range_subrange")
    localRequireEnumText(carrierInput.frequency_range_subrange, ...
        ["FR2-1", "FR2-2"], scope + ".frequency_range_subrange", catalogPath);
    if frequencyRange ~= "FR2"
        localInvalid(catalogPath, scope + ".frequency_range_subrange", ...
            "may only be specified when frequency_range is 'FR2'");
    end
end
localRequireEnumText(carrierInput.duplex_mode, ...
    ["FDD", "TDD", "FDD_and_TDD"], scope + ".duplex_mode", catalogPath);
localRequirePositiveFiniteScalar(carrierInput.channel_bandwidth_mhz, ...
    scope + ".channel_bandwidth_mhz", catalogPath);
localRequirePositiveFiniteScalar(carrierInput.subcarrier_spacing_khz, ...
    scope + ".subcarrier_spacing_khz", catalogPath);
localRequireEnumText(carrierInput.cyclic_prefix, ["normal", "extended"], ...
    scope + ".cyclic_prefix", catalogPath);
carrier.n_prb = localRequirePositiveInteger( ...
    carrierInput.n_prb, scope + ".n_prb", catalogPath);
carrier.prb_start = localRequireNonnegativeInteger( ...
    carrierInput.prb_start, scope + ".prb_start", catalogPath);
carrier.prb_end = localRequireNonnegativeInteger( ...
    carrierInput.prb_end, scope + ".prb_end", catalogPath);
end

function allocation = localValidateAllocation(input, direction, recordScope, catalogPath)
scope = recordScope + ".allocation";
localRequireScalarStruct(input, scope, catalogPath);
localRequireFields(input, { ...
    "mapping_type", "start_symbol", "symbol_length", ...
    "data_bearing_symbols", "full_bandwidth", "frequency_hopping", ...
    "resource_allocation_type", "vrb_to_prb_mapping"}, scope, catalogPath);

localRequireEnumText(input.mapping_type, ["A", "B"], ...
    scope + ".mapping_type", catalogPath);
allocation.start_symbol = localRequireNonnegativeInteger( ...
    input.start_symbol, scope + ".start_symbol", catalogPath);
allocation.symbol_length = localRequirePositiveInteger( ...
    input.symbol_length, scope + ".symbol_length", catalogPath);
allocation.data_bearing_symbols = localRequirePositiveInteger( ...
    input.data_bearing_symbols, scope + ".data_bearing_symbols", catalogPath);
localRequireLogicalScalar(input.full_bandwidth, scope + ".full_bandwidth", catalogPath);
localRequireEnumText(input.frequency_hopping, ["disabled", "enabled"], ...
    scope + ".frequency_hopping", catalogPath);
localRequireNonemptyText(input.resource_allocation_type, ...
    scope + ".resource_allocation_type", catalogPath);
localRequireNonemptyText(input.vrb_to_prb_mapping, ...
    scope + ".vrb_to_prb_mapping", catalogPath);

if direction == "downlink"
    localRequireFields(input, {"rbg_size_config", "prb_bundling_size", ...
        "allocated_slots_per_20ms"}, ...
        scope, catalogPath);
    localRequireNonemptyText(input.rbg_size_config, ...
        scope + ".rbg_size_config", catalogPath);
    if isnumeric(input.prb_bundling_size)
        localRequireEnumNumber(input.prb_bundling_size, [2, 4], ...
            scope + ".prb_bundling_size", catalogPath);
    else
        localRequireEnumText(input.prb_bundling_size, "wideband", ...
            scope + ".prb_bundling_size", catalogPath);
    end
    localRequirePositiveInteger(input.allocated_slots_per_20ms, ...
        scope + ".allocated_slots_per_20ms", catalogPath);
end
end

function localValidateWaveform(input, direction, recordScope, catalogPath)
scope = recordScope + ".waveform";
localRequireScalarStruct(input, scope, catalogPath);
localRequireFields(input, {"name", "transform_precoding"}, scope, catalogPath);
localRequireEnumText(input.name, "CP-OFDM", scope + ".name", catalogPath);
transformPrecoding = localRequireLogicalScalar(input.transform_precoding, ...
    scope + ".transform_precoding", catalogPath);
if direction == "uplink" && transformPrecoding
    localInvalid(catalogPath, scope + ".transform_precoding", ...
        "must be false for these PUSCH FRC requirements");
end
end

function coding = localValidateCoding(input, direction, recordScope, catalogPath)
scope = recordScope + ".coding";
localRequireScalarStruct(input, scope, catalogPath);
localRequireFields(input, { ...
    "mcs_table", "mcs_index", "modulation", ...
    "target_code_rate_numerator", "target_code_rate_denominator", ...
    "displayed_target_code_rate", "tbs_bits", ...
    "transport_block_crc_bits", "code_blocks", ...
    "code_block_crc_bits", "g_bits_per_slot"}, scope, catalogPath);

localRequireNonemptyText(input.mcs_table, scope + ".mcs_table", catalogPath);
if isnumeric(input.mcs_index)
    localRequireNonnegativeInteger(input.mcs_index, scope + ".mcs_index", catalogPath);
else
    mcsToken = localRequireNonemptyText(input.mcs_index, ...
        scope + ".mcs_index", catalogPath);
    if mcsToken ~= "not_specified_by_frc"
        localInvalid(catalogPath, scope + ".mcs_index", ...
            "must be a nonnegative integer or 'not_specified_by_frc'");
    end
end
localRequireEnumText(input.modulation, ["QPSK", "16QAM", "64QAM", "256QAM"], ...
    scope + ".modulation", catalogPath);
numerator = localRequirePositiveFiniteScalar(input.target_code_rate_numerator, ...
    scope + ".target_code_rate_numerator", catalogPath);
denominator = localRequirePositiveFiniteScalar(input.target_code_rate_denominator, ...
    scope + ".target_code_rate_denominator", catalogPath);
displayedRate = localRequirePositiveFiniteScalar(input.displayed_target_code_rate, ...
    scope + ".displayed_target_code_rate", catalogPath);
if numerator >= denominator
    localInvalid(catalogPath, scope + ".target_code_rate_numerator", ...
        "must be smaller than target_code_rate_denominator");
end
if abs(displayedRate - numerator / denominator) > 0.01
    localInvalid(catalogPath, scope + ".displayed_target_code_rate", ...
        "must agree with the exact numerator/denominator to within the standard's displayed precision");
end
localRequirePositiveInteger(input.tbs_bits, scope + ".tbs_bits", catalogPath);
localRequireEnumNumber(input.transport_block_crc_bits, [16, 24], ...
    scope + ".transport_block_crc_bits", catalogPath);
coding.code_blocks = localRequirePositiveInteger( ...
    input.code_blocks, scope + ".code_blocks", catalogPath);
coding.code_block_crc_bits = localRequireEnumNumber( ...
    input.code_block_crc_bits, [0, 24], scope + ".code_block_crc_bits", catalogPath);
localRequirePositiveInteger(input.g_bits_per_slot, ...
    scope + ".g_bits_per_slot", catalogPath);

if direction == "downlink"
    localRequireFields(input, {"g_bits_tracking_slots", "tracking_slot_indices"}, ...
        scope, catalogPath);
    localRequirePositiveInteger(input.g_bits_tracking_slots, ...
        scope + ".g_bits_tracking_slots", catalogPath);
    trackingSlots = localRequireIntegerVector(input.tracking_slot_indices, ...
        scope + ".tracking_slot_indices", catalogPath, false);
    if isempty(trackingSlots)
        localInvalid(catalogPath, scope + ".tracking_slot_indices", ...
            "must identify the slots using g_bits_tracking_slots");
    end
end
end

function dmrs = localValidateDMRS(input, direction, recordScope, catalogPath)
scope = recordScope + ".dmrs";
localRequireScalarStruct(input, scope, catalogPath);
localRequireFields(input, { ...
    "configuration_type", "duration", "type_a_position", ...
    "additional_position", "num_cdm_groups_without_data", ...
    "ports", "data_to_dmrs_epre_db"}, scope, catalogPath);

localRequireEnumNumber(input.configuration_type, [1, 2], ...
    scope + ".configuration_type", catalogPath);
localRequireEnumText(input.duration, ["single_symbol", "double_symbol"], ...
    scope + ".duration", catalogPath);
localRequireEnumNumber(input.type_a_position, [2, 3], ...
    scope + ".type_a_position", catalogPath);
localRequireEnumNumber(input.additional_position, [0, 1, 2, 3], ...
    scope + ".additional_position", catalogPath);
localRequireEnumNumber(input.num_cdm_groups_without_data, [1, 2, 3], ...
    scope + ".num_cdm_groups_without_data", catalogPath);
dmrs.ports = localRequireIntegerVector( ...
    input.ports, scope + ".ports", catalogPath, false);
if isempty(dmrs.ports)
    localInvalid(catalogPath, scope + ".ports", "must not be empty");
end
localRequireFiniteScalar(input.data_to_dmrs_epre_db, ...
    scope + ".data_to_dmrs_epre_db", catalogPath);

if direction == "downlink"
    localRequireFields(input, {"dmrs_re_per_prb"}, scope, catalogPath);
    localRequirePositiveInteger(input.dmrs_re_per_prb, ...
        scope + ".dmrs_re_per_prb", catalogPath);
else
    localRequireFields(input, {"n_id_0", "n_scid"}, scope, catalogPath);
    localRequireNonnegativeInteger(input.n_id_0, scope + ".n_id_0", catalogPath);
    localRequireEnumNumber(input.n_scid, [0, 1], scope + ".n_scid", catalogPath);
end
end

function localValidatePTRS(input, recordScope, catalogPath)
scope = recordScope + ".ptrs";
localRequireScalarStruct(input, scope, catalogPath);
localRequireFields(input, { ...
    "enabled", "frequency_density", "time_density", ...
    "requirement_variant"}, scope, catalogPath);

enabled = localRequireLogicalScalar(input.enabled, ...
    scope + ".enabled", catalogPath);
frequencyDensity = localRequireNonemptyText(input.frequency_density, ...
    scope + ".frequency_density", catalogPath);
timeDensity = localRequireNonemptyText(input.time_density, ...
    scope + ".time_density", catalogPath);
variant = localRequireEnumText(input.requirement_variant, ["Yes", "No"], ...
    scope + ".requirement_variant", catalogPath);

if ~enabled && (frequencyDensity ~= "disabled" || ...
        timeDensity ~= "disabled" || variant ~= "No")
    localInvalid(catalogPath, scope, ...
        "disabled PT-RS must use disabled densities and requirement_variant='No'");
elseif enabled && variant ~= "Yes"
    localInvalid(catalogPath, scope + ".requirement_variant", ...
        "must be 'Yes' when PT-RS is enabled");
end
end

function mimo = localValidateMIMO(input, recordScope, catalogPath)
scope = recordScope + ".mimo";
localRequireScalarStruct(input, scope, catalogPath);
localRequireFields(input, { ...
    "layers", "tx_antennas", "rx_antennas", ...
    "antenna_configuration", "correlation_matrix"}, scope, catalogPath);
mimo.layers = localRequirePositiveInteger(input.layers, scope + ".layers", catalogPath);
mimo.tx_antennas = localRequirePositiveInteger( ...
    input.tx_antennas, scope + ".tx_antennas", catalogPath);
localRequirePositiveInteger(input.rx_antennas, scope + ".rx_antennas", catalogPath);
localRequireNonemptyText(input.antenna_configuration, ...
    scope + ".antenna_configuration", catalogPath);
localRequireNonemptyText(input.correlation_matrix, ...
    scope + ".correlation_matrix", catalogPath);

hasPrecodingScheme = isfield(input, "precoding_scheme");
hasTPMI = isfield(input, "tpmi_index");
if xor(hasPrecodingScheme, hasTPMI)
    localInvalid(catalogPath, scope, ...
        "precoding_scheme and tpmi_index must be provided together");
end
if hasPrecodingScheme
    scheme = localRequireEnumText(input.precoding_scheme, ...
        ["codebook", "noncodebook"], scope + ".precoding_scheme", catalogPath);
    if scheme == "codebook"
        localRequireNonnegativeInteger(input.tpmi_index, ...
            scope + ".tpmi_index", catalogPath);
    else
        tpmi = localRequireNonemptyText(input.tpmi_index, ...
            scope + ".tpmi_index", catalogPath);
        if tpmi ~= "not_applicable"
            localInvalid(catalogPath, scope + ".tpmi_index", ...
                "must be 'not_applicable' for noncodebook precoding");
        end
    end
end
end

function condition = localValidateCondition(input, recordScope, catalogPath)
scope = recordScope + ".condition";
localRequireScalarStruct(input, scope, catalogPath);
localRequireFields(input, { ...
    "id", "kind", "label", "model", "delay_spread_ns", ...
    "max_doppler_hz", "static_channel_reference", ...
    "frequency_offset_hz", "snr_definition"}, scope, catalogPath);
localRequireNonemptyText(input.id, scope + ".id", catalogPath);
condition.kind = localRequireEnumText(input.kind, ["awgn", "fading"], ...
    scope + ".kind", catalogPath);
localRequireNonemptyText(input.label, scope + ".label", catalogPath);
condition.model = localRequireEnumText(input.model, ...
    ["AWGN", "TDL-A", "TDL-B", "TDL-C"], scope + ".model", catalogPath);
condition.delay_spread_ns = localRequireNonnegativeFiniteScalar( ...
    input.delay_spread_ns, scope + ".delay_spread_ns", catalogPath);
condition.max_doppler_hz = localRequireNonnegativeFiniteScalar( ...
    input.max_doppler_hz, scope + ".max_doppler_hz", catalogPath);
localRequireNonemptyText(input.static_channel_reference, ...
    scope + ".static_channel_reference", catalogPath);
localRequireNonnegativeFiniteScalar(input.frequency_offset_hz, ...
    scope + ".frequency_offset_hz", catalogPath);
localRequireNonemptyText(input.snr_definition, ...
    scope + ".snr_definition", catalogPath);
if condition.kind == "awgn" && condition.model ~= "AWGN"
    localInvalid(catalogPath, scope + ".model", ...
        "must be 'AWGN' when condition.kind is 'awgn'");
elseif condition.kind == "fading" && ~startsWith(condition.model, "TDL-")
    localInvalid(catalogPath, scope + ".model", ...
        "must be a concrete TDL profile when condition.kind is 'fading'");
end
end

function localValidateHARQ(input, recordScope, catalogPath)
scope = recordScope + ".harq";
localRequireScalarStruct(input, scope, catalogPath);
localRequireFields(input, {"max_transmissions", "rv_sequence"}, scope, catalogPath);
maxTransmissions = localRequirePositiveInteger( ...
    input.max_transmissions, scope + ".max_transmissions", catalogPath);
rvSequence = localRequireIntegerVector( ...
    input.rv_sequence, scope + ".rv_sequence", catalogPath, false);
if numel(rvSequence) ~= maxTransmissions
    localInvalid(catalogPath, scope + ".rv_sequence", ...
        "must contain exactly max_transmissions entries");
end
if any(~ismember(rvSequence, [0, 1, 2, 3]))
    localInvalid(catalogPath, scope + ".rv_sequence", ...
        "may contain only NR redundancy versions 0, 1, 2, and 3");
end
if isfield(input, "timing")
    localValidateHARQTiming(input.timing, maxTransmissions, scope, catalogPath);
end
end

function localValidateHARQTiming(input, maxTransmissions, harqScope, catalogPath)
scope = harqScope + ".timing";
localRequireScalarStruct(input, scope, catalogPath);
localRequireFields(input, { ...
    "timeline_scope", "selected_duplex_mode", "process_count", ...
    "feedback_delay_slots", "feedback_delay_specified_by_standard", ...
    "process_count_specified_by_standard", ...
    "retransmission_spacing_slots", "retransmission_spacing_source", ...
    "inactive_slot_waveform", "standard_reference"}, scope, catalogPath);

localRequireEnumText(input.timeline_scope, ...
    "independent_transport_block_cluster", ...
    scope + ".timeline_scope", catalogPath);
localRequireEnumText(input.selected_duplex_mode, ["FDD", "TDD"], ...
    scope + ".selected_duplex_mode", catalogPath);
processCount = localRequirePositiveInteger(input.process_count, ...
    scope + ".process_count", catalogPath);
feedbackDelay = localRequireNonnegativeFiniteScalar( ...
    input.feedback_delay_slots, scope + ".feedback_delay_slots", catalogPath);
if feedbackDelay ~= fix(feedbackDelay)
    localInvalid(catalogPath, scope + ".feedback_delay_slots", ...
        "must be a nonnegative integer number of slots");
end
feedbackNormative = localRequireLogicalScalar( ...
    input.feedback_delay_specified_by_standard, ...
    scope + ".feedback_delay_specified_by_standard", catalogPath);
processNormative = localRequireLogicalScalar( ...
    input.process_count_specified_by_standard, ...
    scope + ".process_count_specified_by_standard", catalogPath);
spacing = localRequirePositiveInteger(input.retransmission_spacing_slots, ...
    scope + ".retransmission_spacing_slots", catalogPath);
localRequireNonemptyText(input.retransmission_spacing_source, ...
    scope + ".retransmission_spacing_source", catalogPath);
localRequireEnumText(input.inactive_slot_waveform, ...
    "zero_at_all_tx_ports", scope + ".inactive_slot_waveform", catalogPath);
localRequireNonemptyText(input.standard_reference, ...
    scope + ".standard_reference", catalogPath);

if maxTransmissions == 1 && spacing ~= 1
    localInvalid(catalogPath, scope + ".retransmission_spacing_slots", ...
        "must be one when only one HARQ transmission is configured");
end
if maxTransmissions > 1 && spacing < processCount
    localInvalid(catalogPath, scope + ".retransmission_spacing_slots", ...
        "must be at least process_count for the round-robin harness");
end
if feedbackNormative && feedbackDelay < 1
    localInvalid(catalogPath, scope + ".feedback_delay_slots", ...
        "must be positive when the standard explicitly specifies it");
end
if ~feedbackNormative && feedbackDelay ~= 0
    localInvalid(catalogPath, scope + ".feedback_delay_slots", ...
        "must be zero when the cited standard does not specify a delay");
end
if processNormative && processCount < 1
    localInvalid(catalogPath, scope + ".process_count", ...
        "must be positive when the standard explicitly specifies it");
end
end

function localValidateRequirement(input, recordScope, catalogPath)
scope = recordScope + ".requirement";
localRequireScalarStruct(input, scope, catalogPath);
localRequireFields(input, { ...
    "normative", "metric", "comparator", "target_fraction", ...
    "target_percent", "required_snr_db", "evaluation_mode", ...
    "semantics"}, scope, catalogPath);

isNormative = localRequireLogicalScalar(input.normative, ...
    scope + ".normative", catalogPath);
if ~isNormative
    localInvalid(catalogPath, scope + ".normative", ...
        "must be true for a standards requirement record");
end
metric = localRequireEnumText(input.metric, ...
    ["block_error_rate", "fraction_of_maximum_throughput"], ...
    scope + ".metric", catalogPath);
comparator = localRequireEnumText(input.comparator, ...
    ["less_than_or_equal", "greater_than_or_equal"], ...
    scope + ".comparator", catalogPath);
targetFraction = localRequirePositiveFiniteScalar(input.target_fraction, ...
    scope + ".target_fraction", catalogPath);
targetPercent = localRequirePositiveFiniteScalar(input.target_percent, ...
    scope + ".target_percent", catalogPath);
if targetFraction > 1 || abs(targetPercent - 100 * targetFraction) > 1e-10
    localInvalid(catalogPath, scope, ...
        "target_fraction must be in (0,1] and target_percent must equal 100*target_fraction");
end
localRequireFiniteScalar(input.required_snr_db, ...
    scope + ".required_snr_db", catalogPath);
localRequireEnumText(input.evaluation_mode, "at_required_snr", ...
    scope + ".evaluation_mode", catalogPath);
semantics = localRequireEnumText(input.semantics, ...
    "one_sided_minimum_performance_at_required_snr", ...
    scope + ".semantics", catalogPath);

if metric == "block_error_rate" && comparator ~= "less_than_or_equal"
    localInvalid(catalogPath, scope + ".comparator", ...
        "must be 'less_than_or_equal' for a BLER requirement");
elseif metric == "fraction_of_maximum_throughput" && ...
        comparator ~= "greater_than_or_equal"
    localInvalid(catalogPath, scope + ".comparator", ...
        "must be 'greater_than_or_equal' for a throughput requirement");
end
if semantics ~= "one_sided_minimum_performance_at_required_snr"
    localInvalid(catalogPath, scope + ".semantics", ...
        "must preserve one-sided standards semantics");
end
end

function item = localSequenceItem(sequence, index, scope, catalogPath)
if iscell(sequence)
    item = sequence{index};
else
    item = sequence(index);
end
localRequireScalarStruct(item, sprintf("%s(%d)", scope, index), catalogPath);
end

function localRequireScalarStruct(value, fieldPath, catalogPath)
if ~(isstruct(value) && isscalar(value))
    localInvalid(catalogPath, fieldPath, "must be an object");
end
end

function localRequireFields(value, required, scope, catalogPath)
required = cellstr(string(required));
missing = required(~isfield(value, required));
if ~isempty(missing)
    localInvalid(catalogPath, scope, ...
        "is missing required field(s): " + strjoin(string(missing), ", "));
end
end

function value = localRequireNonemptyText(input, fieldPath, catalogPath)
if ischar(input)
    value = string(input);
elseif isstring(input) && isscalar(input)
    value = input;
else
    localInvalid(catalogPath, fieldPath, "must be a text scalar");
end
if strlength(strtrim(value)) == 0
    localInvalid(catalogPath, fieldPath, "must not be empty");
end
end

function value = localRequireEnumText(input, allowed, fieldPath, catalogPath)
value = localRequireNonemptyText(input, fieldPath, catalogPath);
if ~any(value == allowed)
    localInvalid(catalogPath, fieldPath, ...
        "must be one of: " + strjoin(allowed, ", "));
end
end

function localRequireNonemptyTextSequence(input, fieldPath, catalogPath)
localRequireTextVector(input, fieldPath, catalogPath);
end

function values = localRequireTextVector(input, fieldPath, catalogPath)
if ischar(input) || (isstring(input) && isscalar(input))
    values = string(input);
elseif isstring(input)
    values = input;
elseif iscell(input) && all(cellfun(@(v) ischar(v) || ...
        (isstring(v) && isscalar(v)), input))
    values = string(input);
else
    localInvalid(catalogPath, fieldPath, ...
        "must be a nonempty sequence of text values");
end
if isempty(values) || any(strlength(strtrim(values)) == 0)
    localInvalid(catalogPath, fieldPath, ...
        "must be a nonempty sequence of nonempty text values");
end
values = values(:);
end

function value = localRequireFiniteScalar(input, fieldPath, catalogPath)
if ~(isnumeric(input) && isreal(input) && isscalar(input) && isfinite(input))
    localInvalid(catalogPath, fieldPath, "must be a finite real numeric scalar");
end
value = double(input);
end

function value = localRequireNonnegativeFiniteScalar(input, fieldPath, catalogPath)
value = localRequireFiniteScalar(input, fieldPath, catalogPath);
if value < 0
    localInvalid(catalogPath, fieldPath, "must be nonnegative");
end
end

function value = localRequirePositiveFiniteScalar(input, fieldPath, catalogPath)
value = localRequireFiniteScalar(input, fieldPath, catalogPath);
if value <= 0
    localInvalid(catalogPath, fieldPath, "must be positive");
end
end

function value = localRequireNonnegativeInteger(input, fieldPath, catalogPath)
value = localRequireFiniteScalar(input, fieldPath, catalogPath);
if value < 0 || value ~= fix(value)
    localInvalid(catalogPath, fieldPath, "must be a nonnegative integer");
end
end

function value = localRequirePositiveInteger(input, fieldPath, catalogPath)
value = localRequireFiniteScalar(input, fieldPath, catalogPath);
if value <= 0 || value ~= fix(value)
    localInvalid(catalogPath, fieldPath, "must be a positive integer");
end
end

function value = localRequireEnumNumber(input, allowed, fieldPath, catalogPath)
value = localRequireFiniteScalar(input, fieldPath, catalogPath);
if ~any(value == allowed)
    localInvalid(catalogPath, fieldPath, sprintf( ...
        "must be one of: %s", strjoin(string(allowed), ", ")));
end
end

function values = localRequireIntegerVector(input, fieldPath, catalogPath, allowEmpty)
if nargin < 4
    allowEmpty = false;
end
if ~(isnumeric(input) && isreal(input) && isvector(input) && ...
        all(isfinite(input), "all") && all(input == fix(input), "all"))
    localInvalid(catalogPath, fieldPath, "must be a finite integer vector");
end
values = double(input(:).');
if ~allowEmpty && isempty(values)
    localInvalid(catalogPath, fieldPath, "must not be empty");
end
end

function value = localRequireLogicalScalar(input, fieldPath, catalogPath)
if ~(islogical(input) && isscalar(input))
    localInvalid(catalogPath, fieldPath, "must be a logical scalar");
end
value = input;
end

function duplicates = localDuplicates(values)
[uniqueValues, ~, groups] = unique(values);
counts = accumarray(groups, 1);
duplicates = uniqueValues(counts > 1);
end

function localInvalid(catalogPath, fieldPath, reason)
error("sixgr:conformance:InvalidFRCatalog", ...
    "Invalid FRC catalog '%s': %s %s.", ...
    catalogPath, string(fieldPath), string(reason));
end

function catalogPath = localResolveCatalogPath(catalogPath)
catalogPath = string(catalogPath);
if exist(char(catalogPath), "file") == 2
    return;
end

candidate = fullfile(localRepoRoot(), catalogPath);
if exist(char(candidate), "file") == 2
    catalogPath = string(candidate);
end
end

function catalogPath = localDefaultCatalogPath()
catalogPath = fullfile(localRepoRoot(), "simulator", "configs", ...
    "conformance", "nr_frc_release18.yaml");
end

function root = localRepoRoot()
here = fileparts(mfilename("fullpath"));
root = fileparts(fileparts(here));
end
