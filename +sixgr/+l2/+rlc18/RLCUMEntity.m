classdef RLCUMEntity < handle
    %RLCUMENTITY Bounded exact-header UM entity with ordered reassembly.
    properties (SetAccess=private)
        Identity sixgr.l2.rlc18.RLCBearerIdentity
        SNBits (1,1) double
        State sixgr.l2.rlc18.RLCEntityState
    end
    properties (Access=private)
        Queue cell={}
        Delivered cell={}
    end
    methods
        function obj=RLCUMEntity(config)
            obj.Identity=sixgr.l2.rlc18.RLCBearerIdentity( ...
                string(config.UEID),string(config.BearerID), ...
                string(config.Direction),double(config.ConfigurationEpoch));
            obj.SNBits=double(config.SNBits);
            obj.State=sixgr.l2.rlc18.RLCEntityState( ...
                obj.Identity.EntityID,"UM",obj.SNBits);
            obj.State.activate();
        end
        function addSDU(obj,bytes),obj.Queue{end+1}=uint8(bytes(:).');end
        function pdus=buildPDUs(obj,availableBytes)
            if isempty(obj.Queue),pdus={};return;end
            bytes=obj.Queue{1};
            if numel(bytes)+1<=availableBytes
                header=sixgr.l2.rlc18.RLCHeaderCodec.encodeUM( ...
                    obj.SNBits,0,[],[]);
                obj.Queue(1)=[];pdus={uint8([header bytes])};
            else
                error("sixgr:protocol:UnsupportedCapability", ...
                    "Bounded UM entity requires a complete-SDU allocation.");
            end
        end
        function receivePDU(obj,pdu)
            decoded=sixgr.l2.rlc18.RLCHeaderCodec.decodeUM(pdu,obj.SNBits);
            if decoded.SI~=0
                error("sixgr:protocol:UnsupportedCapability", ...
                    "Bounded UM entity enables complete SDUs only.");
            end
            obj.Delivered{end+1}=decoded.Payload;
        end
        function sdus=pullSDUs(obj),sdus=obj.Delivered;obj.Delivered={};end
        function release(obj),obj.State.release();obj.Queue={};obj.Delivered={};end
    end
end
