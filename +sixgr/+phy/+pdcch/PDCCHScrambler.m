classdef PDCCHScrambler
    %PDCCHSCRAMBLER Pure TS 38.211 Gold sequence and PDCCH scrambling.

    methods (Static)
        function result = scramble(bits, nID, nRNTI)
            bits = int8(bits(:));
            if isempty(bits) || any(bits ~= 0 & bits ~= 1)
                error("sixgr:phy:pdcch:payload_length_mismatch", ...
                    "PDCCH scrambling input must be a nonempty binary vector.");
            end
            nID = localUInt(nID, 0, 65535, "NID");
            nRNTI = localUInt(nRNTI, 0, 65535, "NRNTI");
            cInit = mod(nRNTI * 2^16 + nID, 2^31);
            sequence = sixgr.phy.pdcch.PDCCHScrambler.gold(cInit, numel(bits));
            scrambled = bitxor(bits, sequence);
            result = struct( ...
                "CInit", double(cInit), ...
                "Sequence", sequence, ...
                "ScrambledBits", scrambled, ...
                "SequenceSHA256", localBitStringHash(sequence), ...
                "ScrambledSHA256", localBitStringHash(scrambled), ...
                "NID", double(nID), ...
                "NRNTI", double(nRNTI));
        end

        function sequence = gold(cInit, count)
            cInit = localUInt(cInit, 0, 2^31-1, "cInit");
            count = localUInt(count, 0, intmax("int32"), "count");
            nc = 1600;
            total = nc + count + 31;
            x1 = zeros(total,1,"int8");
            x2 = zeros(total,1,"int8");
            x1(1) = 1;
            u = uint64(cInit);
            for ii = 1:31
                x2(ii) = int8(bitget(u, ii));
            end
            for nn = 1:(nc + count)
                x1(nn+31) = bitxor(x1(nn+3), x1(nn));
                x2(nn+31) = bitxor(bitxor(x2(nn+3), x2(nn+2)), ...
                    bitxor(x2(nn+1), x2(nn)));
            end
            sequence = bitxor(x1(nc+1:nc+count), x2(nc+1:nc+count));
        end
    end
end

function value = localUInt(value, minimum, maximum, name)
value = double(value);
if ~(isscalar(value) && isfinite(value) && value >= minimum && ...
        value <= maximum && value == fix(value))
    error("sixgr:phy:pdcch:field_out_of_range", ...
        "%s must be an integer in [%g,%g].", name, minimum, maximum);
end
end

function value = localBitStringHash(bits)
text = char(join(string(bits(:).'), ""));
value = string(sixgr.rrc.asn1.sha256Hex(uint8(unicode2native(text, "UTF-8"))));
end
