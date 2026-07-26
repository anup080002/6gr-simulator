function tests = testChannelPhase10Anchors
% Independent deterministic anchors for the strict Phase-10 runtime.
tests = functiontests(localfunctions);
end

function testPathlossVectors(testCase)
[input, expected] = localPair("channel_pathloss_test_vectors.csv", ...
    "expected_channel_pathloss.csv");
actual = nan(height(input), 1);
for row = 1:height(input)
    if expected.ExpectedStatus(row) == "PASS"
        [actual(row), meta] = sixgr.channel.Pathloss38901( ...
            input.Scenario(row), input.Condition(row), input.Fc_GHz(row), ...
            input.Distance2D_m(row), input.hBS_m(row), input.hUT_m(row), ...
            input.StreetWidth_m(row), input.BuildingHeight_m(row));
        verifyEqual(testCase, meta.Distance3D_m, expected.Distance3D_m(row), ...
            "AbsTol", 1e-9);
    else
        verifyError(testCase, @() sixgr.channel.Pathloss38901( ...
            input.Scenario(row), input.Condition(row), input.Fc_GHz(row), ...
            input.Distance2D_m(row), input.hBS_m(row), input.hUT_m(row), ...
            input.StreetWidth_m(row), input.BuildingHeight_m(row)), ...
            "CHANNEL:UnsupportedProfile");
    end
end
mask = expected.ExpectedStatus == "PASS";
verifyLessThanOrEqual(testCase, ...
    max(abs(actual(mask) - expected.ExpectedPathloss_dB(mask))), 1e-9);
end

function testLOSProbabilityVectors(testCase)
[input, expected] = localPair("channel_los_probability_test_vectors.csv", ...
    "expected_channel_los_probability.csv");
actual = nan(height(input), 1);
for row = 1:height(input)
    if expected.ExpectedStatus(row) == "PASS"
        actual(row) = sixgr.channel.LOSProbability(input.Scenario(row), ...
            input.Distance2D_m(row), "HUT_m", input.hUT_m(row));
    else
        verifyError(testCase, @() sixgr.channel.LOSProbability( ...
            input.Scenario(row), input.Distance2D_m(row), ...
            "HUT_m", input.hUT_m(row)), "CHANNEL:UnknownLOSScenario");
    end
end
mask = expected.ExpectedStatus == "PASS";
verifyLessThanOrEqual(testCase, ...
    max(abs(actual(mask) - expected.ExpectedPLOS(mask))), 1e-12);
end

function testO2IVectors(testCase)
[input, expected] = localPair("channel_o2i_material_test_vectors.csv", ...
    "expected_channel_o2i_loss.csv");
actual = zeros(height(input), 1);
for row = 1:height(input)
    actual(row) = sixgr.channel.O2ILoss(input.Fc_GHz(row) .* 1e9, ...
        input.Profile(row), "IndoorDistance_m", input.IndoorDistance_m(row), ...
        "RandomComponent_dB", input.RandomComponent_dB(row), ...
        "RandomComponentEnabled", false);
end
verifyLessThanOrEqual(testCase, ...
    max(abs(actual - expected.ExpectedO2ILoss_dB)), 1e-9);
end

function testOxygenVectors(testCase)
[input, expected] = localPair("channel_oxygen_absorption_test_vectors.csv", ...
    "expected_channel_oxygen_absorption.csv");
gamma = sixgr.channel.OxygenAbsorption.specificAttenuation_dBkm(input.Fc_GHz);
loss = sixgr.channel.OxygenAbsorption.pathLoss_dB( ...
    input.Fc_GHz .* 1e9, input.Distance_m);
verifyLessThanOrEqual(testCase, ...
    max(abs(gamma - expected.SpecificAttenuation_dB_per_km)), 1e-12);
verifyLessThanOrEqual(testCase, ...
    max(abs(loss - expected.ExpectedPathLoss_dB)), 1e-12);
end

function testGeometryKinematicsVectors(testCase)
[input, expected] = localPair("channel_geometry_state_test_vectors.csv", ...
    "expected_geometry_kinematics.csv");
