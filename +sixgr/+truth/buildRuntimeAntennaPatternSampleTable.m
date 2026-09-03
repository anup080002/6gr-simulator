function T = buildRuntimeAntennaPatternSampleTable(cfg, bsRuntime, ueRuntime)
%BUILDRUNTIMEANTENNAPATTERNSAMPLETABLE Sample the actual coupled-runtime arrays.
%
% This exporter evaluates the phased.NRRectangularPanelArray objects that
% are also installed on the runtime channel.  It does not rebuild an array
% from configuration and does not apply or infer a selected PMI/beam taper.
% The sampled pattern is therefore the physical array/element directivity
% in the local array coordinate system; selected-beam evidence is exported
% separately by the beam/precoder runtime tables.

enabled = logical(sixgr.util.structGet(cfg, ...
    "outputs.antennaPatternSamplesEnabled", false));
T = localEmptyTable();
if ~enabled
    return;
end

azMin = localFiniteScalar(cfg, "outputs.antennaPatternAzimuthMin_deg");
azMax = localFiniteScalar(cfg, "outputs.antennaPatternAzimuthMax_deg");
azStep = localFiniteScalar(cfg, "outputs.antennaPatternAzimuthStep_deg");
elMin = localFiniteScalar(cfg, "outputs.antennaPatternElevationMin_deg");
elMax = localFiniteScalar(cfg, "outputs.antennaPatternElevationMax_deg");
elStep = localFiniteScalar(cfg, "outputs.antennaPatternElevationStep_deg");
if ~(azMin >= -180 && azMax <= 180 && azMax > azMin && azStep > 0 && ...
        elMin >= -90 && elMax <= 90 && elMax > elMin && elStep > 0)
    error("sixgr:truth:InvalidAntennaPatternSamplingGrid", ...
        ["Runtime antenna-pattern sampling requires finite YAML-resolved " ...
         "azimuth/elevation limits and positive steps within the physical sphere."]);
end
azimuth = azMin:azStep:azMax;
elevation = elMin:elStep:elMax;
if azimuth(end) < azMax - 1e-9
    azimuth(end + 1) = azMax; %#ok<AGROW>
end
if elevation(end) < elMax - 1e-9
    elevation(end + 1) = elMax; %#ok<AGROW>
end

