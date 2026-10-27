classdef PDCPDiscardTimerState
    % TS38.323 V18.5.0 5.2.1/5.3: original TX SDU timers, not RX expiry.
    % The adapter authenticates lower-layer delivery and discard results.
    properties (SetAccess=private)
        SampleRateHz double
        ClockEpoch double
        DiscardSamples double
        LastSample double=0
        Records cell={}
        Active logical=true
    end
    methods
        function obj=PDCPDiscardTimerState(fs,epoch,duration)
            assert(isscalar(fs)&&isfinite(fs)&&fs>0&&fs==fix(fs)&& ...
                isscalar(epoch)&&isfinite(epoch)&&epoch>=0&&epoch==fix(epoch)&& ...
                isscalar(duration)&&isfinite(duration)&&duration>0, ...
                'sixgr:pdcp:DiscardClock','Explicit original sample clock and finite positive discard duration required.');
            samples=duration*fs;
            assert(abs(samples-round(samples))<=max(1e-7,8*eps(samples))&&round(samples)>0, ...
                'sixgr:pdcp:DiscardClock','Discard duration must align to the original sample clock.');
            obj.SampleRateHz=fs;obj.ClockEpoch=epoch;obj.DiscardSamples=round(samples);
        end
        function next=retain(obj,count,sdu,pdu,sample)
            obj.validateSample(sample);
            assert(obj.Active&&isscalar(count)&&isfinite(count)&&count>=0&&count<=2^32-1&&count==fix(count)&& ...
                isa(sdu,'uint8')&&isrow(sdu)&&~isempty(sdu)&&isa(pdu,'uint8')&&isrow(pdu)&&~isempty(pdu), ...
                'sixgr:pdcp:DiscardIdentity','Original full COUNT and SDU/PDU octets required.');
            assert(isempty(obj.index(count)),'sixgr:pdcp:DiscardIdentity','A COUNT cannot restart its original discard timer.');
            row=struct('PDCPCount',count,'EnqueueSample',sample,'DeadlineSample',sample+obj.DiscardSamples, ...
                'SDUBytes',sdu,'PDUBytes',pdu,'SDUSHA256',sixgr.protocol.ProtocolHash.bytes(sdu), ...
                'PDUSHA256',sixgr.protocol.ProtocolHash.bytes(pdu),'Status',"pending");
            next=obj;next.Records{end+1}=row;next.LastSample=sample;
        end
        function [next,expired]=advance(obj,sample)
            obj.validateSample(sample);next=obj;next.LastSample=sample;expired=struct([]);
            if ~obj.Active,return;end
            for k=1:numel(obj.Records)
                r=obj.Records{k};
                if r.Status~="pending"||r.DeadlineSample>sample,continue;end
                e=struct('PDCPCount',r.PDCPCount,'EnqueueSample',r.EnqueueSample, ...
                    'DeadlineSample',r.DeadlineSample,'ObservedAtSample',sample, ...
                    'SampleRateHz',obj.SampleRateHz,'ClockEpoch',obj.ClockEpoch, ...
                    'SDUSHA256',r.SDUSHA256,'PDUSHA256',r.PDUSHA256, ...
                    'Source',"original_PDCP_TX_discard_timer",'ApplicationBytesDropped',0);
                if isempty(expired),expired=e;else,expired(end+1)=e;end %#ok<AGROW>
                r.Status="expired";r.SDUBytes=uint8([]);r.PDUBytes=uint8([]);next.Records{k}=r;
            end
        end
        function [next,disposition]=confirmLowerLayerDelivery(obj,count,pduHash,sample)
            obj.validateSample(sample);idx=obj.index(count);
            assert(isscalar(idx)&&strlength(string(pduHash))==64&&obj.Records{idx}.PDUSHA256==string(pduHash), ...
                'sixgr:pdcp:DiscardIdentity','Original lower-layer-confirmed PDU COUNT/hash required.');
            next=obj;next.LastSample=sample;r=obj.Records{idx};
            if r.Status=="expired",disposition="delivery_confirmation_after_TX_discard";return;end
            if r.Status=="acknowledged",disposition="duplicate_lower_layer_confirmation";return;end
            % A late callback cannot move an earlier timer deadline. Its
            % expiry is processed by advance before any new confirmation.
            assert(sample<r.DeadlineSample,'sixgr:pdcp:UnprocessedDiscardExpiry', ...
                'Advance the original TX clock before processing a late confirmation.');
            r.Status="acknowledged";r.SDUBytes=uint8([]);r.PDUBytes=uint8([]);next.Records{idx}=r;
            disposition="original_lower_layer_delivery_confirmed";
        end
        function sample=nextTimerExpiry(obj)
            sample=inf;if ~obj.Active,return;end
            for r=obj.Records,if r{1}.Status=="pending",sample=min(sample,r{1}.DeadlineSample);end,end
        end
        function next=release(obj)
            next=obj;next.Active=false;next.Records={};
        end
    end
    methods (Access=private)
        function validateSample(obj,sample)
            assert(isscalar(sample)&&isfinite(sample)&&sample>=obj.LastSample&&sample==fix(sample), ...
                'sixgr:pdcp:DiscardClock','Original TX sample clock must be monotonic.');
        end
        function idx=index(obj,count)
            idx=find(cellfun(@(r)r.PDCPCount==count,obj.Records));
        end
    end
end
