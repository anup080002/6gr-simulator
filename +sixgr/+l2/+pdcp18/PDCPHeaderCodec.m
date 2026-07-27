classdef PDCPHeaderCodec
    %PDCPHEADERCODEC TS 38.323 V18.5.0 bounded data PDU headers.

    methods (Static)
        function bytes = encode(bearerType, snBits, sn)
            arguments
                bearerType (1,1) string
                snBits (1,1) double
                sn (1,1) double
            end
            bearerType = upper(bearerType);
            if bearerType == "SRB"
                if snBits ~= 12
                    error("sixgr:pdcp:MalformedPDU", ...
                        "The bounded SRB data PDU uses a 12-bit SN.");
                end
                sixgr.l2.pdcp18.PDCPHeaderCodec.validateSN(sn, snBits);
                bytes = uint8([bitshift(uint16(sn), -8), ...
                    bitand(uint16(sn), uint16(255))]);
                return;
            end
            if bearerType ~= "DRB" || ~ismember(snBits, [12 18])
                error("sixgr:pdcp:MalformedPDU", ...
                    "The bounded DRB data PDU uses a 12- or 18-bit SN.");
            end
            sixgr.l2.pdcp18.PDCPHeaderCodec.validateSN(sn, snBits);
            if snBits == 12
                bytes = uint8([128 + bitshift(uint16(sn), -8), ...
                    bitand(uint16(sn), uint16(255))]);
            else
                bytes = uint8([128 + bitshift(uint32(sn), -16), ...
                    bitand(bitshift(uint32(sn), -8), uint32(255)), ...
                    bitand(uint32(sn), uint32(255))]);
            end
        end

        function text = hex(bytes)
            text = upper(string(reshape(dec2hex(uint8(bytes), 2).', 1, [])));
        end

        function decoded = decode(bearerType,snBits,bytes)
            bearerType=upper(string(bearerType));
            bytes=uint8(bytes(:).');
            headerBytes=2+double(bearerType=="DRB" && snBits==18);
            if numel(bytes)<headerBytes
                error("sixgr:pdcp:MalformedPDU","PDCP PDU is truncated.");
            end
            if bearerType=="SRB" && snBits==12
                if bitand(bytes(1),uint8(240))~=0
                    error("sixgr:pdcp:MalformedPDU", ...
                        "SRB reserved header bits are nonzero.");
                end
                sn=double(bitshift(uint16(bytes(1)),8)+uint16(bytes(2)));
            elseif bearerType=="DRB" && snBits==12
                if bitget(bytes(1),8)~=1 || ...
                        bitand(bytes(1),uint8(112))~=0
                    error("sixgr:pdcp:MalformedPDU", ...
                        "DRB12 D/C or reserved bits are invalid.");
                end
                sn=double(bitshift(uint16(bitand(bytes(1),uint8(15))),8)+ ...
                    uint16(bytes(2)));
            elseif bearerType=="DRB" && snBits==18
                if bitget(bytes(1),8)~=1 || ...
                        bitand(bytes(1),uint8(124))~=0
                    error("sixgr:pdcp:MalformedPDU", ...
                        "DRB18 D/C or reserved bits are invalid.");
                end
                sn=double(bitshift(uint32(bitand(bytes(1),uint8(3))),16)+ ...
                    bitshift(uint32(bytes(2)),8)+uint32(bytes(3)));
            else
                error("sixgr:pdcp:MalformedPDU", ...
                    "Unsupported PDCP bearer/SN tuple.");
            end
            decoded=struct("BearerType",bearerType,"SNBits",snBits, ...
                "SN",sn,"HeaderBytes",headerBytes, ...
                "Payload",bytes(headerBytes+1:end));
        end
    end

    methods (Static, Access = private)
        function validateSN(sn, bits)
            if ~isfinite(sn) || sn ~= floor(sn) || sn < 0 || sn >= 2^bits
                error("sixgr:pdcp:MalformedPDU", ...
                    "PDCP SN does not fit in %d bits.", bits);
            end
        end
    end
end