errorValue = zeros(height(input), 1);
for row = 1:height(input)
    state = sixgr.channel.GeometryKinematics( ...
        [input.TxX_m(row), input.TxY_m(row), input.TxZ_m(row)], ...
        [input.RxX_m(row), input.RxY_m(row), input.RxZ_m(row)], ...
        [input.TxVx_mps(row), input.TxVy_mps(row), input.TxVz_mps(row)], ...
        [input.RxVx_mps(row), input.RxVy_mps(row), input.RxVz_mps(row)], ...
        input.Fc_Hz(row), input.Dt_s(row));
    reference = [expected.Distance2D_m(row), expected.Distance3D_m(row), ...
        expected.UnitX(row), expected.UnitY(row), expected.UnitZ(row), ...
        expected.RangeRate_mps(row), expected.SignedDoppler_Hz(row), ...
        expected.PropagationDelay_s(row), expected.PhaseIncrement_rad(row)];
    measured = [state.Distance2D_m, state.Distance3D_m, state.UnitVector, ...
        state.RangeRate_mps, state.SignedDoppler_Hz, ...
        state.PropagationDelay_s, state.PhaseIncrement_rad];
    errorValue(row) = max(abs(reference - measured));
end
verifyLessThanOrEqual(testCase, max(errorValue), 1e-9);
end

function testLSPAndTDLCorrelationVectors(testCase)
[input, expected] = localPair( ...
    "channel_lsp_spatial_consistency_test_vectors.csv", ...
    "expected_lsp_spatial_correlation.csv");
actual = sixgr.channel.LSPSpatialCorrelation(input.Separation_m, ...
    input.CorrelationDistance_m);
verifyLessThanOrEqual(testCase, ...
    max(abs(actual - expected.ExpectedAutocorrelation)), 1e-12);

root = localRoot();
options = delimitedTextImportOptions("NumVariables", 5);
options.DataLines = [2 Inf];
options.Delimiter = ",";
options.VariableNames = ["CaseID","NPorts","AdjacentCorrelation","ProfileType","Note"];
options.VariableTypes = ["string","double","double","string","string"];
options.ExtraColumnsRule = "ignore";
input = readtable(fullfile(root, "channel_tdl_correlation_test_vectors.csv"), options);
expected = readtable(fullfile(root, "expected_tdl_spatial_correlation.csv"), ...
    "TextType", "string");
offset = 0;
for row = 1:height(input)
    matrix = sixgr.channel.TDLSpatialCorrelation( ...
        input.NPorts(row), input.AdjacentCorrelation(row));
    count = input.NPorts(row).^2;
    reference = expected(offset + (1:count), :);
    linear = sub2ind(size(matrix), reference.Row0 + 1, reference.Col0 + 1);
    verifyLessThanOrEqual(testCase, ...
        max(abs(real(matrix(linear)) - reference.ExpectedReal)), 1e-12);
    verifyLessThanOrEqual(testCase, ...
        max(abs(imag(matrix(linear)) - reference.ExpectedImag)), 1e-12);
    offset = offset + count;
end
end

function testAbsolutePowerVectors(testCase)
[input, expected] = localPair("channel_absolute_power_test_vectors.csv", ...
    "expected_absolute_power_ledger.csv");
errors = zeros(height(input), 4);
for row = 1:height(input)
    state = sixgr.channel.AbsolutePowerLedger(input.TxPower_dBm(row), ...
        input.TxGain_dBi(row), input.RxGain_dBi(row), ...
        input.Pathloss_dB(row), input.ShadowFading_dB(row), ...
        input.O2ILoss_dB(row), input.OxygenLoss_dB(row), ...
        input.ImplementationLoss_dB(row), input.Bandwidth_Hz(row), ...
        input.NoiseFigure_dB(row));
    errors(row,:) = abs([state.NoisePower_dBm - expected.ExpectedNoisePower_dBm(row), ...
        state.RxPower_W - expected.ExpectedRxPower_W(row), ...
        state.RxPower_dBm - expected.ExpectedRxPower_dBm(row), ...
        state.SNR_dB - expected.ExpectedSNR_dB(row)]);
