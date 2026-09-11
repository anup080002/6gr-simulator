classdef MACSubheaderCodec
    %MACSUBHEADERCODEC Exact bounded one-/two-/three-byte subheaders.
    methods (Static)
        function bytes=encode(direction,lcid,payloadLength)
            schema=sixgr.l2.mac.MACCESchemaRegistry.resolve(direction,lcid);
            payloadLength=double(payloadLength);
            if ~isscalar(payloadLength) || ~isfinite(payloadLength) || ...
                    payloadLength<0 || payloadLength>65535 || payloadLength~=fix(payloadLength)
                error("sixgr:mac:MACPDULengthOverrun","Invalid subPDU length.");
            end
            if schema.SizeType=="fixed" && payloadLength~=schema.FixedPayloadBytes
                error("sixgr:mac:FixedMACPayloadLengthMismatch", ...
                    "%s LCID %d requires exactly %d payload octets, got %d.", ...
                    direction,lcid,schema.FixedPayloadBytes,payloadLength);
            end
            if schema.Kind=="SDU" && lcid~=0 && payloadLength==0
                error("sixgr:mac:ZeroLengthLogicalChannelSDU", ...
                    "Logical-channel MAC SDU cannot be empty.");
            end
            if schema.SizeType=="fixed" || schema.SizeType=="implicit"
                bytes=uint8(lcid); return;
            end
            if payloadLength<=255
                bytes=uint8([lcid bitand(payloadLength,255)]);
            else
                bytes=uint8([bitor(lcid,64) bitshift(payloadLength,-8) bitand(payloadLength,255)]);
            end
        end
        function [schema,payloadLength,headerLength]=decode(direction,bytes)
            bytes=uint8(bytes(:).');
            if isempty(bytes), error("sixgr:mac:TruncatedMACPDU","Missing subheader."); end
            lcid=bitand(bytes(1),63);
            schema=sixgr.l2.mac.MACCESchemaRegistry.resolve(direction,double(lcid));
            if schema.SizeType=="fixed" || schema.SizeType=="implicit"
                payloadLength=schema.FixedPayloadBytes; headerLength=1; return;
            end
            f=bitget(bytes(1),7);
            headerLength=2+double(f);
            if numel(bytes)<headerLength
                error("sixgr:mac:TruncatedMACPDU","Truncated length field.");
            end
            if f==0
                payloadLength=double(bytes(2));
            else
                payloadLength=double(bytes(2))*256+double(bytes(3));
            end
            if schema.Kind=="SDU" && double(lcid)~=0 && payloadLength==0
                error("sixgr:mac:ZeroLengthLogicalChannelSDU", ...
                    "Logical-channel MAC SDU cannot be empty.");
            end
        end
    end
end
