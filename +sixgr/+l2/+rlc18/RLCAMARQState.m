classdef RLCAMARQState
    % TX ARQ state. No callback manufactures received STATUS.
    % TS38.322 V18.2.0 5.3.2/5.3.3. Lower-layer accepted transmission
    % commits must be supplied by the real MAC/PHY owner; preview is pure.
    properties (SetAccess=private)
        Config struct
        Records cell = {}
        NextAck double = 0
        HighestSubmitted double = -1
        Revision double = 0
        PollSN double = NaN
        PollDeadline double = Inf
        PollRequired logical = false
        SeenTX string = strings(0,1)
        SeenSTATUS string = strings(0,1)
        LastSample double = 0
    end
    properties (Access=private)
        PreparedRetx cell = {}
    end
    methods
        function obj=RLCAMARQState(c)
            assert(all(isfield(c,{'BearerID','SNBits','InitialCount','PollRetransmitSamples','ClockEpoch','SampleRateHz','MaxRetxThreshold'})), 'sixgr:rlc:ARQConfig','Explicit ARQ policy required.');
            assert(ismember(c.SNBits,[12 18]) && c.InitialCount>=0 && c.InitialCount==fix(c.InitialCount) && c.PollRetransmitSamples>0 && c.PollRetransmitSamples==fix(c.PollRetransmitSamples) && c.SampleRateHz>0 && c.MaxRetxThreshold>=1,'sixgr:rlc:ARQConfig','Invalid policy.');
            obj.Config=c; obj.NextAck=c.InitialCount; obj.HighestSubmitted=c.InitialCount-1;
        end
        function next=retainSDU(obj,count,bytes)
            assert(isa(bytes,'uint8') && isrow(bytes) && ~isempty(bytes) && numel(bytes)<=65536,'sixgr:rlc:ARQBytes','Retain original SDU octets; offsets are 16 bit.');
            assert(count==obj.Config.InitialCount+numel(obj.Records) && isfinite(count) && count<flintmax,'sixgr:rlc:ARQWindow','Queued full counts must be contiguous and exactly representable.');
            r=struct('Count',count,'Bytes',bytes,'Sent',false(size(bytes)),'Acked',false(size(bytes)), ...
                'Pending',false(size(bytes)),'Considered',false,'RetxCount',0);
            next=obj; next.Records{end+1}=r; next.Revision=next.Revision+1;
        end
        function [next,receipt]=discardUnsubmitted(obj,count,protectedCounts)
            if nargin<3,protectedCounts=[];end
            index=obj.index(count);r=obj.Records{index};next=obj;
            receipt=struct('Discarded',false,'Count',count,'PayloadSHA256',sixgr.protocol.ProtocolHash.bytes(r.Bytes), ...
                'OldFullCounts',zeros(0,1),'NewFullCounts',zeros(0,1),'Disposition',"retained_submitted_or_protected");
            if count<=obj.HighestSubmitted || any(r.Sent) || any(protectedCounts>=count),return;end
            later=obj.Records(index+1:end);
            assert(~any(cellfun(@(x)any(x.Sent)||any(x.Acked)||any(x.Pending),later)), ...
                'sixgr:rlc:ARQDiscardConflict','Only wholly unsubmitted later counts may compact.');
            next.Records(index)=[];
            for k=index:numel(next.Records)
                v=next.Records{k};receipt.OldFullCounts(end+1,1)=v.Count;
                v.Count=v.Count-1;next.Records{k}=v;
                receipt.NewFullCounts(end+1,1)=v.Count;
            end
            next.Revision=next.Revision+1;receipt.Discarded=true;
            receipt.Disposition="discarded_wholly_unsubmitted";
            % HighestSubmitted, NextAck, poll clock, submitted masks and all
            % retained original retransmission proposals remain unchanged.
        end
        function records=acknowledgedRecords(obj)
            records=obj.Records(cellfun(@(r)all(r.Sent)&&all(r.Acked),obj.Records));
        end
        function proposal=previewData(obj,count,pdu,originalToken)
            % Adapter must obtain pdu/token from the SAME original RLCAMEntity
            % preview and validate that token at commit. No independent re-encode.
            assert(isa(pdu,'uint8') && isrow(pdu) && ~isempty(pdu), 'sixgr:rlc:ARQBytes','Original encoded AMD octets required.');
            assert(isstruct(originalToken)&&isscalar(originalToken)&&all(isfield(originalToken,{'Owner','Revision','ID'})) && ...
                isstring(originalToken.Owner)&&isscalar(originalToken.Owner)&&strlength(originalToken.Owner)>0 && ...
                isstring(originalToken.ID)&&isscalar(originalToken.ID)&&strlength(originalToken.ID)>0 && ...
                isnumeric(originalToken.Revision)&&isscalar(originalToken.Revision)&&isfinite(originalToken.Revision)&&originalToken.Revision>=0&&originalToken.Revision==fix(originalToken.Revision), ...
                'sixgr:rlc:ARQToken','Original RLC preview owner/revision/token required.');
            assert(obj.canTransmitInitial(count),'sixgr:rlc:ARQWindow','Initial submission must remain inside the current transmit window.');
            d=sixgr.l2.rlc18.RLCHeaderCodec.decodeAM(pdu,obj.Config.SNBits);
            index=obj.index(count);r=obj.Records{index};offset=0;if ~isempty(d.SO),offset=d.SO;end
            positions=offset+(1:numel(d.Payload));
            assert(d.SN==mod(count,2^obj.Config.SNBits) && ~isempty(positions) && positions(end)<=numel(r.Bytes) && ...
                isequal(d.Payload,r.Bytes(positions)) && ~any(r.Sent(positions)), 'sixgr:rlc:ARQBytes','AMD payload/SN must bind exact retained unsent bytes.');
            assert((ismember(d.SI,[0 1]) && offset==0 || ismember(d.SI,[2 3]) && offset>0) && ...
                (ismember(d.SI,[0 2]) == (positions(end)==numel(r.Bytes))), 'sixgr:rlc:ARQBytes','Original segmentation header disagrees with original SDU extent.');
            proposal=struct('Revision',obj.Revision,'Count',count,'Offset',offset,'StopExclusive',positions(end), ...
                'PDU',pdu,'Poll',logical(d.Poll),'OriginalToken',originalToken);
            proposal.Digest=localHash(proposal);
        end
        function next=commitData(obj,proposal,receipt)
            obj.validateReceipt(receipt,'actual_MAC_lower_layer_submission');
            assert(~any(obj.SeenTX==receipt.ID),'sixgr:rlc:ARQDuplicate','Original TX was already committed.');
            assert(isequaln(proposal,obj.previewData(proposal.Count,proposal.PDU,proposal.OriginalToken)) && ...
                isfield(receipt,'OriginalToken') && isequaln(receipt.OriginalToken,proposal.OriginalToken) && ...
                receipt.PayloadSHA256==localHash(proposal.PDU), 'sixgr:rlc:ARQStaleProposal','Commit exact original AMD bytes and still-current original preview token.');
            next=obj;index=obj.index(proposal.Count);r=obj.Records{index};
            r.Sent(proposal.Offset+1:proposal.StopExclusive)=true;next.Records{index}=r;
            next.HighestSubmitted=max(next.HighestSubmitted,proposal.Count);
            next=next.commitClock(receipt,proposal.Poll);
        end
        function [next,disposition]=admitSTATUS(obj,bytes,receipt)
            obj.validateReceipt(receipt,'original_CRC_accepted_reverse_MAC_STATUS');
            assert(isa(bytes,'uint8') && isrow(bytes) && receipt.PayloadSHA256==localHash(bytes),'sixgr:rlc:ARQStatus','Original received STATUS octets/hash required.');
            next=obj;
            if any(obj.SeenSTATUS==receipt.ID), disposition="duplicate_original_receipt"; return; end
            report=sixgr.l2.rlc18.RLCStatusCodec.decodeReport(bytes,obj.Config.SNBits);
            modulus=2^obj.Config.SNBits;
            distance=mod(report.ACKSN-mod(obj.NextAck,modulus),modulus);
            if distance>modulus/2 || (distance==modulus/2 && obj.NextAck+distance>obj.HighestSubmitted+1)
                disposition="stale_ACK_outside_TX_window"; return;
            end
            ack=obj.NextAck+distance;
            assert(ack<=obj.HighestSubmitted+1,'sixgr:rlc:ARQStatus','ACK cannot acknowledge an unsubmitted SN.');
            masks=cell(size(obj.Records));
            for k=1:numel(masks), masks{k}=false(size(obj.Records{k}.Bytes)); end
            for n=report.NACKs
                first=ack-mod(report.ACKSN-n.NACKSN,modulus);
                range=1; if ~isempty(n.NACKRange),range=n.NACKRange;end
                for q=0:range-1
                    count=first+q;
                    if count<obj.NextAck,continue;end
                    idx=obj.index(count); r=obj.Records{idx}; lo=0; hi=numel(r.Bytes)-1;
                    if ~isempty(n.SOstart)
                        if q==0,lo=n.SOstart;end
                        if q==range-1 && n.SOend~=65535,hi=n.SOend;end
                    end
                    assert(lo<=hi && hi<numel(r.Bytes),'sixgr:rlc:ARQStatus','NACK interval exceeds retained SDU.');
                    positions=lo+1:hi+1;
                    % A received 65535 tail may include unsent bytes. Preserve
                    % their initial-TX ownership; never resurrect acknowledged support.
                    masks{idx}(positions)=r.Sent(positions) & ~r.Acked(positions);
                end
            end
            for k=1:numel(obj.Records)
                r=obj.Records{k}; if r.Count<obj.NextAck || r.Count>=ack,continue;end
                % Positive acknowledgement only covers actual submitted support.
                missing=masks{k}; fresh=missing & ~r.Pending;
                if any(fresh)
                    if r.Considered,r.RetxCount=r.RetxCount+1;else,r.Considered=true;r.RetxCount=0;end
                end
                r.Acked=r.Acked|(r.Sent & ~missing); r.Pending=missing; next.Records{k}=r;
            end
            while next.NextAck<=next.HighestSubmitted
                r=next.Records{next.index(next.NextAck)};
                if ~all(r.Acked),break;end
                next.NextAck=next.NextAck+1;
            end
            if isfinite(obj.PollSN) && obj.PollSN<ack, next.PollDeadline=Inf; end
            next.SeenSTATUS(end+1)=receipt.ID; next.LastSample=receipt.Sample;
            next.Revision=next.Revision+1; disposition="original_STATUS_applied";
        end
        function proposal=previewRetx(obj,budget,poll)
            assert(isscalar(budget)&&budget==fix(budget)&&budget>=0 && islogical(poll)&&isscalar(poll),'sixgr:rlc:ARQBudget','Explicit grant budget/header poll required.');
            proposal=struct();
            for k=1:numel(obj.Records)
                r=obj.Records{k}; first=find(r.Pending,1); if isempty(first),continue;end
                offset=first-1; headerBytes=2+double(obj.Config.SNBits==18)+2*double(offset>0);
                if budget<=headerBytes,return;end
                stop=first; while stop<numel(r.Bytes)&&r.Pending(stop+1),stop=stop+1;end
                stop=min(stop,first+budget-headerBytes-1);
                si=3; if offset==0,si=1;end
                if stop==numel(r.Bytes),si=2;if offset==0,si=0;end;end
                so=offset;if offset==0,so=[];end
                header=sixgr.l2.rlc18.RLCHeaderCodec.encodeAM(obj.Config.SNBits,1,poll,si,mod(r.Count,2^obj.Config.SNBits),so);
                proposal=struct('Revision',obj.Revision,'Count',r.Count,'Offset',offset,'StopExclusive',stop,'Poll',poll, ...
                    'Budget',budget,'PDU',uint8([header r.Bytes(first:stop)]));
                proposal.Digest=localHash(proposal);return;
            end
        end
        function next=commitRetx(obj,p,receipt)
            obj.validateReceipt(receipt,'actual_MAC_lower_layer_submission');
            match=cellfun(@(original)isequaln(original,p),obj.PreparedRetx);
            assert(~any(obj.SeenTX==receipt.ID) && nnz(match)==1, 'sixgr:rlc:ARQStaleProposal','Changed/duplicate original prepared retransmission.');
            assert(receipt.PayloadSHA256==localHash(p.PDU),'sixgr:rlc:ARQBytes','Commit exact submitted AMD bytes.');
            next=obj; idx=obj.index(p.Count);r=obj.Records{idx};r.Pending(p.Offset+1:p.StopExclusive)=false;next.Records{idx}=r;
            next.PreparedRetx(match)=[];
            next=next.commitClock(receipt,p.Poll);
        end
        function [next,p]=prepareRetx(obj,budget,poll)
            next=obj;p=obj.previewRetx(budget,poll);
            if isempty(fieldnames(p)),return;end
            assert(isempty(obj.PreparedRetx),'sixgr:rlc:ARQOutstandingPreparation','One actual retransmission preparation per bearer at a time.');
            p=rmfield(p,'Digest');
            p.PreparationID=sixgr.l2.mac.MACHash.of(struct('Bearer',obj.Config.BearerID, ...
                'Epoch',obj.Config.ClockEpoch,'Snapshot',p));
            p.Digest=localHash(p);next.PreparedRetx{end+1}=p;
        end
        function next=releasePreparedRetx(obj,p)
            % Explicit scheduling withholding: bytes stay pending; no TX receipt.
            match=cellfun(@(original)isequaln(original,p),obj.PreparedRetx);
            assert(nnz(match)==1,'sixgr:rlc:ARQStaleProposal','Unknown original withheld preparation.');
            next=obj;next.PreparedRetx(match)=[];
        end
        function next=advancePollTimer(obj,sample,newDataBufferEmpty,windowStalled)
            assert(sample>=obj.LastSample && sample==fix(sample) && islogical(newDataBufferEmpty)&&isscalar(newDataBufferEmpty) && islogical(windowStalled)&&isscalar(windowStalled),'sixgr:rlc:ARQClock','Original clock and queue state required.');
            next=obj;next.LastSample=sample;
            if sample<obj.PollDeadline,return;end
            next.PollDeadline=Inf;next.PollRequired=true;
            pending=any(cellfun(@(r)any(r.Pending),obj.Records));
            if (newDataBufferEmpty && ~pending)||windowStalled
                for k=numel(obj.Records):-1:1
                    r=obj.Records{k};missing=r.Sent & ~r.Acked;
                    if ~any(missing),continue;end
                    if any(missing & ~r.Pending)
                        if r.Considered,r.RetxCount=r.RetxCount+1;else,r.Considered=true;r.RetxCount=0;end
                    end
                    r.Pending=r.Pending|missing;next.Records{k}=r;break;
                end
            end
            next.Revision=next.Revision+1;
        end
        function counts=maxRetxReached(obj)
            counts=[];
            for r=obj.Records,if r{1}.Considered && r{1}.RetxCount>=obj.Config.MaxRetxThreshold,counts(end+1)=r{1}.Count;end;end %#ok<AGROW>
        end
        function allowed=canTransmitInitial(obj,count)
            allowed=isnumeric(count)&&isscalar(count)&&isfinite(count)&&count==fix(count) && ...
                count>=obj.NextAck && count<obj.NextAck+2^(obj.Config.SNBits-1) && ...
                count>=obj.Config.InitialCount && count<obj.nextRetainedCount();
        end
        function stalled=windowStalled(obj)
            % True when the oldest not-yet-submitted queued byte is beyond
            % the current send window. Pending retx ownership is separate.
            stalled=false;
            for k=1:numel(obj.Records)
                r=obj.Records{k};
                if any(~r.Sent),stalled=~obj.canTransmitInitial(r.Count);return;end
            end
        end
        function bytes=pendingRetxBytes(obj)
            bytes=sum(cellfun(@(r)nnz(r.Pending),obj.Records));
        end
        function count=nextRetainedCount(obj)
            % Full count, never a modular SN guessed from a table row.
            count=obj.Config.InitialCount+numel(obj.Records);
        end
        function records=unackedRecords(obj)
            records=obj.Records(cellfun(@(r)any(r.Sent & ~r.Acked),obj.Records));
        end
    end
    methods (Access=private)
        function idx=index(obj,count)
            idx=count-obj.Config.InitialCount+1;
            assert(idx>=1&&idx<=numel(obj.Records)&&idx==fix(idx),'sixgr:rlc:ARQWindow','Unknown original full SN count.');
        end
        function validateReceipt(obj,r,source)
            assert(isstruct(r)&&all(isfield(r,{'ID','BearerID','Sample','ClockEpoch','SampleRateHz','Source','PayloadSHA256'})) && ...
                isstring(r.ID)&&isscalar(r.ID)&&strlength(r.ID)>0 && r.BearerID==obj.Config.BearerID && r.Source==source && r.ClockEpoch==obj.Config.ClockEpoch && r.SampleRateHz==obj.Config.SampleRateHz && r.Sample>=obj.LastSample && r.Sample==fix(r.Sample), 'sixgr:rlc:ARQReceipt','Original bearer/clock receipt required.');
        end
        function next=commitClock(obj,r,poll)
            next=obj;next.SeenTX(end+1)=r.ID;next.LastSample=r.Sample;next.Revision=next.Revision+1;
            if poll,next.PollSN=next.HighestSubmitted;next.PollDeadline=r.Sample+obj.Config.PollRetransmitSamples;next.PollRequired=false;end
        end
    end
end
function h=localHash(x)
if isa(x,'uint8'),h=sixgr.protocol.ProtocolHash.bytes(x);
else,h=sixgr.l2.mac.MACHash.of(orderfieldsIfStruct(x));end
end
function x=orderfieldsIfStruct(x)
if isstruct(x),x=orderfields(x);end
end
