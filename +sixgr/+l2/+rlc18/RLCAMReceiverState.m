classdef RLCAMReceiverState
    % TS38.322 V18.2.0 receiver state from original decoded AMD octets only.
    % Caller authenticates bearer/CRC at MAC demultiplexing. No TX-byte oracle.
    properties (SetAccess=private)
        Config struct
        RXNext double
        RXNextHighest double
        RXHighestStatus double
        RXNextStatusTrigger double
        Records cell = {}
        DelayedPolls double = []
        ReassemblyDeadline double = Inf
        StatusProhibitDeadline double = Inf
        StatusTriggered logical = false
        Revision double = 0
        LastSample double = 0
        SubmittedStatusIDs string = strings(0,1)
        TriggerGeneration double = 0
    end
    properties (Access=private)
        PreparedStatus cell = {}
    end
    methods
        function obj=RLCAMReceiverState(c)
            assert(isstruct(c)&&all(isfield(c,{'BearerID','SNBits','InitialCount','ReassemblySamples','StatusProhibitSamples','ClockEpoch','SampleRateHz'})), 'sixgr:rlc:RXConfig','Explicit receiver timer/identity policy required.');
            v=[c.InitialCount c.ReassemblySamples c.StatusProhibitSamples c.ClockEpoch c.SampleRateHz];
            assert(ismember(c.SNBits,[12 18])&&all(isfinite(v)&v>=0&v==fix(v))&&c.ReassemblySamples>0&&c.SampleRateHz>0,'sixgr:rlc:RXConfig','Invalid receiver clock/timers.');
            obj.Config=c;obj.RXNext=c.InitialCount;obj.RXNextHighest=c.InitialCount;
            obj.RXHighestStatus=c.InitialCount;obj.RXNextStatusTrigger=c.InitialCount;
        end
        function [next,completed,disposition]=receive(obj,pdu,sample)
            assert(isa(pdu,'uint8')&&isrow(pdu)&&~isempty(pdu),'sixgr:rlc:RXBytes','Original received AMD octets required.');
            next=obj.advance(sample);completed=struct('FullCount',{},'Bytes',{});
            disposition="partial";
            d=sixgr.l2.rlc18.RLCHeaderCodec.decodeAM(pdu,obj.Config.SNBits);
            assert(~isempty(d.Payload),'sixgr:rlc:RXBytes','AMD contains no payload.');
            modulus=2^obj.Config.SNBits;delta=mod(d.SN-mod(next.RXNext,modulus),modulus);
            if delta>=modulus/2
                disposition="outside_window";
                if d.Poll,next=next.triggerStatus();end
                next.Revision=next.Revision+1;return;
            end
            count=next.RXNext+delta;idx=next.index(count);
            if isempty(idx)
                r=struct('Count',count,'Bytes',uint8([]),'Present',false(1,0),'Last',NaN,'Complete',false,'CaptureHashes',strings(0,1));
                idx=numel(next.Records)+1;
            else,r=next.Records{idx};end
            offset=0;if ~isempty(d.SO),offset=d.SO;end
            stop=offset+numel(d.Payload);assert(stop<=65536,'sixgr:rlc:RXBytes','Unsupported SDU byte extent.');
            positions=offset+1:stop;
            if stop<=numel(r.Present) && all(r.Present(positions))
                assert(isequal(r.Bytes(positions),d.Payload),'sixgr:rlc:RXConflict','Original overlapping bytes disagree.');
                % TS38.322 5.2.3.2.2: discard the entire duplicate AMD.
                % Its changed SI/final marker cannot alter retained extent.
                if d.Poll,next=next.triggerStatus();end
                disposition="duplicate_bytes";
                next.Revision=next.Revision+1;return;
            end
            if ismember(d.SI,[0 2])
                assert(~isfinite(r.Last)||r.Last==stop,'sixgr:rlc:RXBytes','Conflicting original final extent.');
                assert(~any(r.Present(stop+1:end)),'sixgr:rlc:RXBytes','Final extent truncates received bytes.');r.Last=stop;
            end
            assert(~isfinite(r.Last)||stop<=r.Last,'sixgr:rlc:RXBytes','Received segment exceeds original final extent.');
            if numel(r.Bytes)<stop,r.Bytes(end+1:stop)=uint8(0);r.Present(end+1:stop)=false;end
            positions=offset+1:stop;duplicate=r.Present(positions);
            assert(isequal(r.Bytes(positions(duplicate)),d.Payload(duplicate)), 'sixgr:rlc:RXConflict','Original overlapping bytes disagree.');
            discarded=all(duplicate);r.Bytes(positions)=d.Payload;r.Present(positions)=true;
            r.CaptureHashes(end+1)=sixgr.protocol.ProtocolHash.bytes(pdu);
            newlyComplete=~r.Complete&&isfinite(r.Last)&&all(r.Present(1:r.Last));
            r.Complete=r.Complete||newlyComplete;next.Records{idx}=r;
            if ~discarded
                next.RXNextHighest=max(next.RXNextHighest,count+1);
                if newlyComplete
                    disposition="complete";
                    completed=struct('FullCount',count,'Bytes',r.Bytes(1:r.Last));
                    if count==next.RXHighestStatus,next.RXHighestStatus=next.firstIncomplete(count);end
                    if count==next.RXNext,next.RXNext=next.firstIncomplete(count);end
                end
                next=next.updateReassembly(sample);
            end
            if d.Poll
                if discarded || count<next.RXHighestStatus || count>=next.RXNext+modulus/2
                    next=next.triggerStatus();
                else,next.DelayedPolls=unique([next.DelayedPolls count]);end
            end
            next=next.resolvePolls();next.Revision=next.Revision+1;
        end
        function next=advance(obj,sample)
            assert(isnumeric(sample)&&isscalar(sample)&&isfinite(sample)&&sample>=obj.LastSample&&sample==fix(sample),'sixgr:rlc:RXClock','Monotonic original sample clock required.');
            next=obj;
            if sample>=next.ReassemblyDeadline
                expiry=next.ReassemblyDeadline;next.ReassemblyDeadline=Inf;
                next.RXHighestStatus=next.firstIncomplete(next.RXNextStatusTrigger);
                next=next.triggerStatus();
                if next.hasGapAfter(next.RXHighestStatus)
                    next.ReassemblyDeadline=expiry+next.Config.ReassemblySamples;
                    next.RXNextStatusTrigger=next.RXNextHighest;
                end
                next.Revision=next.Revision+1;next=next.resolvePolls();
                % Caller should schedule exact deadlines; process a bounded
                % subsequent expiry if a clock jump spans another deadline.
                if next.ReassemblyDeadline<=sample,next=next.advance(sample);end
            end
            if sample>=next.StatusProhibitDeadline,next.StatusProhibitDeadline=Inf;end
            next.LastSample=sample;
        end
        function p=previewStatus(obj,budget,sample)
            assert(isscalar(budget)&&budget>=0&&(isinf(budget)||budget==fix(budget)),'sixgr:rlc:RXBudget','Actual reverse grant octet budget required.');
            assert(sample==obj.LastSample,'sixgr:rlc:RXClock','Advance the original receive owner before preview.');
            p=struct();if ~obj.StatusTriggered||isfinite(obj.StatusProhibitDeadline)||budget<3,return;end
            nacks=struct('NACKSN',{},'SOstart',{},'SOend',{},'NACKRange',{});
            ack=obj.RXHighestStatus;modulus=2^obj.Config.SNBits;
            for count=obj.RXNext:obj.RXHighestStatus-1
                added=obj.missing(count);if isempty(added),continue;end
                candidate=[nacks added];
                encoded=sixgr.l2.rlc18.RLCStatusCodec.encodeReport(obj.Config.SNBits,mod(count+1,modulus),candidate);
                if encoded.ByteCount>budget,ack=count;break;end
                nacks=candidate;
            end
            encoded=sixgr.l2.rlc18.RLCStatusCodec.encodeReport(obj.Config.SNBits,mod(ack,modulus),nacks);
            p=struct('Revision',obj.Revision,'FullACKCount',ack,'Bytes',encoded.Bytes,'NACKs',nacks,'Budget',budget,'Sample',sample);
            p.Digest=sixgr.l2.mac.MACHash.of(orderfields(p));
        end
        function next=commitStatus(obj,p,r)
            assert(isstruct(r)&&all(isfield(r,{'ID','BearerID','Sample','ClockEpoch','SampleRateHz','Source','PayloadSHA256'}))&& ...
                r.BearerID==obj.Config.BearerID&&r.ClockEpoch==obj.Config.ClockEpoch&&r.SampleRateHz==obj.Config.SampleRateHz&& ...
                r.Source=="actual_MAC_lower_layer_submission"&&r.Sample==obj.LastSample&&r.Sample==fix(r.Sample)&& ...
                isstring(r.ID)&&isscalar(r.ID)&&strlength(r.ID)>0&&~any(obj.SubmittedStatusIDs==r.ID), 'sixgr:rlc:RXCommit','Original reverse submission receipt required.');
            match=cellfun(@(original)isequaln(original,p),obj.PreparedStatus);
            assert(nnz(match)==1 && p.Sample<=obj.LastSample && ...
                r.PayloadSHA256==sixgr.protocol.ProtocolHash.bytes(p.Bytes), ...
                'sixgr:rlc:RXCommit','Retain the privately owned original prepared STATUS and actual emitted octets.');
            next=obj;
            if obj.TriggerGeneration<=p.TriggerGeneration,next.StatusTriggered=false;end
            next.PreparedStatus={};
            next.StatusProhibitDeadline=r.Sample+obj.Config.StatusProhibitSamples;
            next.SubmittedStatusIDs(end+1)=r.ID;next.LastSample=r.Sample;next.Revision=next.Revision+1;
            if obj.Config.StatusProhibitSamples==0,next.StatusProhibitDeadline=Inf;end
        end
        function [next,p]=prepareStatus(obj,budget,sample)
            p=obj.previewStatus(budget,sample);next=obj;
            if isempty(fieldnames(p)),return;end
            p=rmfield(p,'Digest');p.TriggerGeneration=obj.TriggerGeneration;
            p.PreparationID=sixgr.l2.mac.MACHash.of(struct('Bearer',obj.Config.BearerID, ...
                'Epoch',obj.Config.ClockEpoch,'Ordinal',numel(obj.PreparedStatus)+1,'Snapshot',p));
            p.Digest=sixgr.l2.mac.MACHash.of(orderfields(p));
            next.PreparedStatus{end+1}=p;
        end
        function next=releasePreparedStatus(obj,p)
            match=cellfun(@(original)isequaln(original,p),obj.PreparedStatus);
            assert(nnz(match)==1,'sixgr:rlc:RXCommit','Unknown original withheld STATUS preparation.');
            next=obj;next.PreparedStatus(match)=[];
            % Trigger and prohibit clock remain unchanged: nothing submitted.
        end
        function sample=nextTimerExpiry(obj)
            sample=obj.ReassemblyDeadline;
            if obj.StatusTriggered,sample=min(sample,obj.StatusProhibitDeadline);end
        end
        function bytes=pendingStatusBytes(obj)
            p=obj.previewStatus(Inf,obj.LastSample);bytes=0;if ~isempty(fieldnames(p)),bytes=numel(p.Bytes);end
        end
    end
    methods (Access=private)
        function idx=index(obj,count)
            idx=find(cellfun(@(r)r.Count==count,obj.Records),1);
        end
        function count=firstIncomplete(obj,count)
            while true
                idx=obj.index(count);if isempty(idx)||~obj.Records{idx}.Complete,return;end
                count=count+1;
            end
        end
        function yes=internalGap(obj,count)
            idx=obj.index(count);yes=false;
            if ~isempty(idx),r=obj.Records{idx};yes=any(~r.Present);end
        end
        function yes=hasGapAfter(obj,count)
            yes=obj.RXNextHighest>count+1 || (obj.RXNextHighest==count+1 && obj.internalGap(count));
        end
        function next=updateReassembly(obj,sample)
            next=obj;upper=obj.RXNext+2^(obj.Config.SNBits-1);t=obj.RXNextStatusTrigger;
            if isfinite(obj.ReassemblyDeadline) && (t==obj.RXNext || (t==obj.RXNext+1 && ~obj.internalGap(obj.RXNext)) || ((t<obj.RXNext||t>upper)&&t~=upper))
                next.ReassemblyDeadline=Inf;
            end
            if ~isfinite(next.ReassemblyDeadline)&&next.hasGapAfter(next.RXNext)
                next.ReassemblyDeadline=sample+next.Config.ReassemblySamples;next.RXNextStatusTrigger=next.RXNextHighest;
            end
        end
        function next=resolvePolls(obj)
            next=obj;due=obj.DelayedPolls<obj.RXHighestStatus | obj.DelayedPolls>=obj.RXNext+2^(obj.Config.SNBits-1);
            if any(due),next=next.triggerStatus();next.DelayedPolls(due)=[];end
        end
        function next=triggerStatus(obj)
            next=obj;next.StatusTriggered=true;next.TriggerGeneration=next.TriggerGeneration+1;
        end
        function nacks=missing(obj,count)
            nacks=struct('NACKSN',{},'SOstart',{},'SOend',{},'NACKRange',{});
            n=struct('NACKSN',mod(count,2^obj.Config.SNBits),'SOstart',[],'SOend',[],'NACKRange',[]);
            idx=obj.index(count);if isempty(idx),nacks=n;return;end
            r=obj.Records{idx};if r.Complete,return;end
            support=r.Present;if ~isfinite(r.Last),support(end+1)=false;end
            starts=find(diff([true support])==-1);stops=find(diff([support true])==1);
            for k=1:numel(starts)
                n.SOstart=starts(k)-1;n.SOend=stops(k)-1;
                if ~isfinite(r.Last)&&stops(k)==numel(support),n.SOend=65535;end
                nacks(end+1)=n; %#ok<AGROW>
            end
        end
    end
end
