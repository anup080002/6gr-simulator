classdef ProtocolInvariantGuard
    %PROTOCOLINVARIANTGUARD Typed fail-closed cross-layer invariants.

    methods (Static)
        function requireConservation(values)
            required = ["ArrivedBytes","QueuedBytes","InFlightBytes", ...
                "DeliveredBytes","DroppedBytes","UnownedBytes", ...
                "DuplicateDeliveredBytes"];
            if ~all(isfield(values, cellstr(required)))
                error("sixgr:protocol:ConservationFailure", ...
                    "Conservation ledger is incomplete.");
            end
            equation = double(values.ArrivedBytes) - ...
                double(values.QueuedBytes) - double(values.InFlightBytes) - ...
                double(values.DeliveredBytes) - double(values.DroppedBytes);
            if equation ~= 0 || double(values.UnownedBytes) ~= 0 || ...
                    double(values.DuplicateDeliveredBytes) ~= 0
                error("sixgr:protocol:ConservationFailure", ...
                    "Protocol conservation invariant failed.");
            end
        end

        function rejectGlobalTrafficRNG(streamIdentity)
            if strlength(strtrim(string(streamIdentity))) == 0 || ...
                    lower(string(streamIdentity)) == "global"
                error("sixgr:traffic:NonDeterministicStream", ...
                    "Strict traffic requires a named per-flow random stream.");
            end
        end
    end
end
