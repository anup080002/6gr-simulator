classdef RLCStatusCodec
    %RLCSTATUSCODEC Bounded exact-size TS 38.322 STATUS encoder.

    methods (Static)
        function result = encode(snBits, ackSN, nackCount, segmentNACK, nackRange)
            arguments
                snBits (1,1) double
                ackSN (1,1) double
                nackCount (1,1) double
                segmentNACK (1,1) logical
                nackRange (1,1) logical
            end
            if ~ismember(snBits, [12 18])
                error("sixgr:rlc:InvalidSNLength", ...
                    "AM STATUS SN length must be 12 or 18 bits.");
            end
            if ackSN < 0 || ackSN ~= floor(ackSN) || ackSN >= 2^snBits || ...
                    nackCount < 0 || nackCount ~= floor(nackCount)
                error("sixgr:rlc:StatusEncodingFailed", ...
                    "ACK_SN/NACK count is outside the bounded STATUS profile.");
            end
            baseBits = 24;
            if snBits == 12
                entryControlBits = 4;
            else
                entryControlBits = 6;
            end
            nackBits = snBits + entryControlBits;
            if segmentNACK
                nackBits = nackBits + 32;
            end
            if nackRange
                nackBits = nackBits + 8;
            end
            bitCount = baseBits + nackCount * nackBits;
            bits = zeros(1, bitCount, "uint8");
            % D/C=0, CPT=000. ACK_SN begins after those four bits.
            bits(5:4+snBits) = sixgr.l2.rlc18.RLCStatusCodec.toBits( ...
                ackSN, snBits);
            if nackCount > 0
                bits(5+snBits) = 1;
            end
            cursor = baseBits + 1;
            for index = 1:nackCount
                nackSN = mod(ackSN + index, 2^snBits);
                bits(cursor:cursor+snBits-1) = ...
                    sixgr.l2.rlc18.RLCStatusCodec.toBits(nackSN, snBits);
                cursor = cursor + snBits;
                bits(cursor) = double(index < nackCount);
                bits(cursor+1) = uint8(segmentNACK);
                bits(cursor+2) = uint8(nackRange);
                % Advance over E1/E2/E3 and the reserved alignment bits.
                cursor = cursor + entryControlBits;
                if segmentNACK
                    bits(cursor:cursor+15) = ...
                        sixgr.l2.rlc18.RLCStatusCodec.toBits(0, 16);
                    bits(cursor+16:cursor+31) = ...
                        sixgr.l2.rlc18.RLCStatusCodec.toBits(65535, 16);
                    cursor = cursor + 32;
                end
                if nackRange
                    bits(cursor:cursor+7) = ...
                        sixgr.l2.rlc18.RLCStatusCodec.toBits(1, 8);
                    cursor = cursor + 8;
                end
            end
            result = struct("Bits", bits, ...
                "Bytes", sixgr.l2.rlc18.RLCStatusCodec.pack(bits), ...
                "BitCount", bitCount, "ByteCount", bitCount / 8);
        end
    end

    methods (Static, Access = private)
        function bits = toBits(value, n)
            bits = uint8(bitget(uint64(value), n:-1:1));
        end

        function bytes = pack(bits)
            bits = reshape(uint8(bits), 8, []).';
            weights = uint16(2 .^ (7:-1:0));
            bytes = uint8(double(bits) * double(weights(:)));
            bytes = bytes(:).';
        end
    end
end
