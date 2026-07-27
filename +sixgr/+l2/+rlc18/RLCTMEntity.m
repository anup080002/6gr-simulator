classdef RLCTMEntity < handle
    %RLCTMENTITY Transparent RLC entity for SRB0.
    properties (SetAccess=private)
        Identity sixgr.l2.rlc18.RLCBearerIdentity
    end
    properties (Access=private)
        Queue cell={}
        Delivered cell={}
    end
    methods
        function obj=RLCTMEntity(config)
            obj.Identity=sixgr.l2.rlc18.RLCBearerIdentity( ...
                string(config.UEID),string(config.BearerID), ...
                string(config.Direction),double(config.ConfigurationEpoch));
            if double(config.SNBits)~=0
                error("sixgr:rlc:InvalidSNLength","RLC TM has no SN.");
            end
        end
        function addSDU(obj,bytes),obj.Queue{end+1}=uint8(bytes(:).');end
        function pdus=buildPDUs(obj,availableBytes)
            if isempty(obj.Queue) || numel(obj.Queue{1})>availableBytes
                pdus={};return;
            end
            pdus={obj.Queue{1}};obj.Queue(1)=[];
        end
        function receivePDU(obj,pdu),obj.Delivered{end+1}=uint8(pdu(:).');end
        function sdus=pullSDUs(obj),sdus=obj.Delivered;obj.Delivered={};end
        function release(obj),obj.Queue={};obj.Delivered={};end
    end
end