end
verifyLessThanOrEqual(testCase, max(errors(:,[1 3 4]), [], "all"), 1e-10);
verifyLessThanOrEqual(testCase, max(errors(:,2)), 2e-20);
end

function testArrayResponseVectors(testCase)
[input, expected] = localPair("channel_array_response_test_vectors.csv", ...
    "expected_channel_array_response.csv");
offset = 0;
maxError = 0;
for row = 1:height(input)
    [response, state] = sixgr.channel.ArrayResponse(input.Layout(row), ...
        input.Nv(row), input.Nh(row), input.SpacingH_lambda(row), ...
        input.SpacingV_lambda(row), input.Azimuth_deg(row), ...
        input.Elevation_deg(row), input.Yaw_deg(row), ...
        input.Pitch_deg(row), input.Roll_deg(row));
    count = input.Nv(row) .* input.Nh(row);
    reference = expected(offset + (1:count), :);
    maxError = max(maxError, max(abs(response - ...
        complex(reference.Real, reference.Imag))));
    verifyEqual(testCase, state.ArrayNorm, reference.ArrayNorm(1), ...
        "AbsTol", 1e-12);
    offset = offset + count;
end
verifyLessThanOrEqual(testCase, maxError, 1e-12);
end

function testExplicitWraparoundVectors(testCase)
[input, expected] = localPair("channel_wraparound_test_vectors.csv", ...
    "expected_wraparound_topology.csv");
for row = 1:height(input)
    actual = sixgr.channel.ExplicitHexTopology(input.ISD_m(row), ...
        input.SectorsPerSite(row));
    reference = expected(expected.CaseID == input.CaseID(row), :);
    verifyEqual(testCase, height(actual), height(reference));
    verifyEqual(testCase, actual.AxialQ, reference.AxialQ);
    verifyEqual(testCase, actual.AxialR, reference.AxialR);
    verifyEqual(testCase, actual.CloneSiteIndex0, reference.CloneSiteIndex0);
    verifyEqual(testCase, actual.SectorIndex0, reference.SectorIndex0);
    verifyLessThanOrEqual(testCase, ...
        max(abs(actual.SiteX_m - reference.SiteX_m)), 1e-12);
    verifyLessThanOrEqual(testCase, ...
        max(abs(actual.SiteY_m - reference.SiteY_m)), 1e-12);
end
end

function testInterferenceSuperpositionVectors(testCase)
[input, expected] = localPair( ...
    "channel_interference_superposition_test_vectors.csv", ...
    "expected_interference_superposition.csv");
cases = unique(input.CaseID, "stable");
maxError = 0;
for index = 1:numel(cases)
    links = input(input.CaseID == cases(index), :);
    reference = expected(expected.CaseID == cases(index), :);
    [actual, contributions] = sixgr.channel.composeInterferenceTones( ...
        links, 30.72e6);
    maxError = max(maxError, max(abs(actual - ...
        complex(reference.ExpectedReal, reference.ExpectedImag))));
    verifyEqual(testCase, size(contributions,2), ...
        reference.ContributionCount(1));
end
verifyLessThanOrEqual(testCase, maxError, 1e-12);
end

function testStrictDropProfiles(testCase)
root = localRoot();
input = readtable(fullfile(root, "channel_ue_drop_test_vectors.csv"), ...
    "TextType", "string");
for row = 1:height(input)
    parameters = struct();
    fields = ["CenterX_m","CenterY_m","Floors","Length_m","Radius_m", ...
        "Rmax_m","Rmin_m","Sigma_m","Width_m"];
    for field = fields
        value = input.(field)(row);
        if isfinite(value)
            parameters.(field) = value;
        end
    end
    drop = sixgr.channel.dropUEsStrict(input.Profile(row), input.NUE(row), ...
        input.Seed(row), parameters);
    verifyEqual(testCase, height(drop), input.NUE(row));
    verifyTrue(testCase, all(isfinite(drop{:,["X_m","Y_m","Z_m"]}), "all"));
    repeat = sixgr.channel.dropUEsStrict(input.Profile(row), input.NUE(row), ...
        input.Seed(row), parameters);
    verifyEqual(testCase, drop, repeat);
