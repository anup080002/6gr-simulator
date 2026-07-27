classdef TrafficSession < handle
    %TRAFFICSESSION Immutable packet/session generator for bounded profiles.

    properties (SetAccess = immutable)
        SessionID (1,1) string
        FlowID (1,1) string
        ProfileID (1,1) string
        PduSessionID (1,1) double
        QFI (1,1) double
        FiveQI (1,1) double
        PacketBytes (1,1) double
        DeadlineMs (1,1) double
        StreamIdentity (1,1) string
    end

    properties (Access = private)
        Stream sixgr.traffic18.NamedTrafficStream
        NextPacketIndex (1,1) double = 1
    end

    methods
        function obj = TrafficSession(config)
            arguments
                config struct
            end
            required = {'SessionID','FlowID','ProfileID','PduSessionID', ...
                'QFI','FiveQI','PacketBytes','DeadlineMs','MasterSeed'};
            if ~all(isfield(config, required))
                error("sixgr:traffic:InvalidTrafficProfile", ...
                    "Traffic session configuration is incomplete.");
            end
            profile = upper(string(config.ProfileID));
            supported = ["CBR","POISSON","BOUNDED_BURST", ...
                "XR_PDU_SET","MMTC_PERIODIC","TRACE_REPLAY"];
            if ~ismember(profile, supported)
                error("sixgr:traffic:InvalidTrafficProfile", ...
                    "Unsupported strict traffic profile %s.", profile);
            end
            if config.QFI < 0 || config.QFI > 63 || ...
                    config.PacketBytes <= 0 || config.DeadlineMs <= 0
                error("sixgr:traffic:InvalidTrafficProfile", ...
                    "Traffic QFI/size/deadline is invalid.");
            end
            obj.SessionID = string(config.SessionID);
            obj.FlowID = string(config.FlowID);
            obj.ProfileID = profile;
            obj.PduSessionID = double(config.PduSessionID);
            obj.QFI = double(config.QFI);
            obj.FiveQI = double(config.FiveQI);
            obj.PacketBytes = double(config.PacketBytes);
            obj.DeadlineMs = double(config.DeadlineMs);
            obj.StreamIdentity = "traffic." + obj.SessionID + "." + obj.FlowID;
            obj.Stream = sixgr.traffic18.NamedTrafficStream( ...
                double(config.MasterSeed), obj.StreamIdentity);
        end

        function packets = generate(obj, startMs, stopMs, options)
            arguments
                obj
                startMs (1,1) double
                stopMs (1,1) double
                options.PeriodMs (1,1) double = 10
                options.LambdaPPS (1,1) double = 100
                options.DutyCycle (1,1) double = 0.5
                options.PDUSetPackets (1,1) double = 4
                options.Trace table = table()
            end
            if stopMs <= startMs
                error("sixgr:traffic:InvalidTrafficProfile", ...
                    "Traffic stop time must exceed start time.");
            end
            switch obj.ProfileID
                case {"CBR","MMTC_PERIODIC","XR_PDU_SET"}
                    if options.PeriodMs <= 0
                        error("sixgr:traffic:InvalidTrafficProfile", ...
                            "Periodic traffic requires PeriodMs > 0.");
                    end
                    arrivals = startMs:options.PeriodMs:(stopMs-eps);
                case "POISSON"
                    if options.LambdaPPS <= 0
                        error("sixgr:traffic:InvalidTrafficProfile", ...
                            "Poisson traffic requires LambdaPPS > 0.");
                    end
                    arrivals = [];
                    now = startMs;
                    while true
                        u = max(realmin, obj.Stream.uniform(1,1));
                        now = now - log(u) * 1000 / options.LambdaPPS;
                        if now >= stopMs
                            break;
                        end
                        arrivals(end+1) = now; %#ok<AGROW>
                    end
                case "BOUNDED_BURST"
                    if options.DutyCycle <= 0 || options.DutyCycle > 1
                        error("sixgr:traffic:InvalidTrafficProfile", ...
                            "Burst duty cycle must be in (0,1].");
                    end
                    period = options.PeriodMs;
                    raw = startMs:period:(stopMs-eps);
                    arrivals = raw(mod(floor((raw-startMs)/period), ...
                        max(1,round(1/options.DutyCycle))) == 0);
                case "TRACE_REPLAY"
                    if isempty(options.Trace) || ...
                            ~all(ismember(["ArrivalTime_ms","PacketBytes"], ...
                            string(options.Trace.Properties.VariableNames)))
                        error("sixgr:traffic:InvalidTrafficProfile", ...
                            "Trace replay requires exact arrival and byte columns.");
                    end
                    arrivals = double(options.Trace.ArrivalTime_ms(:).');
                    arrivals = arrivals(arrivals >= startMs & arrivals < stopMs);
            end
            packets = repmat(obj.packetTemplate(), numel(arrivals), 1);
            for index = 1:numel(arrivals)
                pduSetID = "";
                if obj.ProfileID == "XR_PDU_SET"
                    setIndex = floor((index-1)/options.PDUSetPackets) + 1;
                    pduSetID = obj.SessionID + "-PDUSET-" + setIndex;
                end
                bytes = obj.PacketBytes;
                if obj.ProfileID == "TRACE_REPLAY"
                    source = find(double(options.Trace.ArrivalTime_ms) == ...
                        arrivals(index), 1, "first");
                    bytes = double(options.Trace.PacketBytes(source));
                end
                packetID = obj.SessionID + "-" + obj.FlowID + "-PKT-" + ...
                    obj.NextPacketIndex;
                payload = obj.Stream.integer([0 255], bytes, 1);
                packets(index) = struct( ...
                    "PacketID", packetID, "SessionID", obj.SessionID, ...
                    "FlowID", obj.FlowID, "ArrivalTime_ms", arrivals(index), ...
                    "PacketBytes", bytes, "PduSessionID", obj.PduSessionID, ...
                    "QFI", obj.QFI, "FiveQI", obj.FiveQI, ...
                    "Deadline_ms", arrivals(index) + obj.DeadlineMs, ...
                    "PDUSetID", pduSetID, ...
                    "RandomStream", obj.StreamIdentity, ...
                    "PayloadSHA256", sixgr.protocol.ProtocolHash.bytes( ...
                    uint8(payload)));
                obj.NextPacketIndex = obj.NextPacketIndex + 1;
            end
        end
    end

    methods (Access = private)
        function row = packetTemplate(~)
            row = struct("PacketID","","SessionID","","FlowID","", ...
                "ArrivalTime_ms",0,"PacketBytes",0,"PduSessionID",0, ...
                "QFI",0,"FiveQI",0,"Deadline_ms",0,"PDUSetID","", ...
                "RandomStream","","PayloadSHA256","");
        end
    end
end
