classdef MACPDUDemultiplexer
    %MACPDUDEMULTIPLEXER Strict bounded decoder with byte ownership.
    methods (Static)
        function result=decode(direction,bytes)
            bytes=sixgr.l2.mac.requireMACOctets(bytes); offset=0;
            % Padding-only MAC PDUs have zero subPDUs, with the same schema
            % as populated results; never manufacture an empty SDU row.
            rows=repmat(struct('SubPDUIndex',0,'LCID',0,'Kind',"", ...
                'HeaderOffset',0,'HeaderLength',0,'PayloadOffset',0, ...
                'PayloadLength',0,'Payload',uint8.empty(1,0),'PayloadSHA256',""),0,1);
            while offset<numel(bytes)
                first=bytes(offset+1); lcid=double(bitand(first,63));
                if lcid==63
                    padding=numel(bytes)-offset; break;
                end
                [schema,lengthValue,headerLength]= ...
                    sixgr.l2.mac.MACSubheaderCodec.decode(direction,bytes(offset+1:end));
                if schema.SizeType=="fixed"
                    lengthValue=schema.FixedPayloadBytes;
                end
                if ~isfinite(lengthValue)
                    error("sixgr:mac:MACPDULengthOverrun", ...
                        "Variable CE must carry a length.");
                end
                payloadStart=offset+headerLength;
                payloadEnd=payloadStart+lengthValue;
                if payloadEnd>numel(bytes)
                    error("sixgr:mac:MACPDULengthOverrun", ...
                        "SubPDU overruns the transport block.");
                end
                payload=bytes(payloadStart+1:payloadEnd);
                index=numel(rows)+1;
                row=struct("SubPDUIndex",index-1,"LCID",lcid, ...
                    "Kind",schema.Kind,"HeaderOffset",offset, ...
                    "HeaderLength",headerLength,"PayloadOffset",payloadStart, ...
                    "PayloadLength",lengthValue,"Payload",payload, ...
                    "PayloadSHA256",sixgr.l2.mac.MACHash.of(payload));
                if isempty(rows), rows=row; else, rows(end+1)=row; end %#ok<AGROW>
                offset=payloadEnd;
            end
            if ~exist("padding","var"), padding=0; end
            result=struct("SubPDUs",rows,"PaddingBytes",padding, ...
                "ConsumedBytes",numel(bytes),"SHA256",sixgr.l2.mac.MACHash.of(bytes));
        end
    end
end
