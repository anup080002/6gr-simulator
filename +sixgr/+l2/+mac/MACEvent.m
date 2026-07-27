classdef MACEvent
    %MACEVENT Immutable event appended to the canonical MAC event store.

    properties (SetAccess=immutable)
        EventID (1,1) string
        EventType (1,1) string
        UEID (1,1) double
        ServingCell (1,1) double
        Direction (1,1) string
        AbsoluteSlot (1,1) double
        AbsoluteSymbol (1,1) double
        SourceEventID (1,1) string
        ConfigurationEpoch (1,1) double
        Payload (1,1) struct
        PayloadSHA256 (1,1) string
    end

    methods
        function obj = MACEvent(eventType, varargin)
            p = inputParser;
            addRequired(p, "eventType", @(x) ischar(x) || isstring(x));
            addParameter(p, "EventID", "", @(x) ischar(x) || isstring(x));
            addParameter(p, "UEID", 0, @localNonnegativeInteger);
            addParameter(p, "ServingCell", 0, @localNonnegativeInteger);
            addParameter(p, "Direction", "NA", @(x) ischar(x) || isstring(x));
            addParameter(p, "AbsoluteSlot", 0, @localNonnegativeInteger);
            addParameter(p, "AbsoluteSymbol", 0, @localNonnegativeInteger);
            addParameter(p, "SourceEventID", "", @(x) ischar(x) || isstring(x));
            addParameter(p, "ConfigurationEpoch", 0, @localNonnegativeInteger);
            addParameter(p, "Payload", struct(), @(x) isstruct(x) && isscalar(x));
            parse(p, eventType, varargin{:});
            r = p.Results;
            type = upper(string(r.eventType));
            if ~sixgr.l2.mac.MACEventType.isValid(type)
                error("sixgr:mac:UnknownEventType", ...
                    "Unknown MAC event type %s.", type);
            end
            direction = upper(string(r.Direction));
            if ~ismember(direction, ["DL","UL","BOTH","NA"])
                error("sixgr:mac:InvalidDirection", ...
                    "Direction must be DL, UL, BOTH, or NA.");
            end
            obj.EventType = type;
            obj.UEID = double(r.UEID);
            obj.ServingCell = double(r.ServingCell);
            obj.Direction = direction;
            obj.AbsoluteSlot = double(r.AbsoluteSlot);
            obj.AbsoluteSymbol = double(r.AbsoluteSymbol);
            obj.SourceEventID = string(r.SourceEventID);
            obj.ConfigurationEpoch = double(r.ConfigurationEpoch);
            obj.Payload = r.Payload;
            obj.PayloadSHA256 = sixgr.l2.mac.MACHash.of(r.Payload);
            eventID = string(r.EventID);
            if strlength(eventID) == 0
                identity = struct("Type",type,"UEID",obj.UEID, ...
                    "ServingCell",obj.ServingCell,"Direction",direction, ...
                    "AbsoluteSlot",obj.AbsoluteSlot, ...
                    "AbsoluteSymbol",obj.AbsoluteSymbol, ...
                    "SourceEventID",obj.SourceEventID, ...
                    "ConfigurationEpoch",obj.ConfigurationEpoch, ...
                    "PayloadSHA256",obj.PayloadSHA256);
                eventID = sixgr.l2.mac.MACHash.of(identity);
            end
            obj.EventID = eventID;
        end
    end
end

function tf = localNonnegativeInteger(value)
tf = isnumeric(value) && isscalar(value) && isfinite(value) && ...
    value >= 0 && value == fix(value);
end
