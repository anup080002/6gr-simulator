classdef ProtocolRuntime < handle
    %PROTOCOLRUNTIME Bounded connected-mode SDAP/PDCP/RLC execution path.
    %
    % This runtime deliberately owns protocol identities and never infers
    % grant-level truth.  The returned RLC PDU can be handed to the MAC/PHY
    % layer by a caller-provided callback.

    properties (SetAccess = private)
        UEID (1,1) string
        BearerID (1,1) string
        QFI (1,1) double
        PDCPSNBits (1,1) double
        RLCSNBits (1,1) double
        ConfigurationEpoch (1,1) double
        Events sixgr.protocol.ProtocolEventStore
        Lineage sixgr.protocol.ProtocolLineageLedger
        PacketsTransmitted (1,1) double = 0
        PacketsDelivered (1,1) double = 0
        DuplicateDiscards (1,1) double = 0
    end

    properties (Access = private)
        SDAPEntity sixgr.l2.sdap18.SDAPEntity
        PDCPEntity sixgr.l2.pdcp18.PDCPBearerEntity
        RLCEntity sixgr.l2.rlc18.RLCAMEntity
        Delivered containers.Map
        MACSubmit
    end

    methods
        function obj = ProtocolRuntime(config, options)
            arguments
                config (1,1) struct
                options.MACSubmit = []
            end
            required = ["UEID","BearerID","QFI","PDCPSNBits", ...
                "RLCSNBits","ConfigurationEpoch"];
            if ~all(isfield(config, required))
                error("sixgr:protocol:UnsupportedCapability", ...
                    "Protocol runtime configuration is incomplete.");
            end
            obj.UEID = string(config.UEID);
            obj.BearerID = string(config.BearerID);
            obj.QFI = double(config.QFI);
            obj.PDCPSNBits = double(config.PDCPSNBits);
            obj.RLCSNBits = double(config.RLCSNBits);
            obj.ConfigurationEpoch = double(config.ConfigurationEpoch);
            mapping = struct("QFI",obj.QFI,"DRBID",1);
            obj.SDAPEntity = sixgr.l2.sdap18.SDAPEntity(struct( ...
                "UEID",obj.UEID,"Direction","UL","PduSessionID",1, ...
                "DefaultDRBID",1,"ConfigurationEpoch", ...
                obj.ConfigurationEpoch,"Mappings",mapping));
            obj.PDCPEntity = sixgr.l2.pdcp18.PDCPBearerEntity(struct( ...
                "UEID",obj.UEID,"BearerID",obj.BearerID,"Bearer",1, ...
                "Direction",0,"BearerType","DRB","SNBits", ...
                obj.PDCPSNBits,"ConfigurationEpoch", ...
                obj.ConfigurationEpoch,"CipherAlgorithm", ...
                string(localField(config,"CipherAlgorithm","NEA0")), ...
                "IntegrityAlgorithm", ...
                string(localField(config,"IntegrityAlgorithm","NIA0")), ...
                "CipherKey",uint8(localField(config,"CipherKey",zeros(1,16))), ...
                "IntegrityKey",uint8(localField(config, ...
                "IntegrityKey",zeros(1,16)))));
            if logical(localField(config,"SecurityActive",false))
                obj.PDCPEntity.activateSecurity();
            end
            obj.RLCEntity = sixgr.l2.rlc18.RLCAMEntity(struct( ...
                "UEID",obj.UEID,"BearerID",obj.BearerID, ...
                "Direction","UL","ConfigurationEpoch", ...
                obj.ConfigurationEpoch,"SNBits",obj.RLCSNBits, ...
                "PollPDU",double(localField(config,"PollPDU",16)), ...
                "PollByte",double(localField(config,"PollByte",65536)), ...
                "MaxRetxThreshold",double(localField(config, ...
                "MaxRetxThreshold",8))));
            obj.Events = sixgr.protocol.ProtocolEventStore();
            obj.Lineage = sixgr.protocol.ProtocolLineageLedger();
            obj.Delivered = containers.Map('KeyType','char','ValueType','logical');
            obj.MACSubmit = options.MACSubmit;
        end

        function pdu = transmit(obj, packetID, payload, time)
            arguments
                obj
                packetID (1,1) string
                payload (1,:) uint8
                time (1,1) double {mustBeNonnegative}
            end
            packetHash = sixgr.protocol.ProtocolHash.bytes(payload);
            packet = struct("PacketID",packetID, ...
                "PacketBytes",numel(payload),"PayloadSHA256",packetHash);
            obj.Lineage.addPacket(packet);

            [sdapPDU,~] = obj.SDAPEntity.transmit(obj.QFI,payload);
            sdapHeader = sdapPDU(1);
            count = double(obj.PDCPEntity.TX.current());
            pdcpSN = double(obj.PDCPEntity.TX.SN);
            pdcpPDU = obj.PDCPEntity.transmit(sdapPDU);
            pdcpHeaderBytes = 2+double(obj.PDCPSNBits==18);
            pdcpHeader = pdcpPDU(1:pdcpHeaderBytes);
            rlcSN = obj.RLCEntity.State.TX_NEXT;
            obj.RLCEntity.addSDU(pdcpPDU);
            encoded = obj.RLCEntity.buildPDUs(inf);
            if numel(encoded)~=1
                error("sixgr:rlc:MalformedPDU", ...
                    "Connected-mode packet did not produce one RLC PDU.");
            end
            rlcPDU = encoded{1};
            rlcHeaderBytes = 2+double(obj.RLCSNBits==18);
            rlcHeader = rlcPDU(1:rlcHeaderBytes);

            sdapID = "SDAP-" + packetID;
            pdcpID = "PDCP-" + string(count);
            rlcID = "RLC-" + string(rlcSN);
            macID = "MAC-" + packetID;
            tbID = "TB-" + packetID;
            obj.Lineage.addNode(sdapID,packetID,"SDAP",numel(sdapPDU));
            obj.Lineage.addNode(pdcpID,packetID,"PDCP",numel(pdcpPDU));
            obj.Lineage.addNode(rlcID,packetID,"RLC",numel(rlcPDU));
            macHeaderBytes=2+double(numel(rlcPDU)>255);
            mac=sixgr.l2.mac.MACPDUAssembler.assemble("UL", ...
                struct("LCID",4,"Payload",rlcPDU,"OwnerID",rlcID), ...
                numel(rlcPDU)+macHeaderBytes);
            obj.Lineage.addNode(macID,packetID,"MAC",numel(mac.Bytes));
            obj.Lineage.addNode(tbID,packetID,"HARQ_TB",numel(mac.Bytes));
            event = obj.Events.append(time,"SDAP","SDU_ACCEPTED", ...
                "UEID",obj.UEID,"BearerID",obj.BearerID, ...
                "ConfigurationEpoch",obj.ConfigurationEpoch, ...
                "Payload",struct("PacketID",packetID,"QFI",obj.QFI));
            event = obj.Events.append(time,"PDCP","PDU_ENCODED", ...
                "UEID",obj.UEID,"BearerID",obj.BearerID, ...
                "SourceEventID",event.EventID, ...
                "ConfigurationEpoch",obj.ConfigurationEpoch, ...
                "Payload",struct("COUNT",count,"SN",pdcpSN));
            obj.Events.append(time,"RLC","PDU_ENCODED", ...
                "UEID",obj.UEID,"BearerID",obj.BearerID, ...
                "SourceEventID",event.EventID, ...
                "ConfigurationEpoch",obj.ConfigurationEpoch, ...
                "Payload",struct("SN",rlcSN,"Bytes",numel(rlcPDU)));
            obj.Events.append(time,"MAC","TB_ASSEMBLED", ...
                "UEID",obj.UEID,"BearerID",obj.BearerID, ...
                "ConfigurationEpoch",obj.ConfigurationEpoch, ...
                "Payload",struct("TBID",tbID,"HARQAttempt",1, ...
                "Bytes",numel(mac.Bytes)));

            pdu = struct("PacketID",packetID,"PacketSHA256",packetHash, ...
                "SDAPHeader",sdapHeader,"PDCPHeader",pdcpHeader, ...
                "RLCHeader",rlcHeader,"PDCPCount",count,"RLCSN",rlcSN, ...
                "Bytes",rlcPDU,"PayloadBytes",numel(payload), ...
                "EncodedSHA256",sixgr.protocol.ProtocolHash.bytes(rlcPDU), ...
                "MACBytes",mac.Bytes,"MACSHA256",mac.SHA256, ...
                "TBID",tbID,"HARQAttempt",1);
            obj.PacketsTransmitted = obj.PacketsTransmitted + 1;
            if ~isempty(obj.MACSubmit)
                obj.MACSubmit(pdu);
            end
        end

        function delivered = receive(obj, pdu, time)
            arguments
                obj
                pdu (1,1) struct
                time (1,1) double {mustBeNonnegative}
            end
            if sixgr.protocol.ProtocolHash.bytes(pdu.Bytes) ~= ...
                    string(pdu.EncodedSHA256)
                error("sixgr:protocol:LineageViolation", ...
                    "Received RLC PDU digest does not match its identity.");
            end
            if sixgr.l2.mac.MACHash.of(pdu.MACBytes) ~= ...
                    string(pdu.MACSHA256)
                error("sixgr:protocol:LineageViolation", ...
                    "Received MAC PDU digest does not match its TB identity.");
            end
            demux=sixgr.l2.mac.MACPDUDemultiplexer.decode("UL",pdu.MACBytes);
            if numel(demux.SubPDUs)~=1 || demux.SubPDUs(1).LCID~=4 || ...
                    ~isequal(demux.SubPDUs(1).Payload,pdu.Bytes)
                error("sixgr:protocol:LineageViolation", ...
                    "MAC demultiplexing changed RLC PDU ownership.");
            end
            obj.RLCEntity.receivePDU(demux.SubPDUs(1).Payload);
            pdcpPDUs = obj.RLCEntity.pullSDUs();
            if numel(pdcpPDUs)~=1
                error("sixgr:rlc:MalformedPDU", ...
                    "RLC receiver did not reassemble exactly one PDCP PDU.");
            end
            sdapPDUs = obj.PDCPEntity.receive(pdcpPDUs{1});
            key = char(string(pdu.PacketID));
            if isempty(sdapPDUs) || isKey(obj.Delivered,key)
                obj.DuplicateDiscards = obj.DuplicateDiscards + 1;
                delivered = false;
                obj.Events.append(time,"PDCP","DUPLICATE_DISCARDED", ...
                    "UEID",obj.UEID,"BearerID",obj.BearerID, ...
                    "ConfigurationEpoch",obj.ConfigurationEpoch, ...
                    "Payload",struct("PacketID",pdu.PacketID));
                return;
            end
            payload = obj.SDAPEntity.receive(sdapPDUs{1});
            if sixgr.protocol.ProtocolHash.bytes(payload) ~= ...
                    string(pdu.PacketSHA256)
                error("sixgr:protocol:LineageViolation", ...
                    "Delivered traffic payload does not match packet identity.");
            end
            obj.Delivered(key) = true;
            delivered = obj.Lineage.deliver(string(pdu.PacketID));
            obj.PacketsDelivered = obj.PacketsDelivered + double(delivered);
            obj.Events.append(time,"PDCP","SDU_DELIVERED", ...
                "UEID",obj.UEID,"BearerID",obj.BearerID, ...
                "ConfigurationEpoch",obj.ConfigurationEpoch, ...
                "Payload",struct("PacketID",pdu.PacketID, ...
                "PayloadBytes",pdu.PayloadBytes));
        end

        function value = conservation(obj)
            value = obj.Lineage.conservation();
        end
    end
end

function value=localField(config,name,defaultValue)
if isfield(config,name)
    value=config.(name);
else
    value=defaultValue;
end
end
