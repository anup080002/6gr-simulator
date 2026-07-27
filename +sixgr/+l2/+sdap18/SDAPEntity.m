classdef SDAPEntity < handle
    %SDAPENTITY Directional header and explicit QFI/DRB mapping authority.
    properties (SetAccess=private)
        UEID (1,1) string
        Direction (1,1) string
        Mapping sixgr.l2.sdap18.SDAPMappingState
        ConfigurationEpoch (1,1) double
    end
    properties (Access=private)
        Delivered cell={}
    end
    methods
        function obj=SDAPEntity(config)
            required=["UEID","Direction","PduSessionID", ...
                "DefaultDRBID","ConfigurationEpoch"];
            if ~all(isfield(config,required))
                error("sixgr:rrc:ASN1ConstraintViolation", ...
                    "SDAP entity configuration is incomplete.");
            end
            obj.UEID=string(config.UEID);
            obj.Direction=upper(string(config.Direction));
            obj.ConfigurationEpoch=double(config.ConfigurationEpoch);
            obj.Mapping=sixgr.l2.sdap18.SDAPMappingState( ...
                double(config.PduSessionID),double(config.DefaultDRBID));
            if isfield(config,"Mappings")
                mappings=config.Mappings;
                for index=1:numel(mappings)
                    obj.Mapping.configure(double(mappings(index).QFI), ...
                        double(mappings(index).DRBID), ...
                        obj.ConfigurationEpoch);
                end
            end
        end
        function [pdu,drbID]=transmit(obj,qfi,sdu,options)
            arguments
                obj
                qfi (1,1) double
                sdu (1,:) uint8
                options.RDI (1,1) double=0
                options.RQI (1,1) double=0
            end
            drbID=obj.Mapping.resolve(qfi);
            header=sixgr.l2.sdap18.SDAPHeaderCodec.encode( ...
                obj.Direction,"DATA",qfi,options.RDI,options.RQI);
            pdu=uint8([header sdu]);
        end
        function sdu=receive(obj,pdu)
            decoded=sixgr.l2.sdap18.SDAPHeaderCodec.decode( ...
                obj.Direction,"DATA",pdu);
            obj.Mapping.resolve(decoded.QFI);
            if obj.Direction=="DL" && decoded.RQI==1
                obj.Mapping.applyReflective(decoded.QFI, ...
                    obj.Mapping.resolve(decoded.QFI), ...
                    obj.ConfigurationEpoch);
            end
            sdu=decoded.Payload;
            obj.Delivered{end+1}=sdu;
        end
        function marker=endMarker(obj,qfi,newDRBID,newEpoch)
            if obj.Direction~="UL"
                error("sixgr:sdap:MalformedPDU", ...
                    "SDAP end marker is enabled on UL only.");
            end
            marker=sixgr.l2.sdap18.SDAPHeaderCodec.encode( ...
                "UL","END_MARKER",qfi,[],[]);
            obj.Mapping.configure(qfi,newDRBID,newEpoch);
            obj.ConfigurationEpoch=newEpoch;
        end
        function sdus=pullSDUs(obj),sdus=obj.Delivered;obj.Delivered={};end
    end
end