end
end

function testMobilityIntegratedPhaseVectors(testCase)
[input, expected] = localPair("channel_mobility_doppler_test_vectors.csv", ...
    "expected_mobility_doppler_phase.csv");
cases = unique(input.CaseID, "stable");
maxDopplerError = 0;
maxPhaseError = 0;
for caseIndex = 1:numel(cases)
    rows = find(input.CaseID == cases(caseIndex));
    doppler = zeros(numel(rows),1);
    for ordinal = 1:numel(rows)
        row = rows(ordinal);
        state = sixgr.channel.GeometryKinematics( ...
            [input.TxX_m(row),input.TxY_m(row),input.TxZ_m(row)], ...
            [input.RxX_m(row),input.RxY_m(row),input.RxZ_m(row)], ...
            [0 0 0],[input.RxVx_mps(row),input.RxVy_mps(row),input.RxVz_mps(row)], ...
            input.Fc_Hz(row),input.Dt_s(row));
        doppler(ordinal) = state.SignedDoppler_Hz;
    end
    phase = sixgr.channel.integrateDopplerPhase(input.Time_s(rows),doppler);
    maxDopplerError = max(maxDopplerError, ...
        max(abs(doppler-expected.SignedDoppler_Hz(rows))));
    maxPhaseError = max(maxPhaseError, ...
        max(abs(phase-expected.IntegratedPhase_rad(rows))));
end
verifyLessThanOrEqual(testCase,maxDopplerError,1e-6);
verifyLessThanOrEqual(testCase,maxPhaseError,1e-5);
end

function testStrictRuntimeNegativeVectors(testCase)
root = localRoot();
vectors = readtable(fullfile(root, "channel_negative_test_vectors.csv"), ...
    "TextType", "string");
types = unique(vectors.NegativeType, "stable");
for index = 1:numel(types)
    row = find(vectors.NegativeType == types(index),1);
    state = localInvalidStateFixture(types(index));
    before = state;
    verifyError(testCase, ...
        @() sixgr.channel.validateStrictRuntimeState(state), ...
        vectors.ExpectedError(row));
    verifyEqual(testCase,state,before);
end
end

function [input, expected] = localPair(inputName, expectedName)
root = localRoot();
input = readtable(fullfile(root, inputName), "TextType", "string");
expected = readtable(fullfile(root, expectedName), "TextType", "string");
end

function root = localRoot()
root = fullfile(fileparts(mfilename("fullpath")), "vectors", "channel");
end

