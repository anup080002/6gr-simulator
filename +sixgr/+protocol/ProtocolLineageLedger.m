classdef ProtocolLineageLedger < handle
    %PROTOCOLLINEAGELEDGER First-delivery lineage and byte conservation.

    properties (Access = private)
        Nodes
        PacketBytes
        DeliveryState
    end

    methods
        function obj = ProtocolLineageLedger()
            obj.Nodes = containers.Map('KeyType','char','ValueType','any');
            obj.PacketBytes = containers.Map('KeyType','char','ValueType','double');
            obj.DeliveryState = containers.Map('KeyType','char','ValueType','char');
        end

        function addPacket(obj, packet)
            id = char(string(packet.PacketID));
            if isKey(obj.PacketBytes, id)
                error("sixgr:protocol:LineageViolation", ...
                    "Duplicate PacketID %s.", string(id));
            end
            obj.PacketBytes(id) = double(packet.PacketBytes);
            obj.DeliveryState(id) = 'QUEUED';
            obj.Nodes(id) = struct("Layer","TRAFFIC","ParentID","", ...
                "PayloadBytes",double(packet.PacketBytes), ...
                "Hash",string(packet.PayloadSHA256));
        end

        function hash = addNode(obj, nodeID, parentID, layer, payloadBytes)
            nodeID = char(string(nodeID));
            parentID = char(string(parentID));
            if isKey(obj.Nodes, nodeID) || ~isKey(obj.Nodes, parentID)
                error("sixgr:protocol:LineageViolation", ...
                    "Protocol lineage node is duplicate or orphaned.");
            end
            parent = obj.Nodes(parentID);
            hash = sixgr.protocol.ProtocolHash.bytes(join([ ...
                string(parent.Hash), string(nodeID), string(layer), ...
                string(payloadBytes)], "|"));
            obj.Nodes(nodeID) = struct("Layer",string(layer), ...
                "ParentID",string(parentID),"PayloadBytes",double(payloadBytes), ...
                "Hash",hash);
        end

        function validateDelivery(obj,packetID,payload)
            key=char(string(packetID));
            assert(isKey(obj.DeliveryState,key)&&isKey(obj.Nodes,key)&&isKey(obj.PacketBytes,key), ...
                'sixgr:protocol:LineageViolation','Original completion refers to an unknown packet.');
            original=obj.Nodes(key);
            assert(strcmp(obj.DeliveryState(key),'QUEUED')&&obj.PacketBytes(key)==numel(payload)&& ...
                original.Hash==sixgr.protocol.ProtocolHash.bytes(payload), ...
                'sixgr:protocol:LineageViolation','Original queued packet bytes or terminal state differ.');
        end

        function first = deliver(obj, packetID)
            key = char(string(packetID));
            if ~isKey(obj.DeliveryState, key)
                error("sixgr:protocol:LineageViolation", ...
                    "Delivery refers to an unknown packet.");
            end
            first = ~strcmp(obj.DeliveryState(key), 'DELIVERED');
            assert(~strcmp(obj.DeliveryState(key),'DROPPED'), ...
                'sixgr:protocol:ConservationFailure','A terminally discarded unsent packet cannot subsequently be delivered.');
            if first
                obj.DeliveryState(key) = 'DELIVERED';
            end
        end

        function drop(obj, packetID)
            key = char(string(packetID));
            if ~isKey(obj.DeliveryState, key)
                error("sixgr:protocol:LineageViolation", ...
                    "Drop refers to an unknown packet.");
            end
            if strcmp(obj.DeliveryState(key), 'DELIVERED')
                error("sixgr:protocol:ConservationFailure", ...
                    "A delivered packet cannot subsequently be dropped.");
            end
            obj.DeliveryState(key) = 'DROPPED';
        end

        function result = conservation(obj)
            ids = keys(obj.PacketBytes);
            arrived = 0; queued = 0; delivered = 0; dropped = 0;
            for index = 1:numel(ids)
                bytes = obj.PacketBytes(ids{index});
                arrived = arrived + bytes;
                switch obj.DeliveryState(ids{index})
                    case 'QUEUED'
                        queued = queued + bytes;
                    case 'DELIVERED'
                        delivered = delivered + bytes;
                    case 'DROPPED'
                        dropped = dropped + bytes;
                end
            end
            errorBytes = arrived - queued - delivered - dropped;
            result = struct("ArrivedBytes",arrived,"QueuedBytes",queued, ...
                "InFlightBytes",0,"DeliveredBytes",delivered, ...
                "DroppedBytes",dropped,"UnownedBytes",0, ...
                "DuplicateDeliveredBytes",0, ...
                "EquationErrorBytes",errorBytes);
            if errorBytes ~= 0
                error("sixgr:protocol:ConservationFailure", ...
                    "Protocol byte conservation error is %d bytes.", errorBytes);
            end
        end
    end
end