entries = [localNormalizeEntries(bsRuntime); localNormalizeEntries(ueRuntime)];
for ii = 1:numel(entries)
    entry = entries(ii);
    antenna = sixgr.util.structGet(entry, "Antenna", struct());
    metadata = sixgr.util.structGet(entry, "Metadata", struct());
    arrayObject = sixgr.util.structGet(antenna, "ArrayObj", []);
    if isempty(arrayObject) || ...
            ~isa(arrayObject, "phased.NRRectangularPanelArray")
        error("sixgr:truth:RuntimeAntennaPatternObjectUnavailable", ...
            ["Antenna pattern sampling was enabled, but runtime node %s-%g " ...
             "does not carry the required phased.NRRectangularPanelArray object."], ...
            char(string(sixgr.util.structGet(metadata, "NodeType", "unknown"))), ...
            double(sixgr.util.structGet(metadata, "NodeIndex", NaN)));
    end
    frequencyHz = double(sixgr.util.structGet(antenna, "Fc_Hz", NaN));
    if ~(isscalar(frequencyHz) && isfinite(frequencyHz) && frequencyHz > 0)
        error("sixgr:truth:RuntimeAntennaPatternFrequencyUnavailable", ...
            "The actual runtime antenna object has no finite operating frequency.");
    end
    try
        directivity = pattern(arrayObject, frequencyHz, azimuth, elevation, ...
            "Type", "directivity", "CoordinateSystem", "rectangular");
    catch ME
        error("sixgr:truth:RuntimeAntennaPatternEvaluationFailed", ...
            "Actual runtime antenna pattern evaluation failed: %s", ME.message);
    end
    if isequal(size(directivity), [numel(elevation), numel(azimuth)])
        [azGrid, elGrid] = meshgrid(azimuth, elevation);
    elseif isequal(size(directivity), [numel(azimuth), numel(elevation)])
        [elGrid, azGrid] = meshgrid(elevation, azimuth);
    else
        error("sixgr:truth:RuntimeAntennaPatternShapeMismatch", ...
            "Actual runtime antenna returned unexpected pattern size %s.", ...
            mat2str(size(directivity)));
    end
    directivity = double(directivity);
    if any(~isfinite(directivity(:)))
        error("sixgr:truth:RuntimeAntennaPatternNonfinite", ...
            "Actual runtime antenna returned nonfinite directivity samples.");
    end
    sha = sixgr.util.sha256Hex(typecast(directivity(:), "uint8"));
    elementObject = sixgr.util.structGet(antenna, "ElementObj", []);
    if isempty(elementObject) || ~isa(elementObject, "phased.NRAntennaElement")
        error("sixgr:truth:RuntimeAntennaElementObjectUnavailable", ...
            ["Antenna pattern sampling requires the actual " ...
             "phased.NRAntennaElement installed in the runtime array."]);
    end
    boresight = double(sixgr.util.structGet( ...
        antenna, "BoresightAzElSlant_deg", [NaN NaN NaN]));
    if numel(boresight) < 3
        boresight = [NaN NaN NaN];
    end
    n = numel(directivity);
    rows = table();
    rows.NodeType = repmat(string(sixgr.util.structGet(metadata, "NodeType", "")), n, 1);
    rows.NodeIndex = repmat(double(sixgr.util.structGet(metadata, "NodeIndex", NaN)), n, 1);
    rows.BaseStationID = repmat(double(sixgr.util.structGet(metadata, "BaseStationID", NaN)), n, 1);
    rows.UEIndex = repmat(double(sixgr.util.structGet(metadata, "UEIndex", NaN)), n, 1);
    rows.Frequency_Hz = repmat(frequencyHz, n, 1);
    rows.Azimuth_deg = double(azGrid(:));
    rows.Elevation_deg = double(elGrid(:));
    rows.Directivity_dBi = directivity(:);
    rows.ArrayClass = repmat(string(class(arrayObject)), n, 1);
    rows.ElementClass = repmat(string(class(elementObject)), n, 1);
    rows.ElementModel = repmat(string(sixgr.util.structGet(antenna, "ElementModel", "")), n, 1);
    rows.BoresightAzimuth_deg = repmat(double(boresight(1)), n, 1);
    rows.BoresightElevation_deg = repmat(double(boresight(2)), n, 1);
    rows.BoresightSlant_deg = repmat(double(boresight(3)), n, 1);
    rows.CoordinateFrame = repmat("local_array_coordinate_frame_before_runtime_orientation", n, 1);
    rows.PatternKind = repmat("physical_array_element_directivity_without_selected_precoder_taper", n, 1);
    rows.PatternSource = repmat("actual_CoupledTruthRuntime_phased_NRRectangularPanelArray", n, 1);
    rows.SelectedBeamApplied = false(n, 1);
    rows.SelectedBeamEvidenceSource = repmat("separate_runtime_beam_precoder_tables", n, 1);
    rows.PatternSHA256 = repmat(string(sha), n, 1);
    rows.truth_status = repmat("real_runtime_object_evidence", n, 1);
    T = [T; rows]; %#ok<AGROW>
end
end

function value = localFiniteScalar(cfg, path)
value = double(sixgr.util.structGet(cfg, path, NaN));
if ~(isscalar(value) && isfinite(value))
    error("sixgr:truth:MissingAntennaPatternSamplingAuthority", ...
        "Missing finite YAML-resolved runtime antenna pattern field %s.", path);
end
end

function entries = localNormalizeEntries(value)
entries = repmat(struct(), 0, 1);
if isstruct(value) && ~isempty(value)
    entries = value(:);
end
end

function T = localEmptyTable()
T = table( ...
    strings(0,1), nan(0,1), nan(0,1), nan(0,1), nan(0,1), ...
    nan(0,1), nan(0,1), nan(0,1), strings(0,1), strings(0,1), ...
    strings(0,1), nan(0,1), nan(0,1), nan(0,1), strings(0,1), ...
    strings(0,1), strings(0,1), false(0,1), strings(0,1), strings(0,1), ...
    strings(0,1), ...
    'VariableNames', { ...
    'NodeType','NodeIndex','BaseStationID','UEIndex','Frequency_Hz', ...
    'Azimuth_deg','Elevation_deg','Directivity_dBi','ArrayClass','ElementClass', ...
    'ElementModel','BoresightAzimuth_deg','BoresightElevation_deg','BoresightSlant_deg', ...
    'CoordinateFrame','PatternKind','PatternSource','SelectedBeamApplied', ...
    'SelectedBeamEvidenceSource','PatternSHA256','truth_status'});
end
