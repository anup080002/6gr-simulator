classdef EventEnvelope
    %EVENTENVELOPE Immutable causality/provenance carrier.
    properties (SetAccess=immutable)
        EventID (1,1) string
        EventType (1,1) string
        Producer (1,1) string
        Consumer (1,1) string
        ProducedAt (1,1) double
        AvailableAt (1,1) double
        ExpiryAt (1,1) double
        ParentEventIDs (:,1) string
        RunID (1,1) string
        ConfigurationEpoch (1,1) double
        Payload
        PayloadSHA256 (1,1) string
    end
    methods
        function obj = EventEnvelope(eventType,producer,consumer, ...
                producedAt,availableAt,expiryAt,payload,varargin)
            ip = inputParser;
            ip.addParameter("RunID","",@(x)ischar(x)||isstring(x));
            ip.addParameter("ConfigurationEpoch",1,@isnumeric);
            ip.addParameter("ParentEventIDs",strings(0,1), ...
                @(x)ischar(x)||isstring(x)||iscellstr(x)); %#ok<ISCLSTR>
            ip.addParameter("EventID","",@(x)ischar(x)||isstring(x));
            ip.parse(varargin{:});
            times = double([producedAt availableAt expiryAt]);
            if any(~isfinite(times)) || times(1) > times(2) || ...
                    times(2) > times(3)
                error("sixgr:integration:InvalidEventTime", ...
                    "Event times must satisfy ProducedAt <= AvailableAt <= ExpiryAt.");
            end
            digest = sixgr.integration.IntegrationHash.data(payload);
            id = string(ip.Results.EventID);
            if strlength(id) == 0
                id = "EVT-" + extractBefore(sixgr.integration.IntegrationHash.data( ...
                    struct("Type",string(eventType),"Producer",string(producer), ...
                    "Consumer",string(consumer),"Times",times, ...
                    "PayloadSHA256",digest)),17);
            end
            obj.EventID = id; obj.EventType = string(eventType);
            obj.Producer = string(producer); obj.Consumer = string(consumer);
            obj.ProducedAt = times(1); obj.AvailableAt = times(2);
            obj.ExpiryAt = times(3);
            obj.ParentEventIDs = string(ip.Results.ParentEventIDs(:));
            obj.RunID = string(ip.Results.RunID);
            obj.ConfigurationEpoch = double(ip.Results.ConfigurationEpoch);
            obj.Payload = payload; obj.PayloadSHA256 = digest;
        end
        function assertConsumable(obj,now,epoch)
            now = double(now);
            if now < obj.AvailableAt
                error("sixgr:integration:FutureEvidenceConsumed", ...
                    "Event %s is unavailable until sample %.0f.", ...
                    obj.EventID,obj.AvailableAt);
            end
            if now > obj.ExpiryAt
                error("sixgr:integration:StaleEvidenceConsumed", ...
                    "Event %s expired at sample %.0f.", ...
                    obj.EventID,obj.ExpiryAt);
            end
            if double(epoch) ~= obj.ConfigurationEpoch
                error("sixgr:integration:StaleEvidenceConsumed", ...
                    "Event %s belongs to a different configuration epoch.", ...
                    obj.EventID);
            end
        end
    end
end
