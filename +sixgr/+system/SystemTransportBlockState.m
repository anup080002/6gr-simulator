classdef SystemTransportBlockState < handle
% Immutable grant-level payload identity scoped to one SLS execution.
    properties (Access=private)
        Processes
        Stream
        Sequence double = 0
        Namespace string
        MaterializeBits logical = true
    end
    methods
        function obj=SystemTransportBlockState(seed,materializeBits)
            if nargin>=2, obj.MaterializeBits=logical(materializeBits); end
            obj.Processes=containers.Map('KeyType','char','ValueType','any');
            obj.Stream=RandStream('mt19937ar','Seed',seed);
            obj.Namespace=string(java.util.UUID.randomUUID());
        end
        function [ctx,previous]=bind(obj,ctx)
            g=ctx.Grant; h=sixgr.util.structGet(g,'HARQ',struct());
            retx=logical(sixgr.util.structGet(h,'IsRetransmission', ...
                sixgr.util.structGet(g,'IsRetransmission',false)));
            pid=double(sixgr.util.structGet(h,'HarqID',NaN));
            key=char(join([string(ctx.Direction),string(ctx.ServingCellID), ...
                string(g.RNTI),string(pid)],'|'));
            previous="";
            if retx
                if ~isKey(obj.Processes,key)
                    error('sixgr:system:MissingTransportBlock','Retransmission has no first-transmission payload.');
                end
                b=obj.Processes(key);
                if b.TBSBits~=ctx.TBSBits || ~isequaln(b.NDI,sixgr.util.structGet(h,'NDI',NaN))
                    error('sixgr:system:TransportBlockMutation','Retransmission changed TBS or NDI.');
                end
            else
                if isKey(obj.Processes,key)
                    old=obj.Processes(key); previous=old.ID;
                    sixgr.system.waveform.harqSoftBufferCache("clear",old.SoftBufferKey);
                end
                obj.Sequence=obj.Sequence+1;
                b=struct('ID',obj.Namespace+"/"+string(obj.Sequence), ...
                    'TBSBits',ctx.TBSBits,'NDI',sixgr.util.structGet(h,'NDI',NaN), ...
                    'FirstTTI',double(sixgr.util.structGet(ctx,'TTI',1)), ...
                    'Bits',int8([]));
                if obj.MaterializeBits
                    b.Bits=int8(randi(obj.Stream,[0 1],ctx.TBSBits,1));
                end
            end
            b.LastTTI=double(sixgr.util.structGet(ctx,'TTI',1));
            b.SoftBufferKey=upper(string(ctx.Direction))+"|tb="+b.ID+"|tbs="+string(b.TBSBits);
            obj.Processes(key)=b;
            ctx.TransportBlockIdentity=b.ID;
            ctx.TransportBlockBits=b.Bits;
            ctx.Grant.TransportBlockIdentity=b.ID;
            ctx.IsRetransmission=retx;
        end
        function delete(obj)
            % A censored final TB is not delivered or abandoned here. Only
            % release its decoder memory; retain file censoring in exports.
            % Never reset the global cache: other runs own different keys.
            if isempty(obj.Processes), return; end
            entries=values(obj.Processes);
            for k=1:numel(entries)
                sixgr.system.waveform.harqSoftBufferCache("clear",entries{k}.SoftBufferKey);
            end
        end
        function dropped=terminalDrops(obj,direction,cellID,ledger,tti)
            dropped=struct('ID',{},'UEID',{},'TBSBits',{});
            if isempty(ledger), return; end
            rows=find(string(ledger.Status)=="max_retx_drop" & ledger.AttemptSlot==tti-1);
            for n=rows(:).'
                key=char(join([string(direction),string(cellID),string(ledger.RNTI(n)), ...
                    string(ledger.HARQProcessId(n))],'|'));
                if ~isKey(obj.Processes,key)
                    error('sixgr:system:UnknownDroppedTB','HARQ dropped a TB without a runtime payload identity.');
                end
                b=obj.Processes(key);
                assert(b.FirstTTI==ledger.ScheduleSlot(n)+1 && b.LastTTI==tti, ...
                    'sixgr:system:DroppedTBIdentity','HARQ drop refers to another TB generation.');
                dropped(end+1)=struct('ID',b.ID,'UEID',double(ledger.RNTI(n)),'TBSBits',b.TBSBits); %#ok<AGROW>
            end
        end
    end
end
