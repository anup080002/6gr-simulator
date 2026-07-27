classdef MACPDUAssembler
    %MACPDUASSEMBLER Exact bounded assembly; never drops an SDU silently.
    methods (Static)
        function result=assemble(direction,subPDUs,tbsBytes)
            direction=upper(string(direction));
            encoded=uint8.empty(1,0); rows=struct([]);
            for ii=1:numel(subPDUs)
                item=subPDUs(ii);
                payload=uint8(item.Payload(:).');
                header=sixgr.l2.mac.MACSubheaderCodec.encode( ...
                    direction,item.LCID,numel(payload));
                if numel(encoded)+numel(header)+numel(payload)>tbsBytes
                    error("sixgr:mac:MACPDUCapacityExceeded", ...
                        "SubPDU %d does not fit; caller must segment it.",ii);
                end
                headerOffset=numel(encoded);
                payloadOffset=headerOffset+numel(header);
                encoded=[encoded header payload]; %#ok<AGROW>
                row=struct("SubPDUIndex",ii-1,"LCID",item.LCID, ...
                    "Kind",sixgr.l2.mac.MACCESchemaRegistry.resolve( ...
                    direction,item.LCID).Kind, ...
                    "HeaderOffset",headerOffset,"HeaderLength",numel(header), ...
                    "PayloadOffset",payloadOffset,"PayloadLength",numel(payload), ...
                    "OwnerID",string(item.OwnerID), ...
                    "PayloadSHA256",sixgr.l2.mac.MACHash.of(payload));
                if isempty(rows), rows=row; else, rows(end+1)=row; end %#ok<AGROW>
            end
            padding=tbsBytes-numel(encoded);
            if padding>0
                encoded=[encoded uint8(63) zeros(1,padding-1,"uint8")];
            end
            result=struct("Bytes",encoded,"SubPDUs",rows, ...
                "PaddingBytes",padding,"SHA256",sixgr.l2.mac.MACHash.of(encoded));
        end
    end
end
