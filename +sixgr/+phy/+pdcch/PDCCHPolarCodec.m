classdef PDCCHPolarCodec
    %PDCCHPOLARCODEC Release-pinned Toolbox adapter with explicit invariants.

    methods (Static)
        function result = encode(payloadBits, rnti, aggregationLevel)
            payloadBits = int8(payloadBits(:));
            if isempty(payloadBits) || any(payloadBits ~= 0 & payloadBits ~= 1)
                error("sixgr:phy:pdcch:payload_length_mismatch", ...
                    "PDCCH Polar payload must be a nonempty binary vector.");
            end
            E = sixgr.phy.pdcch.PDCCHSpecificationProfile.encodedBits(aggregationLevel);
            KPayload = numel(payloadBits);
            KWithCRC = KPayload + 24;
            if KWithCRC > 164
                error("sixgr:phy:pdcch:payload_length_mismatch", ...
                    "DCI payload plus CRC exceeds the 164-bit PDCCH Polar limit.");
            end
            crc = sixgr.phy.pdcch.DCICRC24C.encode(payloadBits, rnti);
            rateMatched = int8(nrDCIEncode(payloadBits, double(rnti), E));
            [N, mode] = localMotherLengthAndMode(KWithCRC, E);
            result = struct( ...
                "KPayload", KPayload, ...
                "KWithCRC", KWithCRC, ...
                "AggregationLevel", double(aggregationLevel), ...
                "E", E, ...
                "PolarN", N, ...
                "CodeRate", KWithCRC / E, ...
                "RateMatchMode", mode, ...
                "CRCCodewordBits", crc.MaskedCodewordBits, ...
                "CRCCodewordSHA256", crc.CodewordSHA256, ...
                "RateMatchedBits", rateMatched, ...
                "EncodedSHA256", crc.CodewordSHA256, ...
                "RateMatchedSHA256", localHash(rateMatched), ...
                "Adapter", "MATLAB_5G_Toolbox_nrDCIEncode_release_pinned", ...
                "Status", "PASS");
        end

        function result = decode(llr, KPayload, rnti, listLength)
            arguments
                llr (:,1) double
                KPayload (1,1) double
                rnti (1,1) double
                listLength (1,1) double = 8
            end
            if isempty(llr) || any(~isfinite(llr))
                error("sixgr:phy:pdcch:payload_length_mismatch", ...
                    "PDCCH Polar decoder requires finite rate-recovered LLRs.");
            end
            if ~(KPayload >= 1 && KPayload == fix(KPayload))
                error("sixgr:phy:pdcch:payload_length_mismatch", ...
                    "KPayload must be a positive integer.");
            end
            [bits, errFlag] = nrDCIDecode(llr, KPayload, listLength, rnti);
            result = struct("PayloadBits", int8(bits(:)), ...
                "CRCError", logical(errFlag), ...
                "CRCPassed", ~logical(errFlag), ...
                "ListLength", listLength, ...
                "Status", string(ternary(errFlag == 0, "PASS", "CRC_RNTI_MISMATCH")));
        end

        function result = roundTrip(payloadBits, rnti, aggregationLevel, listLength)
            if nargin < 4
                listLength = 8;
            end
            encoded = sixgr.phy.pdcch.PDCCHPolarCodec.encode( ...
                payloadBits, rnti, aggregationLevel);
            llr = 20 * (1 - 2*double(encoded.RateMatchedBits));
            decoded = sixgr.phy.pdcch.PDCCHPolarCodec.decode( ...
                llr, numel(payloadBits), rnti, listLength);
            result = encoded;
            result.DecodedBits = decoded.PayloadBits;
            result.CRCError = decoded.CRCError;
            result.RoundTripBitErrors = sum(int8(payloadBits(:)) ~= decoded.PayloadBits);
            result.Status = string(ternary(result.RoundTripBitErrors == 0 && ~result.CRCError, "PASS", "FAIL"));
        end
    end
end

function [N, mode] = localMotherLengthAndMode(K, E)
n1 = ceil(log2(E));
if E <= (9/8)*2^(n1-1) && K/E < 9/16
    n1 = n1 - 1;
end
n2 = ceil(log2(K/(1/8)));
n = max(5, min([n1 n2 9]));
N = 2^n;
if E >= N
    mode = "repetition";
elseif K/E <= 7/16
    mode = "puncturing";
else
    mode = "shortening";
end
end

function value = localHash(bits)
value = string(sixgr.rrc.asn1.sha256Hex(uint8(bits(:))));
end

function value = ternary(condition, a, b)
if condition
    value = a;
else
    value = b;
end
end
