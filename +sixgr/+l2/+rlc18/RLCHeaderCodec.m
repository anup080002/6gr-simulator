classdef RLCHeaderCodec
    %RLCHEADERCODEC TS 38.322 V18.2.0 bounded UM/AM data headers.

    methods (Static)
        function bytes = encodeUM(snBits, si, sn, so)
            arguments
                snBits (1,1) double
                si (1,1) double
                sn = []
                so = []
            end
            sixgr.l2.rlc18.RLCHeaderCodec.validateSI(si);
            if ~ismember(snBits, [6 12])
                error("sixgr:rlc:InvalidSNLength", ...
                    "UM SN length must be 6 or 12 bits.");
            end
            if si == 0
                if ~isempty(sn) || ~isempty(so)
                    error("sixgr:rlc:MalformedPDU", ...
                        "A complete UM SDU cannot carry SN or SO.");
                end
                bytes = uint8(0);
                return;
            end
            sn = sixgr.l2.rlc18.RLCHeaderCodec.validateUnsigned( ...
                sn, snBits, "SN");
            if snBits == 6
                bytes = uint8(bitshift(uint8(si), 6) + uint8(sn));
            else
                bytes = uint8([ ...
                    bitshift(uint8(si), 6) + uint8(bitshift(sn, -8)), ...
                    bitand(uint16(sn), uint16(255))]);
            end
            if ismember(si, [2 3])
                so = sixgr.l2.rlc18.RLCHeaderCodec.validateUnsigned( ...
                    so, 16, "SO");
                bytes = [bytes, sixgr.l2.rlc18.RLCHeaderCodec.u16be(so)]; %#ok<AGROW>
            elseif ~isempty(so)
                error("sixgr:rlc:MalformedPDU", ...
                    "SO is present only for middle/last UM segments.");
            end
        end

        function bytes = encodeAM(snBits, dc, poll, si, sn, so)
            arguments
                snBits (1,1) double
                dc (1,1) double
                poll (1,1) double
                si (1,1) double
                sn
                so = []
            end
            if ~ismember(snBits, [12 18])
                error("sixgr:rlc:InvalidSNLength", ...
                    "AM SN length must be 12 or 18 bits.");
            end
            if dc ~= 1 || ~ismember(poll, [0 1])
                error("sixgr:rlc:MalformedPDU", ...
                    "AM data header requires D/C=1 and a one-bit poll field.");
            end
            sixgr.l2.rlc18.RLCHeaderCodec.validateSI(si);
            sn = sixgr.l2.rlc18.RLCHeaderCodec.validateUnsigned( ...
                sn, snBits, "SN");
            first = bitshift(uint8(dc), 7) + bitshift(uint8(poll), 6) + ...
                bitshift(uint8(si), 4);
            if snBits == 12
                bytes = uint8([first + uint8(bitshift(sn, -8)), ...
                    bitand(uint16(sn), uint16(255))]);
            else
                % The 18-bit AM SN occupies the high 18 bits of the
                % remaining 20-bit header field; its two low bits are
                % reserved and encoded as zero.
                bytes = uint8([first + uint8(bitshift(sn, -14)), ...
                    bitand(uint32(bitshift(sn, -6)), uint32(255)), ...
                    bitand(bitshift(uint32(sn), 2), uint32(255))]);
            end
            if ismember(si, [2 3])
                so = sixgr.l2.rlc18.RLCHeaderCodec.validateUnsigned( ...
                    so, 16, "SO");
                bytes = [bytes, sixgr.l2.rlc18.RLCHeaderCodec.u16be(so)]; %#ok<AGROW>
            elseif ~isempty(so)
                error("sixgr:rlc:MalformedPDU", ...
                    "SO is present only for middle/last AM segments.");
            end
        end

        function text = hex(bytes)
            text = upper(string(reshape(dec2hex(uint8(bytes), 2).', 1, [])));
        end

        function decoded = decodeUM(bytes, snBits)
            bytes = uint8(bytes(:).');
            if ~ismember(snBits,[6 12]) || isempty(bytes)
                error("sixgr:rlc:MalformedPDU", ...
                    "UM PDU is empty or uses an invalid SN length.");
            end
            si = double(bitshift(bytes(1),-6));
            if si==0
                headerBytes=1; sn=[]; so=[];
                if bitand(bytes(1),uint8(63))~=0
                    error("sixgr:rlc:MalformedPDU", ...
                        "Complete UM PDU reserved bits must be zero.");
                end
            else
                if snBits==6
                    headerBytes=1;
                    sn=double(bitand(bytes(1),uint8(63)));
                else
                    if numel(bytes)<2
                        error("sixgr:rlc:MalformedPDU","Truncated UM header.");
                    end
                    headerBytes=2;
                    sn=double(bitshift(uint16(bitand(bytes(1),uint8(15))),8) + ...
                        uint16(bytes(2)));
                end
                so=[];
                if ismember(si,[2 3])
                    if numel(bytes)<headerBytes+2
                        error("sixgr:rlc:MalformedPDU","Truncated UM SO.");
                    end
                    so=double(bitshift(uint16(bytes(headerBytes+1)),8) + ...
                        uint16(bytes(headerBytes+2)));
                    headerBytes=headerBytes+2;
                end
            end
            decoded=struct("SI",si,"SN",sn,"SO",so, ...
                "HeaderBytes",headerBytes,"Payload",bytes(headerBytes+1:end));
        end

        function decoded = decodeAM(bytes, snBits)
            bytes=uint8(bytes(:).');
            baseBytes=2+double(snBits==18);
            if ~ismember(snBits,[12 18]) || numel(bytes)<baseBytes
                error("sixgr:rlc:MalformedPDU", ...
                    "AM PDU is truncated or uses an invalid SN length.");
            end
            dc=double(bitget(bytes(1),8));
            poll=double(bitget(bytes(1),7));
            si=double(bitand(bitshift(bytes(1),-4),uint8(3)));
            if dc~=1
                error("sixgr:rlc:MalformedPDU", ...
                    "Bounded AM data PDU requires D/C=1.");
            end
            if snBits==12
                sn=double(bitshift(uint16(bitand(bytes(1),uint8(15))),8) + ...
                    uint16(bytes(2)));
            else
                if bitand(bytes(3),uint8(3))~=0
                    error("sixgr:rlc:MalformedPDU", ...
                        "AM18 reserved bits must be zero.");
                end
                sn=double(bitshift(uint32(bitand(bytes(1),uint8(15))),14) + ...
                    bitshift(uint32(bytes(2)),6) + ...
                    bitshift(uint32(bytes(3)),-2));
            end
            headerBytes=baseBytes; so=[];
            if ismember(si,[2 3])
                if numel(bytes)<headerBytes+2
                    error("sixgr:rlc:MalformedPDU","Truncated AM SO.");
                end
                so=double(bitshift(uint16(bytes(headerBytes+1)),8) + ...
                    uint16(bytes(headerBytes+2)));
                headerBytes=headerBytes+2;
            end
            decoded=struct("DC",dc,"Poll",poll,"SI",si, ...
                "SN",sn,"SO",so,"HeaderBytes",headerBytes, ...
                "Payload",bytes(headerBytes+1:end));
        end
    end

    methods (Static, Access = private)
        function validateSI(si)
            if ~(isscalar(si) && isfinite(si) && ismember(si, 0:3))
                error("sixgr:rlc:MalformedPDU", ...
                    "Segmentation information must be an integer in [0,3].");
            end
        end

        function value = validateUnsigned(value, bits, name)
            if isempty(value) || ~isscalar(value) || ~isfinite(value) || ...
                    value ~= floor(value) || value < 0 || value >= 2^bits
                error("sixgr:rlc:MalformedPDU", ...
                    "%s does not fit in %d bits.", name, bits);
            end
            value = double(value);
        end

        function value = u16be(input)
            value = uint8([bitshift(uint16(input), -8), ...
                bitand(uint16(input), uint16(255))]);
        end
    end
end