function state = localInvalidStateFixture(negativeType)
% Read the runner fixture through its executed output contract.  The
% validator itself is independently exercised here with one representative
% mutation per typed error family.
switch string(negativeType)
    case "MISSING_OBSERVED_DISTANCE"
        state=struct("Kind","OBSERVED_GEOMETRY","SignedDoppler_Hz",1);
    case "MISSING_OBSERVED_DOPPLER"
        state=struct("Kind","OBSERVED_GEOMETRY","Distance3D_m",1);
    case "CONFIGURED_AS_OBSERVED"
        state=struct("Kind","PROVENANCE","Observed",true,"ProvenanceClass","configured");
    case "CIRCULAR_PATHLOSS_COMPARE"
        state=struct("Kind","COMPARISON","ExpectedSourceID","x","ActualSourceID","x");
    case "UNKNOWN_COORDINATE_FRAME"
        state=struct("Kind","COORDINATE_FRAME","Frame","WGS84","Units","m");
    case "DUPLICATE_CLONE_ID"
        state=struct("Kind","TOPOLOGY","CloneIDs",["x","x"]);
    case "OUTSIDE_DROP_POLYGON"
        state=struct("Kind","DROP","InsideDeclaredRegion",false);
    case "UNKNOWN_LOS_SCENARIO"
        state=struct("Kind","LOS_SCENARIO","Scenario","x");
    case "LOS_TELEPORT"
        state=struct("Kind","LOS_TRANSITION","CorrelatedTransition",false);
    case "PATHLOSS_OUTSIDE_RANGE"
        state=struct("Kind","PATHLOSS_APPLICABILITY","Distance2D_m",11, ...
            "MinimumDistance_m",1,"MaximumDistance_m",10,"HUT_m",1, ...
            "MinimumHUT_m",1,"MaximumHUT_m",2);
    case "MISSING_LSP_MATRIX"
        state=struct("Kind","LSP_PROFILE","ProfileAvailable",false);
    case "NON_PSD_LSP_MATRIX"
        state=struct("Kind","LSP_COVARIANCE","Covariance",[1 2;2 1]);
    case "LSP_DISCONTINUITY"
        state=struct("Kind","LSP_CONTINUITY","ObservedDelta",2,"MaximumDelta",1);
    case "UNKNOWN_O2I_MATERIAL"
        state=struct("Kind","O2I_MATERIAL","MaterialRegistered",false);
    case "INVALID_INDOOR_DISTANCE"
        state=struct("Kind","INDOOR_DISTANCE","IndoorDistance_m",2, ...
            "MaximumIndoorDistance_m",1);
    case "MISSING_OXYGEN_TABLE"
        state=struct("Kind","OXYGEN_PROFILE","ProfilePinned",false);
    case "INVALID_TDL_DELAY_SPREAD"
        state=struct("Kind","TDL_PROFILE","Profile","TDL-C", ...
            "DelaySpread_s",2,"SupportedDelaySpreads_s",1);
    case "INVALID_CDL_ARRAY"
        state=struct("Kind","CDL_PROFILE","Profile","CDL-D","ArrayCompatible",false);
    case "ARRAY_DIMENSION_MISMATCH"
        state=struct("Kind","ANTENNA_ARRAY","ElementCount",3,"PanelDimensions",[2 2]);
    case "PORT_PROJECTION_ENERGY"
        state=struct("Kind","PORT_PROJECTION","InputPower",1,"OutputPower",2,"Tolerance",0);
    case "DOPPLER_SIGN_FLIP"
        state=struct("Kind","DOPPLER_STATE","ExpectedSign",1,"ActualDoppler_Hz",-1);
    case "MISSING_POWER_REFERENCE"
        state=struct("Kind","POWER_REFERENCE");
    case "POWER_RECONCILIATION"
        state=struct("Kind","POWER_RECONCILIATION","ExpectedPower_dBm",0, ...
            "MeasuredPower_dBm",1,"Tolerance_dB",0.05);
    case "MISSING_INTERFERER_CHANNEL"
        state=struct("Kind","INTERFERENCE_LINK","CompleteChannelState",false);
    case "INTERFERENCE_SUM_MISMATCH"
        state=struct("Kind","INTERFERENCE_LEDGER","Composite",1, ...
            "Contributions",0,"Tolerance",0);
    case "COVARIANCE_MISMATCH"
        state=struct("Kind","INTERFERENCE_COVARIANCE", ...
            "ExpectedCovariance",1,"MeasuredCovariance",2,"Tolerance",0);
    case "UNKNOWN_MOBILITY"
        state=struct("Kind","MOBILITY_MODEL","Model","x");
    case "VELOCITY_TELEPORT"
        state=struct("Kind","MOBILITY_TRAJECTORY","VelocityBefore_mps",0, ...
            "VelocityAfter_mps",10,"MaximumAcceleration_mps2",1,"DeltaTime_s",1);
    case "HANDOVER_WITHOUT_EVENT"
        state=struct("Kind","HANDOVER","DecodedEventPresent",false);
    case "UNSUPPORTED_BLOCKAGE"
        state=struct("Kind","BLOCKAGE","Profile","x");
    case "RAY_CONTRACT_MISSING"
        state=struct("Kind","RAY_CONTRACT");
    case "RAY_HASH_MISMATCH"
        state=struct("Kind","RAY_RESULT","ExpectedSceneSHA256","a", ...
            "ActualSceneSHA256","b");
    case "STRICT_FALLBACK"
        state=struct("Kind","STRICT_FALLBACK","FallbackUsed",true);
end
end
