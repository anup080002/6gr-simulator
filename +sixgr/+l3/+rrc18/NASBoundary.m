classdef NASBoundary
    %NASBOUNDARY Typed external N1/N2 boundary; no synthetic success.

    methods (Static)
        function event = request(ueID, messageClass, nasBytes, transactionID)
            arguments
                ueID (1,1) string
                messageClass (1,1) string
                nasBytes
                transactionID (1,1) string
            end
            event = struct("UEID", ueID, "BoundaryDirection", "REQUEST", ...
                "MessageClass", messageClass, ...
                "ExternalTransactionID", transactionID, ...
                "PayloadSHA256", sixgr.protocol.ProtocolHash.bytes( ...
                uint8(nasBytes)), "ExternalResult", "PENDING", ...
                "RRCStateChangeAllowed", false);
        end

        function event = indication(requestEvent, result, decodedResult)
            arguments
                requestEvent struct
                result (1,1) string
                decodedResult = struct()
            end
            result = upper(result);
            if ~ismember(result, ["SUCCESS","FAILURE"])
                error("sixgr:rrc:ExternalNASRequired", ...
                    "NAS result must originate externally as SUCCESS or FAILURE.");
            end
            if isempty(fieldnames(decodedResult))
                error("sixgr:rrc:ExternalNASRequired", ...
                    "A decoded external NAS result is required.");
            end
            event = requestEvent;
            event.BoundaryDirection = "INDICATION";
            event.ExternalResult = result;
            event.RRCStateChangeAllowed = result == "SUCCESS";
            event.DecodedResultSHA256 = ...
                sixgr.protocol.ProtocolHash.bytes(jsonencode(decodedResult));
        end
    end
end
