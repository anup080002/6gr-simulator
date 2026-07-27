classdef RLCAMEntity < handle
    %RLCAMENTITY Bounded exact-header AM entity with segmentation/state.
    properties (SetAccess = private)
        Identity sixgr.l2.rlc18.RLCBearerIdentity
        SNBits (1,1) double
        PollPDU (1,1) double
        PollByte (1,1) double
        MaxRetxThreshold (1,1) double
        State sixgr.l2.rlc18.RLCEntityState
        PollCount (1,1) double=0
        TransmittedBytes (1,1) double=0
        RetransmissionCount (1,1) double=0
    end
    properties (Access=private)
        Queue cell={}
        Segment struct=struct("Active",false,"Bytes",uint8([]), ...
            "Offset",0,"SN",0)
        Delivered cell={}
        RxSegments
    end
    methods
        function obj=RLCAMEntity(config)
            required=["UEID","BearerID","Direction","ConfigurationEpoch", ...
                "SNBits"];
            if ~all(isfield(config,required))
                error("sixgr:rrc:ASN1ConstraintViolation", ...
                    "RLC AM configuration is incomplete.");
            end
            obj.Identity=sixgr.l2.rlc18.RLCBearerIdentity( ...
                string(config.UEID),string(config.BearerID), ...
                string(config.Direction),double(config.ConfigurationEpoch));
            obj.SNBits=double(config.SNBits);
            obj.PollPDU=double(localField(config,"PollPDU",16));
            obj.PollByte=double(localField(config,"PollByte",65536));
            obj.MaxRetxThreshold=double(localField(config,"MaxRetxThreshold",8));
            if ~ismember(obj.SNBits,[12 18]) || obj.PollPDU<1 || ...
                    obj.PollByte<1 || obj.MaxRetxThreshold<1
                error("sixgr:rlc:InvalidSNLength", ...
                    "Invalid strict RLC AM configuration.");
            end
            obj.State=sixgr.l2.rlc18.RLCEntityState( ...
                obj.Identity.EntityID,"AM",obj.SNBits);
            obj.State.activate();
            obj.RxSegments=containers.Map('KeyType','double','ValueType','any');
        end
        function addSDU(obj,bytes)
            bytes=uint8(bytes(:).');
            if isempty(bytes)
                error("sixgr:rlc:MalformedPDU","RLC SDU cannot be empty.");
            end
            obj.Queue{end+1}=bytes;
        end
        function pdus=buildPDUs(obj,availableBytes)
            availableBytes=floor(double(availableBytes));
            if availableBytes<3
                pdus={}; return;
            end
            if ~obj.Segment.Active
                if isempty(obj.Queue),pdus={};return;end
                obj.Segment=struct("Active",true,"Bytes",obj.Queue{1}, ...
                    "Offset",0,"SN",obj.State.allocateSN());
                obj.Queue(1)=[];
            end
            baseHeader=2+double(obj.SNBits==18);
            remaining=numel(obj.Segment.Bytes)-obj.Segment.Offset;
            if obj.Segment.Offset==0 && remaining<=availableBytes-baseHeader
                si=0; header=sixgr.l2.rlc18.RLCHeaderCodec.encodeAM( ...
                    obj.SNBits,1,obj.shouldPoll(remaining),si, ...
                    obj.Segment.SN,[]);
                take=remaining;
            else
                headerBytes=baseHeader+double(obj.Segment.Offset>0)*2;
                take=min(remaining,availableBytes-headerBytes);
                if take<=0,pdus={};return;end
                if obj.Segment.Offset==0,si=1;so=[];
                elseif take==remaining,si=2;so=obj.Segment.Offset;
                else,si=3;so=obj.Segment.Offset;end
                header=sixgr.l2.rlc18.RLCHeaderCodec.encodeAM( ...
                    obj.SNBits,1,obj.shouldPoll(take),si, ...
                    obj.Segment.SN,so);
            end
            payload=obj.Segment.Bytes(obj.Segment.Offset+(1:take));
            pdus={uint8([header payload])};
            obj.Segment.Offset=obj.Segment.Offset+take;
            obj.TransmittedBytes=obj.TransmittedBytes+take;
            if obj.Segment.Offset==numel(obj.Segment.Bytes)
                obj.Segment.Active=false;
            end
        end
        function receivePDU(obj,pdu)
            decoded=sixgr.l2.rlc18.RLCHeaderCodec.decodeAM(pdu,obj.SNBits);
            if decoded.SI==0
                obj.Delivered{end+1}=decoded.Payload; return;
            end
            sn=decoded.SN;
            if isKey(obj.RxSegments,sn),state=obj.RxSegments(sn);
            else,state=struct("Parts",{{}},"Offsets",[],"Last",NaN);end
            offset=0;
            if ~isempty(decoded.SO),offset=decoded.SO;end
            if ismember(offset,state.Offsets),return;end
            state.Parts{end+1}=decoded.Payload;
            state.Offsets(end+1)=offset;
            if decoded.SI==2,state.Last=offset+numel(decoded.Payload);end
            obj.RxSegments(sn)=state;
            if any(state.Offsets==0) && isfinite(state.Last)
                [offsets,order]=sort(state.Offsets);
                cursor=0; assembled=uint8([]);
                for index=order
                    if state.Offsets(index)~=cursor,return;end
                    assembled=[assembled state.Parts{index}]; %#ok<AGROW>
                    cursor=cursor+numel(state.Parts{index});
                end
                if cursor==state.Last
                    obj.Delivered{end+1}=assembled;
                    remove(obj.RxSegments,sn);
                end
            end
        end
        function sdus=pullSDUs(obj)
            sdus=obj.Delivered; obj.Delivered={};
        end
        function status=buildStatus(obj,ackSN,nackCount,segmentNACK,nackRange)
            status=sixgr.l2.rlc18.RLCStatusCodec.encode(obj.SNBits, ...
                ackSN,nackCount,segmentNACK,nackRange);
        end
        function release(obj),obj.State.release();obj.Queue={};obj.Delivered={};end
    end
    methods (Access=private)
        function poll=shouldPoll(obj,newBytes)
            obj.PollCount=obj.PollCount+1;
            poll=mod(obj.PollCount,obj.PollPDU)==0 || ...
                obj.TransmittedBytes+newBytes>=obj.PollByte;
        end
    end
end
function value=localField(config,name,defaultValue)
if isfield(config,name),value=config.(name);else,value=defaultValue;end
end
