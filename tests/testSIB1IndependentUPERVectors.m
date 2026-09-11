function tests = testSIB1IndependentUPERVectors
%TESTSIB1INDEPENDENTUPERVECTORS Bit-exact external Release-18 vectors.
tests = functiontests(localfunctions);
end

function testPositiveVectorsBitExact(testCase)
vectors = localVectors();
vectors = vectors(vectors.ExpectedBehavior == "ACCEPT", :);
verifyGreaterThanOrEqual(testCase, height(vectors), 5);
for ii = 1:height(vectors)
    bits = localHexToBits(vectors.UPERHex(ii));
    [message, decodedMeta] = sixgr.rrc.asn1.decodeSIB1UPER(bits);
    [actualBits, encodedMeta] = ...
        sixgr.rrc.asn1.encodeSIB1UPER(message);
    verifyEqual(testCase, actualBits, bits, ...
        sprintf("Independent vector %s mismatch.", vectors.VectorID(ii)));
    verifyEqual(testCase, string(encodedMeta.PayloadHash), ...
        vectors.SHA256(ii));
    verifyEqual(testCase, string(decodedMeta.ASN1SchemaSHA256), ...
        vectors.SchemaSHA256(ii));
    verifyFalse(testCase, logical(decodedMeta.SelfConsistencyOnly));
    expected = jsondecode(vectors.SemanticJSON(ii));
    sib = message.message.c1.systemInformationBlockType1;
    verifyEqual(testCase, double(sib.cellAccessRelatedInfo.cellIdentity), double(expected.cell_identity));
    verifyEqual(testCase, double(sib.cellAccessRelatedInfo.trackingAreaCode), double(expected.tracking_area_code));
    if isfield(expected,"pdcch_config_common")
        received = sixgr.mac.ra.installDecodedSIB1RACHConfig(struct(), message);
        verifyTrue(testCase, received.UECommonCellConfiguration.PDCCHConfigCommonPresent);
        verifyEqual(testCase, double(received.UECommonCellConfiguration.PDCCHConfigCommon.ra_SearchSpace), ...
            double(expected.pdcch_config_common.ra_SearchSpace));
        verifyEqual(testCase, received.random_access.initial_ul_bwp_start, 7);
        verifyEqual(testCase, received.random_access.initial_ul_bwp_size, 52);
        verifyEqual(testCase, received.UECommonCellConfiguration.InitialULBWP.SubcarrierSpacing_kHz, 15);
    end
    if isfield(expected,"pucch_config_common")
        received = sixgr.mac.ra.installDecodedSIB1RACHConfig(struct(), message);
        actual = received.UECommonCellConfiguration.PUCCHConfigCommon;
        verifyTrue(testCase, received.UECommonCellConfiguration.PUCCHConfigCommonPresent);
        verifyEqual(testCase, double(actual.pucch_ResourceCommon), ...
            double(expected.pucch_config_common.pucch_ResourceCommon));
        verifyEqual(testCase, string(actual.pucch_GroupHopping), ...
            string(expected.pucch_config_common.pucch_GroupHopping));
        verifyEqual(testCase, double(actual.hoppingId), ...
            double(expected.pucch_config_common.hoppingId));
        verifyEqual(testCase, double(actual.p0_nominal), ...
            double(expected.pucch_config_common.p0_nominal));
    end
end
end

function testNegativeVectorsFailClosed(testCase)
vectors = localVectors();
vectors = vectors(vectors.ExpectedBehavior == "REJECT", :);
verifyGreaterThanOrEqual(testCase, height(vectors), 3);
for ii = 1:height(vectors)
    observed = "";
    try
        sixgr.rrc.asn1.decodeSIB1UPER( ...
            localHexToBits(vectors.UPERHex(ii)));
    catch cause
        observed = string(cause.identifier);
    end
    verifyEqual(testCase, observed, vectors.ExpectedError(ii), ...
        sprintf("Negative vector %s did not fail closed.", ...
        vectors.VectorID(ii)));
end
end

function vectors = localVectors()
path = fullfile(fileparts(mfilename("fullpath")), ...
    "vectors", "initial_access", ...
    "sib1_release18_uper_vectors.csv");
vectors = readtable(path, ...
    "TextType", "string", ...
    "VariableNamingRule", "preserve", ...
    "Delimiter", ",");
for name = [ ...
        "VectorID","ExpectedBehavior","ExpectedError","UPERHex", ...
        "SHA256","SchemaSHA256"]
    vectors.(name) = string(vectors.(name));
end
verify = lower(string(vectors.SelfConsistencyOnly));
assert(all(verify == "false" | verify == "0"), ...
    "Independent vectors must not be self-consistency-only.");
end

function bits = localHexToBits(hex)
bytes = uint8(sscanf(char(hex), "%2x"));
bits = zeros(numel(bytes) * 8, 1, "int8");
for ii = 1:numel(bytes)
    for jj = 1:8
        bits((ii - 1) * 8 + jj) = int8( ...
            bitget(bytes(ii), 9 - jj));
    end
end
end
