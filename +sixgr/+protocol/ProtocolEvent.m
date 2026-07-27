classdef ProtocolEvent
    %PROTOCOLEVENT Immutable cross-layer protocol event.

    properties (SetAccess = immutable)
        EventSequence (1,1) double
        AbsoluteTime (1,1) double
        UEID (1,1) string
        BearerID (1,1) string
        Layer (1,1) string
        EventType (1,1) string
        SourceEventID (1,1) string
        ConfigurationEpoch (1,1) double
        PayloadSHA256 (1,1) string
        EventID (1,1) string
    end

    methods
        function obj = ProtocolEvent(sequence, time, layer, type, options)
            arguments
                sequence (1,1) double {mustBeInteger,mustBePositive}
                time (1,1) double {mustBeFinite,mustBeNonnegative}
                layer (1,1) string
                type (1,1) string
                options.UEID (1,1) string = ""
                options.BearerID (1,1) string = ""
                options.SourceEventID (1,1) string = ""
                options.ConfigurationEpoch (1,1) double = 0
                options.Payload = struct()
            end
            obj.EventSequence = sequence;
            obj.AbsoluteTime = time;
            obj.UEID = options.UEID;
            obj.BearerID = options.BearerID;
            obj.Layer = layer;
            obj.EventType = type;
            obj.SourceEventID = options.SourceEventID;
            obj.ConfigurationEpoch = options.ConfigurationEpoch;
            encoded = jsonencode(options.Payload);
            obj.PayloadSHA256 = sixgr.protocol.ProtocolHash.bytes(encoded);
            identity = join([string(sequence), string(time), layer, type, ...
                obj.UEID, obj.BearerID, obj.SourceEventID, ...
                string(obj.ConfigurationEpoch), obj.PayloadSHA256], "|");
            obj.EventID = sixgr.protocol.ProtocolHash.bytes(identity);
        end
    end
end
