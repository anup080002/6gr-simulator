classdef DCICRC24C
    %DCICRC24C Pure Release-18 DCI CRC24C and 16-bit RNTI masking.

    methods (Static)
        function result = encode(payloadBits, rnti)
            payloadBits = localBits(payloadBits, "payloadBits");
            rntiBits = localUIntBits(rnti, 16);
            augmented = [ones(24,1,"int8"); payloadBits; zeros(24,1,"int8")];
            polynomial = int8([1 1 0 1 1 0 0 1 0 1 0 1 1 0 0 0 1 0 0 0 1 0 1 1 1].');
            work = augmented;
            for ii = 1:(numel(work)-24)
                if work(ii) ~= 0
                    work(ii:ii+24) = bitxor(work(ii:ii+24), polynomial);
                end
            end
            crc = work(end-23:end);
            masked = crc;
            masked(9:24) = bitxor(masked(9:24), rntiBits);
            codeword = [payloadBits; masked];
            result = struct( ...
                "PayloadBits", payloadBits, ...
                "CRC24CBits", crc, ...
                "RNTIBits", rntiBits, ...
                "MaskedCRCBits", masked, ...
                "MaskedCodewordBits", codeword, ...
                "CRC24CSHA256", string(sixgr.rrc.asn1.asn1SHA256Hex(uint8(crc))), ...
                "CodewordSHA256", string(sixgr.rrc.asn1.asn1SHA256Hex(uint8(codeword))), ...
                "RNTI", double(rnti), ...
                "Polynomial", "D24+D23+D21+D20+D17+D15+D13+D12+D8+D4+D2+D+1");
        end

        function [passed, payload, details] = check(maskedCodewordBits, rnti)
            bits = localBits(maskedCodewordBits, "maskedCodewordBits");
            if numel(bits) <= 24
                error("sixgr:phy:pdcch:payload_length_mismatch", ...
                    "A DCI CRC codeword must contain payload bits plus 24 CRC bits.");
            end
            payload = bits(1:end-24);
            expected = sixgr.phy.pdcch.DCICRC24C.encode(payload, rnti);
            passed = isequal(bits, expected.MaskedCodewordBits);
            details = expected;
            details.ObservedCodewordBits = bits;
            details.MismatchCount = sum(bits ~= expected.MaskedCodewordBits);
            if ~passed
                details.Status = "CRC_RNTI_MISMATCH";
            else
                details.Status = "PASS";
            end
        end
    end
end

function bits = localBits(value, name)
if ~(isnumeric(value) || islogical(value))
    error("sixgr:phy:pdcch:payload_length_mismatch", ...
        "%s must be a binary vector.", name);
end
bits = int8(value(:));
if isempty(bits) || any(bits ~= 0 & bits ~= 1)
    error("sixgr:phy:pdcch:payload_length_mismatch", ...
        "%s must be a nonempty binary vector.", name);
end
end

function bits = localUIntBits(value, width)
value = double(value);
if ~(isscalar(value) && isfinite(value) && value >= 0 && ...
        value < 2^width && value == fix(value))
    error("sixgr:phy:pdcch:invalid_rnti_procedure", ...
        "RNTI must be an unsigned 16-bit integer.");
end
bits = zeros(width,1,"int8");
u = uint64(value);
for ii = 1:width
    bits(ii) = int8(bitget(u, width - ii + 1));
end
end
