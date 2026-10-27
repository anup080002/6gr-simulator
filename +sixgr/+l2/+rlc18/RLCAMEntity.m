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
        ARQEnabled (1,1) logical=false
    end
    properties (Access=private)
        Queue cell={}
        Segment struct=struct("Active",false,"Bytes",uint8([]), ...
            "Offset",0,"SN",0)
        Delivered cell={}
        RxSegments
        RxCompleted
        RXNextCount (1,1) double=0
        TxRevision (1,1) double=0
        TxOwner (1,1) string
        Prepared
        PreparedStatusReceives
        PDUsSincePoll (1,1) double=0
        BytesSincePoll (1,1) double=0
        QueueCounts double=[]
        QueueIDs string=strings(1,0)
        SDURecords cell={}
        SDUAcknowledgements struct=struct([])
        NextSDUCount (1,1) double=0
        ARQ
        Receiver
        Clock struct=struct()
        LastSample (1,1) double=0
        MaxRetxNotifiedCounts double=[]
        UpperLayerIndications struct=struct([])
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
            obj.RxCompleted=containers.Map('KeyType','double','ValueType','logical');
            obj.TxOwner=string(java.util.UUID.randomUUID());
            obj.Prepared=containers.Map('KeyType','char','ValueType','any');
            obj.PreparedStatusReceives=containers.Map('KeyType','char','ValueType','any');
            obj.ARQEnabled=logical(localField(config,'ARQEnabled',false));
            if obj.ARQEnabled
                c=config.ARQConfig;
                c.BearerID=obj.Identity.EntityID;c.SNBits=obj.SNBits;c.InitialCount=0;
                c.MaxRetxThreshold=obj.MaxRetxThreshold;
                obj.Clock=c;
                obj.ARQ=sixgr.l2.rlc18.RLCAMARQState(c);
                obj.Receiver=sixgr.l2.rlc18.RLCAMReceiverState(c);
            end
        end
        function queueID=addSDU(obj,bytes)
            assert(obj.State.Lifecycle=="ACTIVE",'sixgr:rlc:WindowViolation','Released bearer cannot queue SDUs.');
            bytes=uint8(bytes(:).');
            if isempty(bytes)
                error("sixgr:rlc:MalformedPDU","RLC SDU cannot be empty.");
            end
            if obj.ARQEnabled,obj.ARQ=obj.ARQ.retainSDU(obj.NextSDUCount,bytes);end
            queueID=string(java.util.UUID.randomUUID());
            obj.SDURecords{end+1}=struct('QueueID',queueID,'FullCount',obj.NextSDUCount, ...
                'PayloadSHA256',sixgr.protocol.ProtocolHash.bytes(bytes),'PayloadBytes',numel(bytes), ...
                'HandedToLowerLayer',false,'Discarded',false,'Acknowledged',false);
            obj.Queue{end+1}=bytes;obj.QueueCounts(end+1)=obj.NextSDUCount;obj.QueueIDs(end+1)=queueID;
            obj.NextSDUCount=obj.NextSDUCount+1;
        end
        function receipt=discardUnsubmittedSDU(obj,queueID)
            assert(obj.State.Lifecycle=="ACTIVE",'sixgr:rlc:WindowViolation','Released bearer cannot discard SDUs.');
            assert(isstring(queueID)&&isscalar(queueID)&&strlength(queueID)>0, ...
                'sixgr:rlc:SDUIdentity','Original opaque queue identity required.');
            hit=find(cellfun(@(r)r.QueueID==queueID,obj.SDURecords));
            assert(isscalar(hit),'sixgr:rlc:SDUIdentity','Queue identity belongs to this original bearer.');
            record=obj.SDURecords{hit};
            receipt=struct('QueueID',queueID,'BearerID',obj.Identity.EntityID, ...
                'OriginalFullCount',record.FullCount,'PayloadSHA256',record.PayloadSHA256, ...
                'PayloadBytes',record.PayloadBytes,'Discarded',false,'Disposition',"", ...
                'RemappedQueueIDs',strings(0,1),'OldFullCounts',zeros(0,1),'NewFullCounts',zeros(0,1));
            if record.Discarded
                receipt.Disposition="already_discarded"; return;
            end
            if record.HandedToLowerLayer
                receipt.Disposition="retained_already_handed_to_lower_layer"; return;
            end
            later=find(cellfun(@(r)~r.Discarded && r.FullCount>record.FullCount,obj.SDURecords));
            if any(cellfun(@(r)r.HandedToLowerLayer,obj.SDURecords(later)))
                receipt.Disposition="retained_later_immutable_count"; return;
            end
            qi=find(obj.QueueIDs==queueID);
            assert(isscalar(qi) && obj.QueueCounts(qi)==record.FullCount && ...
                sixgr.protocol.ProtocolHash.bytes(obj.Queue{qi})==record.PayloadSHA256, ...
                'sixgr:rlc:SDUIdentity','Unsubmitted original queue bytes/count must match.');
            if obj.ARQEnabled
                protected=cellfun(@(r)r.FullCount,obj.SDURecords(cellfun(@(r)~r.Discarded&&r.HandedToLowerLayer,obj.SDURecords)));
                [next,remap]=obj.ARQ.discardUnsubmitted(record.FullCount,protected);
                assert(remap.Discarded,'sixgr:rlc:SDUDiscardConflict','ARQ rejected an unsubmitted original queue record.');
            end
            % No prepared/active/transmitted count can be altered above.
            obj.Queue(qi)=[]; obj.QueueCounts(qi)=[]; obj.QueueIDs(qi)=[];
            obj.QueueCounts(obj.QueueCounts>record.FullCount)=obj.QueueCounts(obj.QueueCounts>record.FullCount)-1;
            for k=later
                r=obj.SDURecords{k};
                receipt.RemappedQueueIDs(end+1,1)=r.QueueID;
                receipt.OldFullCounts(end+1,1)=r.FullCount;
                r.FullCount=r.FullCount-1;obj.SDURecords{k}=r;
                receipt.NewFullCounts(end+1,1)=r.FullCount;
            end
            record.Discarded=true;obj.SDURecords{hit}=record;
            obj.NextSDUCount=obj.NextSDUCount-1;
            if obj.ARQEnabled,obj.ARQ=next;end
            % Do not invalidate unaffected earlier prepared PDU tokens.
            receipt.Discarded=true;receipt.Disposition="discarded_wholly_unsubmitted";
        end
        function rows=takeSDUAcknowledgements(obj)
            rows=obj.SDUAcknowledgements;obj.SDUAcknowledgements=struct([]);
        end
        function [pdus,segment]=buildPDUs(obj,availableBytes,time)
            if nargin<3,time=0;end
            [pdus,segment,token]=obj.previewPDU(availableBytes);
            if ~isempty(pdus), obj.commitPreparedPDU(token,time); end
        end
        function [pdus,segment,token]=previewPDU(obj,availableBytes)
            % Allocation preparation does not consume an SDU or allocate an SN.
            assert(obj.State.Lifecycle=="ACTIVE",'sixgr:rlc:WindowViolation','RLC owner is not active.');
            segment=struct();
            token=struct();
            availableBytes=floor(double(availableBytes));
            if availableBytes<3
                pdus={}; return;
            end
            if obj.ARQEnabled && obj.ARQ.pendingRetxBytes()>0
                poll=obj.ARQ.PollRequired;
                proposed=obj.ARQ.previewRetx(availableBytes,logical(poll));
                if isempty(fieldnames(proposed)),pdus={};return;end
                d=sixgr.l2.rlc18.RLCHeaderCodec.decodeAM(proposed.PDU,obj.SNBits);
                if obj.pendingPayloadBytes()==0 && obj.ARQ.pendingRetxBytes()==numel(d.Payload)
                    poll=true;
                end
                [obj.ARQ,proposed]=obj.ARQ.prepareRetx(availableBytes,logical(poll));
                d=sixgr.l2.rlc18.RLCHeaderCodec.decodeAM(proposed.PDU,obj.SNBits);
                record=obj.ARQ.unackedRecords();
                hit=find(cellfun(@(r)r.Count==proposed.Count,record));
                assert(isscalar(hit),'sixgr:rlc:ARQBytes','Retx owns one retained original SDU.');
                segment=struct('SN',d.SN,'Offset',proposed.Offset, ...
                    'PayloadBytes',numel(d.Payload),'SDUBytes',numel(record{hit}.Bytes), ...
                    'HeaderBytes',d.HeaderBytes,'Complete',false, ...
                    'FullCount',proposed.Count,'IsRetransmission',true);
                segment.QueueID=obj.queueIDForCount(segment.FullCount);
            obj.markSDUHandoff(segment.FullCount);
            token=struct('Owner',obj.TxOwner,'Revision',obj.TxRevision,'ID',string(java.util.UUID.randomUUID()));
                obj.Prepared(char(token.ID))=struct('Token',token,'Segment',segment, ...
                    'PDU',proposed.PDU,'Poll',logical(d.Poll),'ARQProposal',proposed);
                pdus={proposed.PDU};return;
            end
            head=obj.Segment;
            if ~head.Active
                if isempty(obj.Queue),pdus={};return;end
                head=struct("Active",true,"Bytes",obj.Queue{1}, ...
                    "Offset",0,"SN",obj.State.TX_NEXT,'FullCount',obj.QueueCounts(1));
            end
            if obj.ARQEnabled && ~obj.ARQ.canTransmitInitial(head.FullCount)
                pdus={};return; % Retain queued SDUs until original received ACK opens the window.
            end
            baseHeader=2+double(obj.SNBits==18);
            remaining=numel(head.Bytes)-head.Offset;
            if head.Offset==0 && remaining<=availableBytes-baseHeader
                si=0; so=[];
                take=remaining;
            else
                headerBytes=baseHeader+double(head.Offset>0)*2;
                take=min(remaining,availableBytes-headerBytes);
                if take<=0,pdus={};return;end
                if head.Offset==0,si=1;so=[];
                elseif take==remaining,si=2;so=head.Offset;
                else,si=3;so=head.Offset;end
            end
            queuedAfter=numel(obj.Queue)-double(~obj.Segment.Active);
            poll=obj.PDUsSincePoll+1>=obj.PollPDU || ...
                obj.BytesSincePoll+take>=obj.PollByte || (take==remaining && queuedAfter==0);
            if obj.ARQEnabled,poll=poll || obj.ARQ.PollRequired;end
            header=sixgr.l2.rlc18.RLCHeaderCodec.encodeAM(obj.SNBits,1,poll,si,head.SN,so);
            payload=head.Bytes(head.Offset+(1:take));
            pdus={uint8([header payload])};
            segment=struct('SN',head.SN,'Offset',head.Offset, ...
                'PayloadBytes',take,'SDUBytes',numel(head.Bytes), ...
                'HeaderBytes',numel(header),'Complete',take==remaining, ...
                'FullCount',head.FullCount,'IsRetransmission',false);
            segment.QueueID=obj.queueIDForCount(segment.FullCount);
            obj.markSDUHandoff(segment.FullCount);
            token=struct('Owner',obj.TxOwner,'Revision',obj.TxRevision,'ID',string(java.util.UUID.randomUUID()));
            obj.Prepared(char(token.ID))=struct('Token',token,'Head',head, ...
                'Segment',segment,'PDU',pdus{1},'Poll',poll);
        end
        function validatePreparedPDU(obj,token)
            assert(isstruct(token) && isfield(token,'ID') && isKey(obj.Prepared,char(token.ID)), ...
                'sixgr:rlc:StaleTransmitPreparation','RLC preparation is unknown, stale, or already committed.');
            entry=obj.Prepared(char(token.ID));
            assert(isequaln(entry.Token,token) && token.Owner==obj.TxOwner && token.Revision==obj.TxRevision, ...
                'sixgr:rlc:StaleTransmitPreparation','Prepared RLC owner/revision changed.');
            assert(obj.State.Lifecycle=="ACTIVE",'sixgr:rlc:WindowViolation','RLC owner is not active.');
            if entry.Segment.IsRetransmission,return;end
            if ~obj.Segment.Active
                assert(~isempty(obj.Queue) && isequal(obj.Queue{1},entry.Head.Bytes) && ...
                    obj.State.TX_NEXT==entry.Head.SN,'sixgr:rlc:StaleTransmitPreparation','Original queued head changed.');
            end
        end
        function [pdu,segment]=commitPreparedPDU(obj,token,time)
            if nargin<3,time=0;end
            obj.validatePreparedPDU(token);
            entry=obj.Prepared(char(token.ID));
            if obj.ARQEnabled
                sample=obj.timeSample(time); receipt=obj.receipt(token.ID,entry.PDU,sample);
                receipt.OriginalToken=token;
                if entry.Segment.IsRetransmission
                    nextARQ=obj.ARQ.commitRetx(entry.ARQProposal,receipt);
                else
                    proposed=obj.ARQ.previewData(entry.Segment.FullCount,entry.PDU,token);
                    nextARQ=obj.ARQ.commitData(proposed,receipt);
                end
            end
            if entry.Segment.IsRetransmission
                obj.ARQ=nextARQ;obj.LastSample=sample;
                pdu=entry.PDU;segment=entry.Segment;
                obj.RetransmissionCount=obj.RetransmissionCount+1;
                if entry.Poll,obj.PDUsSincePoll=0;obj.BytesSincePoll=0;end
                obj.TxRevision=obj.TxRevision+1;
                obj.Prepared=containers.Map('KeyType','char','ValueType','any');return;
            end
            if ~obj.Segment.Active, obj.Queue(1)=[];obj.QueueCounts(1)=[];obj.QueueIDs(1)=[];end
            obj.Segment=entry.Head; segment=entry.Segment; pdu=entry.PDU;
            obj.Segment.Offset=obj.Segment.Offset+segment.PayloadBytes;
            obj.Segment.Active=~segment.Complete;
            % TS38.322 7.1: TX_Next advances for a complete SDU/last segment.
            if segment.Complete, obj.State.allocateSN(); end
            obj.TransmittedBytes=obj.TransmittedBytes+segment.PayloadBytes;
            obj.PollCount=obj.PollCount+1;
            obj.PDUsSincePoll=obj.PDUsSincePoll+1;
            obj.BytesSincePoll=obj.BytesSincePoll+segment.PayloadBytes;
            if entry.Poll, obj.PDUsSincePoll=0; obj.BytesSincePoll=0; end
            if obj.ARQEnabled,obj.ARQ=nextARQ;obj.LastSample=sample;end
            obj.TxRevision=obj.TxRevision+1;
            obj.Prepared=containers.Map('KeyType','char','ValueType','any');
        end
        function disposition=receivePDU(obj,pdu,time)
            if nargin<3,time=0;end
            assert(obj.State.Lifecycle=="ACTIVE",'sixgr:rlc:WindowViolation','Released bearer cannot accept PDUs.');
            if obj.ARQEnabled
                sample=obj.timeSample(time);
                [next,completed,disposition]=obj.Receiver.receive(uint8(pdu(:).'),sample);
                obj.Receiver=next;obj.LastSample=sample;
                for k=1:numel(completed),obj.Delivered{end+1}=completed(k).Bytes;end
                return;
            end
            decoded=sixgr.l2.rlc18.RLCHeaderCodec.decodeAM(pdu,obj.SNBits);
            disposition="partial";
            % TS38.322 V18.2.0 5.2.3.2: modulo receiving window, duplicate
            % byte removal and full SDU coverage, including overlapping resegmentation.
            modulus=2^obj.SNBits;
            distance=mod(decoded.SN-mod(obj.RXNextCount,modulus),modulus);
            if distance>=modulus/2,disposition="outside_window";return;end
            sn=obj.RXNextCount+distance;
            if isKey(obj.RxCompleted,sn),disposition="duplicate_bytes";return;end
            if isKey(obj.RxSegments,sn),state=obj.RxSegments(sn);
            else,state=struct('Bytes',uint8([]),'Present',false(1,0),'Last',NaN);end
            offset=0;
            if ~isempty(decoded.SO),offset=decoded.SO;end
            stop=offset+numel(decoded.Payload);
            assert(stop>offset,'sixgr:rlc:MalformedPDU','An AMD PDU must carry data.');
            indices=offset+(1:numel(decoded.Payload));
            if stop<=numel(state.Present)&&all(state.Present(indices))
                assert(isequal(state.Bytes(indices),decoded.Payload), ...
                    'sixgr:rlc:ConflictingReceivedSegment','Overlapping original decoded bytes disagree.');
                disposition="duplicate_bytes";return;
            end
            if ismember(decoded.SI,[0 2])
                assert(~isfinite(state.Last) || state.Last==stop, ...
                    'sixgr:rlc:MalformedPDU','Received last segments disagree on SDU extent.');
                assert(~any(state.Present(stop+1:end)), ...
                    'sixgr:rlc:MalformedPDU','Last segment truncates already received data.');
                state.Last=stop;
            end
            assert(~isfinite(state.Last) || stop<=state.Last, ...
                'sixgr:rlc:MalformedPDU','Segment exceeds received SDU extent.');
            if numel(state.Bytes)<stop
                state.Bytes(end+1:stop)=uint8(0); state.Present(end+1:stop)=false;
            end
            indices=offset+(1:numel(decoded.Payload)); duplicate=state.Present(indices);
            assert(isequal(state.Bytes(indices(duplicate)),decoded.Payload(duplicate)), ...
                'sixgr:rlc:ConflictingReceivedSegment','Overlapping original decoded byte segments disagree.');
            state.Bytes(indices(~duplicate))=decoded.Payload(~duplicate);
            state.Present(indices)=true;
            obj.RxSegments(sn)=state;
            if isfinite(state.Last) && all(state.Present(1:state.Last))
                disposition="complete";
                obj.Delivered{end+1}=state.Bytes(1:state.Last);
                remove(obj.RxSegments,sn); obj.RxCompleted(sn)=true;
                while isKey(obj.RxCompleted,obj.RXNextCount)
                    remove(obj.RxCompleted,obj.RXNextCount);
                    obj.RXNextCount=obj.RXNextCount+1;
                end
            end
        end
        function bytes=pendingPayloadBytes(obj)
            bytes=sum(cellfun(@numel,obj.Queue));
            if obj.Segment.Active
                bytes=bytes+numel(obj.Segment.Bytes)-obj.Segment.Offset;
            end
        end
        function bytes=pendingRetransmissionBytes(obj)
            bytes=0;if obj.ARQEnabled,bytes=obj.ARQ.pendingRetxBytes();end
        end
        function bytes=pendingStatusBytes(obj)
            bytes=0;if obj.ARQEnabled,bytes=obj.Receiver.pendingStatusBytes();end
        end
        function advance(obj,time)
            if ~obj.ARQEnabled,return;end
            sample=obj.timeSample(time);
            obj.Receiver=obj.Receiver.advance(sample);
            obj.ARQ=obj.ARQ.advancePollTimer(sample,obj.pendingPayloadBytes()==0,obj.ARQ.windowStalled());
            obj.LastSample=sample;
            obj.recordMaxRetxIndications("original_poll_timer");
        end
        function time=nextTimerExpiry(obj)
            time=inf;
            if obj.ARQEnabled,time=min(obj.ARQ.PollDeadline,obj.Receiver.nextTimerExpiry())/obj.Clock.SampleRateHz;end
        end
        function p=prepareStatus(obj,budget,time)
            assert(obj.ARQEnabled,'sixgr:rlc:ARQConfig','Explicit ARQ clock/timers required.');
            obj.advance(time);[obj.Receiver,p]=obj.Receiver.prepareStatus(budget,obj.LastSample);
        end
        function commitStatus(obj,p,id,time)
            obj.validateStatus(p,id,time);
            obj.advance(time);r=obj.receipt(id,p.Bytes,obj.LastSample);
            obj.Receiver=obj.Receiver.commitStatus(p,r);
        end
        function validateStatus(obj,p,id,time)
            assert(obj.ARQEnabled,'sixgr:rlc:ARQConfig','Explicit ARQ clock/timers required.');
            sample=obj.timeSample(time);
            receiver=obj.Receiver.advance(sample);
            receiver.commitStatus(p,obj.receipt(id,p.Bytes,sample));
        end
        function cancelStatus(obj,p)
            assert(obj.ARQEnabled,'sixgr:rlc:ARQConfig','Explicit ARQ clock/timers required.');
            obj.Receiver=obj.Receiver.releasePreparedStatus(p);
        end
        function disposition=receiveStatus(obj,bytes,id,time)
            token=obj.previewReceivedStatus(bytes,id,time);
            disposition=obj.commitReceivedStatus(token);
        end
        function token=previewReceivedStatus(obj,bytes,id,time)
            assert(obj.ARQEnabled,'sixgr:rlc:ARQConfig','Explicit ARQ clock/timers required.');
            assert(isa(bytes,'uint8')&&isrow(bytes)&&~isempty(bytes), ...
                'sixgr:rlc:ARQStatus','Require original received STATUS octets without conversion.');
            sample=obj.timeSample(time);r=obj.receipt(id,bytes,sample);
            r.Source="original_CRC_accepted_reverse_MAC_STATUS";
            % All timer/STATUS work happens on value owners. Invalid received
            % bytes cannot advance live clocks or create retransmissions.
            receiver=obj.Receiver.advance(sample);
            arq=obj.ARQ.advancePollTimer(sample,obj.pendingPayloadBytes()==0,obj.ARQ.windowStalled());
            [arq,disposition]=arq.admitSTATUS(bytes,r);
            token=struct('Owner',obj.TxOwner,'ID',string(java.util.UUID.randomUUID()), ...
                'ReceiptID',string(id),'PayloadSHA256',r.PayloadSHA256,'Sample',sample);
            obj.PreparedStatusReceives(char(token.ID))=struct('Token',token, ...
                'BaseARQ',obj.ARQ,'BaseReceiver',obj.Receiver,'BaseLastSample',obj.LastSample, ...
                'ARQ',arq,'Receiver',receiver,'LastSample',sample,'Disposition',disposition);
        end
        function validateReceivedStatus(obj,token)
            assert(obj.ARQEnabled&&isstruct(token)&&isfield(token,'ID')&& ...
                isKey(obj.PreparedStatusReceives,char(token.ID)), ...
                'sixgr:rlc:StaleSTATUSAdmission','Original uncommitted STATUS admission required.');
            entry=obj.PreparedStatusReceives(char(token.ID));
            assert(isequaln(token,entry.Token)&&isequaln(obj.ARQ,entry.BaseARQ)&& ...
                isequaln(obj.Receiver,entry.BaseReceiver)&&obj.LastSample==entry.BaseLastSample, ...
                'sixgr:rlc:StaleSTATUSAdmission','Bearer TX/RX/timer state changed after STATUS preview.');
        end
        function disposition=commitReceivedStatus(obj,token)
            obj.validateReceivedStatus(token);entry=obj.PreparedStatusReceives(char(token.ID));
            obj.ARQ=entry.ARQ;obj.Receiver=entry.Receiver;obj.LastSample=entry.LastSample;
            disposition=entry.Disposition;remove(obj.PreparedStatusReceives,char(token.ID));
            obj.recordMaxRetxIndications(token.ReceiptID);
            obj.recordSDUAcknowledgements(token);
        end
        function rows=takeUpperLayerIndications(obj)
            rows=obj.UpperLayerIndications;obj.UpperLayerIndications=struct([]);
        end
        function cancelReceivedStatus(obj,token)
            assert(isstruct(token)&&isfield(token,'ID')&& ...
                isKey(obj.PreparedStatusReceives,char(token.ID))&& ...
                isequaln(token,obj.PreparedStatusReceives(char(token.ID)).Token), ...
                'sixgr:rlc:StaleSTATUSAdmission','Unknown original STATUS admission.');
            remove(obj.PreparedStatusReceives,char(token.ID));
        end
        function cancelPreparedPDU(obj,token)
            obj.validatePreparedPDU(token);entry=obj.Prepared(char(token.ID));
            if entry.Segment.IsRetransmission,obj.ARQ=obj.ARQ.releasePreparedRetx(entry.ARQProposal);end
            remove(obj.Prepared,char(token.ID));
        end
        function sdus=pullSDUs(obj)
            sdus=obj.Delivered; obj.Delivered={};
        end
        function status=buildStatus(obj,ackSN,nacks)
            status=sixgr.l2.rlc18.RLCStatusCodec.encodeReport(obj.SNBits,ackSN,nacks);
        end
        function release(obj)
            obj.State.release();obj.Queue={};obj.Delivered={};
            obj.QueueCounts=[];obj.QueueIDs=strings(1,0);
            obj.ARQEnabled=false;obj.ARQ=[];obj.Receiver=[];
            obj.PreparedStatusReceives=containers.Map('KeyType','char','ValueType','any');
            obj.Segment.Active=false; obj.TxRevision=obj.TxRevision+1;
            obj.Prepared=containers.Map('KeyType','char','ValueType','any');
        end
    end
    methods (Access=private)
        function id=queueIDForCount(obj,count)
            hit=find(cellfun(@(r)~r.Discarded && r.FullCount==count,obj.SDURecords));
            assert(isscalar(hit),'sixgr:rlc:SDUIdentity','One original queue identity must own this count.');
            id=obj.SDURecords{hit}.QueueID;
        end
        function markSDUHandoff(obj,count)
            hit=find(cellfun(@(r)~r.Discarded && r.FullCount==count,obj.SDURecords));
            assert(isscalar(hit),'sixgr:rlc:SDUIdentity','Original SDU count must own one stable identity.');
            r=obj.SDURecords{hit};r.HandedToLowerLayer=true;obj.SDURecords{hit}=r;
        end
        function recordSDUAcknowledgements(obj,token)
            records=obj.ARQ.acknowledgedRecords();
            for k=1:numel(records)
                a=records{k};hit=find(cellfun(@(r)~r.Discarded && r.FullCount==a.Count,obj.SDURecords));
                assert(isscalar(hit),'sixgr:rlc:SDUIdentity','Actual ACK must join one original SDU.');
                r=obj.SDURecords{hit};
                if r.Acknowledged,continue;end
                assert(r.HandedToLowerLayer && r.PayloadSHA256==sixgr.protocol.ProtocolHash.bytes(a.Bytes), ...
                    'sixgr:rlc:SDUAcknowledgement','ACK cannot replace original submitted bytes.');
                row=struct('QueueID',r.QueueID,'RLCFullCount',a.Count, ...
                    'BearerID',obj.Identity.EntityID,'ConfigurationEpoch',obj.Identity.ConfigurationEpoch, ...
                    'PayloadSHA256',r.PayloadSHA256,'PayloadBytes',r.PayloadBytes, ...
                    'STATUSReceiptID',token.ReceiptID,'STATUSPayloadSHA256',token.PayloadSHA256, ...
                    'AcknowledgedAtSample',token.Sample,'SampleRateHz',obj.Clock.SampleRateHz, ...
                    'ClockEpoch',obj.Clock.ClockEpoch,'Source',"original_received_STATUS_all_original_SDU_bytes_ACKed");
                if isempty(obj.SDUAcknowledgements),obj.SDUAcknowledgements=row;
                else,obj.SDUAcknowledgements(end+1)=row;end
                r.Acknowledged=true;obj.SDURecords{hit}=r;
            end
        end
        function recordMaxRetxIndications(obj,sourceID)
            for count=obj.ARQ.maxRetxReached()
                if any(obj.MaxRetxNotifiedCounts==count),continue;end
                row=struct('UEID',obj.Identity.UEID,'BearerID',obj.Identity.BearerID, ...
                    'Direction',obj.Identity.Direction,'ConfigurationEpoch',obj.Identity.ConfigurationEpoch, ...
                    'RLCFullCount',count,'Type',"maximum_RLC_retransmissions_reached", ...
                    'Sample',obj.LastSample,'SampleRateHz',obj.Clock.SampleRateHz, ...
                    'ClockEpoch',obj.Clock.ClockEpoch,'MaxRetxThreshold',obj.MaxRetxThreshold, ...
                    'SourceEventID',string(sourceID),'Source',"original_RLC_AM_retransmission_counter", ...
                    'ApplicationBytesDropped',0,'UpperLayerAction',"pending_RRC_consumer");
                row.IndicationID=sixgr.l2.mac.MACHash.of(orderfields(row));
                obj.MaxRetxNotifiedCounts(end+1)=count;
                if isempty(obj.UpperLayerIndications),obj.UpperLayerIndications=row;
                else,obj.UpperLayerIndications(end+1)=row;end
            end
        end
        function sample=timeSample(obj,time)
            x=time*obj.Clock.SampleRateHz;sample=round(x);
            assert(isnumeric(time)&&isscalar(time)&&isfinite(time)&&time>=0 && ...
                abs(x-sample)<=max(1e-7,8*eps(x)) && sample>=obj.LastSample, ...
                'sixgr:rlc:ARQClock','Protocol time must be an original monotonic sample boundary.');
        end
        function r=receipt(obj,id,bytes,sample)
            r=struct('ID',string(id),'BearerID',obj.Identity.EntityID,'Sample',sample, ...
                'ClockEpoch',obj.Clock.ClockEpoch,'SampleRateHz',obj.Clock.SampleRateHz, ...
                'Source',"actual_MAC_lower_layer_submission", ...
                'PayloadSHA256',sixgr.protocol.ProtocolHash.bytes(bytes));
        end
    end
end
function value=localField(config,name,defaultValue)
if isfield(config,name),value=config.(name);else,value=defaultValue;end
end
