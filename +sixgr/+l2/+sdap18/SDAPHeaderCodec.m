classdef SDAPHeaderCodec
    %SDAPHEADERCODEC TS 37.324 V18.0.0 directional one-byte headers.

    methods (Static)
        function byte = encode(direction, pduType, qfi, rdi, rqi)
            arguments
                direction (1,1) string
                pduType (1,1) string
                qfi (1,1) double
                rdi = []
                rqi = []
            end
            if qfi < 0 || qfi > 63 || qfi ~= floor(qfi)
                error("sixgr:sdap:MalformedPDU", ...
                    "SDAP QFI must be an integer in [0,63].");
            end
            direction = upper(direction);
            pduType = upper(pduType);
            if direction == "DL" && pduType == "DATA"
                if ~ismember(rdi, [0 1]) || ~ismember(rqi, [0 1])
                    error("sixgr:sdap:MalformedPDU", ...
                        "DL data SDAP requires one-bit RDI and RQI.");
                end
                byte = uint8(bitshift(uint8(rdi), 7) + ...
                    bitshift(uint8(rqi), 6) + uint8(qfi));
            elseif direction == "UL" && pduType == "DATA"
                byte = uint8(128 + qfi);
            elseif direction == "UL" && pduType == "END_MARKER"
                byte = uint8(qfi);
            else
                error("sixgr:sdap:MalformedPDU", ...
                    "Unsupported directional SDAP PDU tuple %s/%s.", ...
                    direction, pduType);
            end
        end

        function text = hex(byte)
            text = upper(string(dec2hex(uint8(byte), 2)));
        end

        function decoded = decode(direction,pduType,bytes)
            bytes=uint8(bytes(:).');
            if isempty(bytes)
                error("sixgr:sdap:MalformedPDU","SDAP PDU is empty.");
            end
            direction=upper(string(direction));
            pduType=upper(string(pduType));
            byte=bytes(1);
            if direction=="DL" && pduType=="DATA"
                decoded=struct("Direction",direction,"PDUType",pduType, ...
                    "QFI",double(bitand(byte,uint8(63))), ...
                    "RDI",double(bitget(byte,8)), ...
                    "RQI",double(bitget(byte,7)), ...
                    "DC",[],"Payload",bytes(2:end));
            elseif direction=="UL" && pduType=="DATA"
                if bitget(byte,8)~=1
                    error("sixgr:sdap:MalformedPDU", ...
                        "UL data SDAP D/C bit must be one.");
                end
                decoded=struct("Direction",direction,"PDUType",pduType, ...
                    "QFI",double(bitand(byte,uint8(63))), ...
                    "RDI",[],"RQI",[],"DC",1, ...
                    "Payload",bytes(2:end));
            elseif direction=="UL" && pduType=="END_MARKER"
                if bitget(byte,8)~=0
                    error("sixgr:sdap:MalformedPDU", ...
                        "UL end-marker SDAP D/C bit must be zero.");
                end
                decoded=struct("Direction",direction,"PDUType",pduType, ...
                    "QFI",double(bitand(byte,uint8(63))), ...
                    "RDI",[],"RQI",[],"DC",0, ...
                    "Payload",bytes(2:end));
            else
                error("sixgr:sdap:MalformedPDU", ...
                    "Unsupported directional SDAP decode tuple.");
            end
        end
    end
end
