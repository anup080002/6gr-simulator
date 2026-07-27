classdef PDCPBearerEntity < handle
    %PDCPBEARERENTITY Exact bounded PDCP data/security/count authority.
    properties (SetAccess=private)
        UEID (1,1) string
        BearerID (1,1) string
        Bearer (1,1) double
        Direction (1,1) double
        BearerType (1,1) string
        SNBits (1,1) double
        ConfigurationEpoch (1,1) double
        CipherAlgorithm (1,1) string
        IntegrityAlgorithm (1,1) string
        TX sixgr.l2.pdcp18.PDCPCountState
        RX sixgr.l2.pdcp18.PDCPReorderingState
        SecurityActive (1,1) logical=false
        DuplicateCount (1,1) double=0
    end
    properties (Access=private)
        CipherKey uint8
        IntegrityKey uint8
        Delivered cell={}
    end
    methods
        function obj=PDCPBearerEntity(config)
            required=["UEID","BearerID","Bearer","Direction","BearerType", ...
                "SNBits","ConfigurationEpoch","CipherAlgorithm", ...
                "IntegrityAlgorithm"];
            if ~all(isfield(config,required))
                error("sixgr:rrc:ASN1ConstraintViolation", ...
                    "PDCP bearer configuration is incomplete.");
            end
            obj.UEID=string(config.UEID);obj.BearerID=string(config.BearerID);
            obj.Bearer=double(config.Bearer);obj.Direction=double(config.Direction);
            obj.BearerType=upper(string(config.BearerType));
            obj.SNBits=double(config.SNBits);
            obj.ConfigurationEpoch=double(config.ConfigurationEpoch);
            obj.CipherAlgorithm=upper(string(config.CipherAlgorithm));
            obj.IntegrityAlgorithm=upper(string(config.IntegrityAlgorithm));
            if ~ismember(obj.CipherAlgorithm,["NEA0","128-NEA2"]) || ...
                    ~ismember(obj.IntegrityAlgorithm,["NIA0","128-NIA2"])
                error("sixgr:protocol:UnsupportedCapability", ...
                    "Unsupported strict PDCP security algorithm.");
            end
            obj.TX=sixgr.l2.pdcp18.PDCPCountState(obj.SNBits,0,0);
            obj.RX=sixgr.l2.pdcp18.PDCPReorderingState(obj.SNBits,0);
            obj.CipherKey=uint8(localField(config,"CipherKey",zeros(1,16)));
            obj.IntegrityKey=uint8(localField(config,"IntegrityKey",zeros(1,16)));
            if numel(obj.CipherKey)~=16 || numel(obj.IntegrityKey)~=16
                error("sixgr:pdcp:SecurityContextMissing", ...
                    "PDCP security keys must be 128 bits.");
            end
        end
        function activateSecurity(obj)
            obj.SecurityActive=true;
        end
        function pdu=transmit(obj,sdu)
            sdu=uint8(sdu(:).');
            count=double(obj.TX.current());sn=double(obj.TX.SN);
            header=sixgr.l2.pdcp18.PDCPHeaderCodec.encode( ...
                obj.BearerType,obj.SNBits,sn);
            payload=sdu;
            if obj.SecurityActive && obj.CipherAlgorithm=="128-NEA2"
                payload=sixgr.l2.pdcp18.PDCPSecurity128.nea2( ...
                    obj.CipherKey,count,obj.Bearer,obj.Direction, ...
                    payload,8*numel(payload));
            end
            macI=uint8([]);
            if obj.SecurityActive && obj.IntegrityAlgorithm=="128-NIA2"
                macI=sixgr.l2.pdcp18.PDCPSecurity128.nia2( ...
                    obj.IntegrityKey,count,obj.Bearer,obj.Direction, ...
                    [header payload],8*numel([header payload]));
            end
            pdu=uint8([header payload macI]);
            obj.TX.advance();
        end
        function delivered=receive(obj,pdu)
            decoded=sixgr.l2.pdcp18.PDCPHeaderCodec.decode( ...
                obj.BearerType,obj.SNBits,pdu);
            body=decoded.Payload;
            count=decoded.SN;
            if obj.SecurityActive && obj.IntegrityAlgorithm=="128-NIA2"
                if numel(body)<4
                    error("sixgr:pdcp:IntegrityFailure", ...
                        "PDCP PDU has no MAC-I.");
                end
                payload=body(1:end-4);received=body(end-3:end);
                headerBytes=pdu(1:decoded.HeaderBytes);
                sixgr.l2.pdcp18.PDCPSecurity128.verifyNIA2( ...
                    obj.IntegrityKey,count,obj.Bearer,obj.Direction, ...
                    [headerBytes payload],8*numel([headerBytes payload]), ...
                    received);
            else
                payload=body;
            end
            if obj.SecurityActive && obj.CipherAlgorithm=="128-NEA2"
                payload=sixgr.l2.pdcp18.PDCPSecurity128.nea2( ...
                    obj.CipherKey,count,obj.Bearer,obj.Direction, ...
                    payload,8*numel(payload));
            end
            ready=obj.RX.receive(decoded.SN);
            if isempty(ready)
                obj.DuplicateCount=obj.RX.DuplicateCount;
                delivered={};return;
            end
            % The bounded entity accepts in-order execution. Out-of-order
            % payload buffering is explicitly outside this enabled tuple.
            if numel(ready)~=1 || ready(1)~=decoded.SN
                error("sixgr:protocol:UnsupportedCapability", ...
                    "Out-of-order PDCP payload buffering is not enabled.");
            end
            obj.Delivered{end+1}=payload;
            delivered={payload};
        end
        function sdus=pullSDUs(obj),sdus=obj.Delivered;obj.Delivered={};end
    end
end
function value=localField(config,name,defaultValue)
if isfield(config,name),value=config.(name);else,value=defaultValue;end
end
