classdef IdealDelayedHARQ < handle
    %IDEALDELAYEDHARQ Research clock adapter around the production HARQ entity.
    % Feedback is an explicitly ideal delayed receiver-CRC event. No PUCCH or
    % PDCCH waveform is claimed. Receiver soft state is separate from TX TBs.
    properties (SetAccess=private)
        Entity
        Direction
        RNTI
        DelaySlots
        LastClock = -1
        Queue = struct([])
        Feedback = struct([])
        ReceiverState
        ReceivedAttempts
        TransmitConfigurations
    end
    methods
        function obj=IdealDelayedHARQ(s,direction)
            obj.Direction=upper(string(direction));
            p=s.("research_"+lower(obj.Direction)); h=s.research_harq;
            assert(p.harq_enabled && s.harq.enabled && string(h.feedback_mode)=="ideal_delayed", ...
                'sixgr:research:HARQOptInRequired','Explicit ideal-delayed HARQ opt-in is required.');
            obj.RNTI=p.rnti; obj.DelaySlots=h.feedback_delay_slots;
            obj.Entity=sixgr.l2.mac.HARQEntity(struct(),'Direction',obj.Direction, ...
                'NumProcesses',h.num_processes,'MaxRetx',h.max_transmissions-1, ...
                'RVSequence',h.rv_sequence,'StoreTB',true);
            obj.ReceiverState=cell(1,h.num_processes);
            obj.TransmitConfigurations=cell(1,h.num_processes);
            obj.ReceivedAttempts=containers.Map('KeyType','char','ValueType','logical');
        end

        function advance(obj,slot)
            validateattributes(slot,{'numeric'},{'scalar','integer','nonnegative','finite'});
            assert(slot>=obj.LastClock,'sixgr:research:HARQClockReversed','HARQ clock cannot move backwards.');
            obj.LastClock=slot;
            if isempty(obj.Queue), return; end
            due=find([obj.Queue.AvailableSlot]<=slot);
            for k=due
                e=obj.Queue(k);
                applied=obj.Entity.onFeedback(obj.RNTI,e.HARQProcessId,e.CRCPass, ...
                    'SourceSlot',e.SourceSlot,'FeedbackSlot',slot);
                assert(applied,'sixgr:research:HARQFeedbackRejected', ...
                    'An owned ideal-feedback event must match its outstanding transmitted attempt.');
                e.DeliveredAtSlot=slot;
                if isempty(obj.Feedback), obj.Feedback=e; else, obj.Feedback(end+1)=e; end
                proc=obj.Entity.UEProcs{1}(e.HARQProcessId+1);
                if ~proc.Active
                    obj.ReceiverState{e.HARQProcessId+1}=[];
                    obj.TransmitConfigurations{e.HARQProcessId+1}=[];
                end
            end
            obj.Queue(due)=[];
        end

        function [plan,tb,attemptConfig]=reserve(obj,s,slot,allowNew)
            if nargin<4, allowNew=true; end
            assert(slot==obj.LastClock,'sixgr:research:HARQClockNotAdvanced', ...
                'Deliver available feedback before scheduling this slot.');
            a=sixgr.phy.research.SharedChannelLink.allocation(s,slot,obj.Direction);
            allocation=obj.Entity.allocate(obj.RNTI,slot,a.TransportBlockSize/8,'NewData',allowNew);
            plan=struct(); tb=[]; attemptConfig=s;
            if allocation.NoFreeProcess || isempty(allocation.ProcessIndex), return; end
            h=allocation.HARQ;
            key=obj.Direction+"_rnti"+obj.RNTI+"_pid"+h.HarqID+"_epoch"+h.NDIEpoch;
            section="research_"+lower(obj.Direction);
            if h.IsRetransmission
                retained=obj.TransmitConfigurations{h.HarqID+1};
                assert(~isempty(retained) && retained.HARQKey==key, ...
                    'sixgr:research:MissingHARQConfiguration', ...
                    'Retransmission requires the original TB-epoch configuration.');
                % New-data adaptation must never change an outstanding TB's
                % rank, modulation, coding, DMRS or physical port allocation.
                attemptConfig=retained.Config;
            else
                obj.TransmitConfigurations{h.HarqID+1}=struct('HARQKey',key,'Config',s);
            end
            attemptConfig.(section).rv=h.RV;
            a=sixgr.phy.research.SharedChannelLink.allocation(attemptConfig,slot,obj.Direction);
            if h.IsRetransmission
                tb=int8(obj.Entity.getStoredTB(obj.RNTI,h.HarqID));
                assert(numel(tb)==a.TransportBlockSize, ...
                    'sixgr:research:HARQAllocationChanged','Retransmission must retain its original TB size.');
            else
                tb=int8(randi([0 1],a.TransportBlockSize,1));
                obj.ReceiverState{h.HarqID+1}=[];
            end
            plan=struct('HARQKey',key,'AbsoluteSlot',slot,'HARQ',h,'Allocation',a);
        end

        function transmitted(obj,plan,tx)
            a=plan.Allocation;
            proc=obj.Entity.UEProcs{1}(plan.HARQ.HarqID+1);
            assert(~proc.AwaitingFeedback && proc.NDIEpoch==plan.HARQ.NDIEpoch, ...
                'sixgr:research:DuplicateHARQTransmission','Do not execute an outstanding attempt twice.');
            assert(tx.HARQKey==plan.HARQKey && ...
                tx.Allocation.AbsoluteSlot==plan.AbsoluteSlot && ...
                tx.Allocation.RV==plan.HARQ.RV && ~isempty(tx.Waveform), ...
                'sixgr:research:HARQTransmitEvidenceMismatch','Retain the actually generated coded attempt.');
            g=struct('Direction',obj.Direction,'RNTI',obj.RNTI,'Slot',plan.AbsoluteSlot, ...
                'HARQ',plan.HARQ,'TransportBlockId',plan.HARQKey, ...
                'TBSBits',a.TransportBlockSize,'Modulation',a.Modulation, ...
                'TargetCodeRate',a.TargetCodeRate,'NumLayers',a.NumLayers, ...
                'PRBSet',a.ReferenceGeometry.PRBSet,'SymbolAllocation',a.ReferenceGeometry.SymbolAllocation, ...
                'CodingLayout',a.CodingLayout,'LayerDataRE',a.LayerDataRE);
            obj.Entity.onTx(obj.RNTI,plan.HARQ.HarqID,uint8(tx.TransportBlock),g,plan.AbsoluteSlot);
        end

        function options=receiveOptions(obj,plan)
            prior=obj.ReceiverState{plan.HARQ.HarqID+1};
            soft=[]; layout=struct();
            if ~isempty(prior)
                assert(prior.HARQKey==plan.HARQKey, ...
                    'sixgr:research:HARQReceiverIdentityMismatch','Never combine across TB/process epochs.');
                soft=prior.SoftBuffer; layout=prior.CodingLayout;
            end
            options={'HARQKey',plan.HARQKey,'HARQSoftBuffer',soft,'PriorCodingLayout',layout};
        end

        function received(obj,plan,rx)
            assert(rx.HARQKey==plan.HARQKey && rx.Allocation.AbsoluteSlot==plan.AbsoluteSlot && ...
                rx.Allocation.RV==plan.HARQ.RV, ...
                'sixgr:research:HARQReceiveEvidenceMismatch','CRC feedback must belong to this received attempt.');
            attemptKey=char(plan.HARQKey+"_slot"+plan.AbsoluteSlot);
            assert(~isKey(obj.ReceivedAttempts,attemptKey), ...
                'sixgr:research:DuplicateHARQReception','Do not publish the same received attempt twice.');
            proc=obj.Entity.UEProcs{1}(plan.HARQ.HarqID+1);
            assert(proc.AwaitingFeedback && proc.LastTxSlot==plan.AbsoluteSlot, ...
                'sixgr:research:HARQReceiveBeforeTransmit','Feedback requires the corresponding executed transmission.');
            obj.ReceivedAttempts(attemptKey)=true;
            obj.ReceiverState{plan.HARQ.HarqID+1}=struct('HARQKey',plan.HARQKey, ...
                'SoftBuffer',rx.HARQSoftBuffer,'CodingLayout',rx.Allocation.CodingLayout);
            e=struct('Direction',obj.Direction,'TBID',plan.HARQKey, ...
                'HARQProcessId',plan.HARQ.HarqID,'SourceSlot',plan.AbsoluteSlot, ...
                'AvailableSlot',plan.AbsoluteSlot+obj.DelaySlots,'DeliveredAtSlot',NaN, ...
                'AttemptIndex',plan.HARQ.HARQRound+1, ...
                'NumLayers',plan.Allocation.NumLayers,'Modulation',plan.Allocation.Modulation, ...
                'MeasuredNoiseVariance',rx.NoiseVariance, ...
                'CRCPass',logical(rx.CRCPass),'FeedbackMode',"ideal_delayed_receiver_CRC");
            if isempty(obj.Queue), obj.Queue=e; else, obj.Queue(end+1)=e; end
        end

        function count=pendingCount(obj)
            count=0;
            if ~isempty(obj.Entity.UEProcs), count=sum([obj.Entity.UEProcs{1}.Active]); end
        end
    end
end
