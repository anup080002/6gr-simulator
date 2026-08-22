function report = validateRACHTDocStudyConfig(cfg)
%VALIDATECAMPAIGNCONFIG Fail-closed validation for the TDoc campaign layer.

if ~(isstruct(cfg) && isscalar(cfg))
    error("sixgr:rach:tdoc10512:BadConfig", ...
        "Resolved campaign configuration must be a scalar struct.");
end
required = [ ...
    "meta.scenario_id"
    "meta.research_class"
    "random_access.prach_format"
    "random_access.channel_model"
    "random_access.statistical_qualification"
    "tdoc10512.schema_version"
    "tdoc10512.campaign_mode"
    "tdoc10512.campaign_id"
    "tdoc10512.master_seed"
    "tdoc10512.speed_of_light_mps"
    "tdoc10512.prach_formats"
    "tdoc10512.scenarios"
    "tdoc10512.msg3_shapes"
    "tdoc10512.sbfd"
    "tdoc10512.output.root"];
for k = 1:numel(required)
    value = sixgr.util.structGet(cfg, required(k), []);
    if isempty(value)
        error("sixgr:rach:tdoc10512:MissingField", ...
            "Required campaign field '%s' is missing.", required(k));
    end
end

mode = lower(string(cfg.tdoc10512.campaign_mode));
allowedModes = ["smoke","analytical","engineering_lls","core_lls","full","report_only"];
if ~isscalar(mode) || ~ismember(mode, allowedModes)
    error("sixgr:rach:tdoc10512:BadMode", ...
        "tdoc10512.campaign_mode must be one of: %s.", ...
        strjoin(allowedModes, ", "));
end
if string(cfg.tdoc10512.frequency_stress_mode) ~= "study_table_screening" || ...
        string(cfg.tdoc10512.waveform_frequency_stress_mode) ~= ...
        "physical_channel_plus_residual_cfo"
    error("sixgr:rach:tdoc10512:FrequencyStressSemantics", ...
        "Analytical two-way Doppler and waveform physical Doppler/CFO must remain separate.");
end

out = cfg.tdoc10512.output;
if logical(out.save_svg)
    error("sixgr:rach:tdoc10512:SVGForbidden", ...
        "This repository campaign is configured for raster PNG/JPEG output; save_svg must be false.");
end
if ~logical(out.save_png) || double(out.png_dpi) < 300
    error("sixgr:rach:tdoc10512:RasterContract", ...
        "TDoc campaign figures require PNG output at 300 dpi or greater.");
end

formats = localRecords(cfg.tdoc10512.prach_formats);
scenarios = localRecords(cfg.tdoc10512.scenarios);
shapes = localRecords(cfg.tdoc10512.msg3_shapes);
localUniqueIDs(formats, "PRACH format");
localUniqueIDs(scenarios, "scenario");
localUniqueIDs(shapes, "Msg3 shape");

c = double(cfg.tdoc10512.speed_of_light_mps);
if ~(isscalar(c) && isfinite(c) && c > 2.9e8 && c < 3.1e8)
    error("sixgr:rach:tdoc10512:BadPhysicalConstant", ...
        "tdoc10512.speed_of_light_mps must be a finite physical light speed.");
end
for k = 1:numel(scenarios)
    row = scenarios{k};
    expectedRTT = 2 * double(row.cell_range_m) / c * 1e6;
    if abs(expectedRTT - double(row.geometric_rtt_us)) > 0.12
        error("sixgr:rach:tdoc10512:ScenarioPairing", ...
            "Scenario %s geometric RTT %.6g us conflicts with range-derived %.6g us.", ...
            string(row.id), double(row.geometric_rtt_us), expectedRTT);
    end
    expectedScreen = 2 * (double(row.speed_kmh)/3.6) / c * ...
        double(row.carrier_hz);
    if abs(expectedScreen - double(row.two_way_screening_doppler_hz)) > 1.0
        error("sixgr:rach:tdoc10512:ScenarioPairing", ...
            "Scenario %s two-way screening Doppler %.6g Hz conflicts with paired carrier/speed %.6g Hz.", ...
            string(row.id), double(row.two_way_screening_doppler_hz), expectedScreen);
    end
    if contains(upper(string(row.id)), "ATG") && logical(row.waveform_eligible)
        error("sixgr:rach:tdoc10512:ATGCalibrationRequired", ...
            "ATG scenario %s must remain analytical-only without an explicit calibrated ATG channel.", ...
            string(row.id));
    end
end

stats = cfg.random_access.statistical_qualification;
if any(mode == ["smoke","engineering_lls"])
    if double(stats.minimum_trials) < 100 || ...
            double(stats.minimum_detection_trials) < 100
        error("sixgr:rach:tdoc10512:SmokeTrialFloor", ...
            "Smoke mode requires at least 100 independent noise and signal trials.");
    end
elseif any(mode == ["core_lls","full"])
    if double(stats.minimum_trials) < 1e6
        error("sixgr:rach:tdoc10512:FalseAlarmTrialFloor", ...
            "Core/full mode requires at least 1e6 noise-only trials for the 1e-3 working point.");
    end
end

report = table(string(required), true(numel(required),1), ...
    repmat("validated",numel(required),1), ...
    'VariableNames',{'Field','Pass','Status'});
end

function rows = localRecords(value)
if iscell(value)
    rows = value(:);
elseif isstruct(value)
    rows = arrayfun(@(x)x, value(:), 'UniformOutput', false);
else
    error("sixgr:rach:tdoc10512:BadCatalog", ...
        "Campaign catalogs must decode to structure records.");
end
if isempty(rows) || ~all(cellfun(@(x)isstruct(x)&&isscalar(x),rows))
    error("sixgr:rach:tdoc10512:BadCatalog", ...
        "Campaign catalogs must contain scalar structure records.");
end
end

function localUniqueIDs(rows, label)
ids = string(cellfun(@(x)x.id, rows, 'UniformOutput', false));
if any(strlength(strtrim(ids)) == 0) || numel(unique(ids)) ~= numel(ids)
    error("sixgr:rach:tdoc10512:DuplicateCatalogID", ...
        "%s IDs must be nonempty and unique.", label);
end
end
