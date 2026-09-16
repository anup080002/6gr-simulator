classdef BSRStateMachine < handle
    %BSRSTATEMACHINE Base (non-extended) BSR declared-event state.
    % The MAC owner supplies LCP triggers, post-LCP buffers and actual TX
    % callbacks. Preparing bytes is not evidence of physical transmission.
    properties (SetAccess=private)
        UEID (1,1) double
        Buffers (1,:) double
        PendingTrigger (1,1) string = "none"
        PeriodicTimer (1,1) double
        RetxTimer (1,1) double
        LastReportSlot (1,1) double = NaN
        PeriodicExpirySlot (1,1) double = NaN
        RetxExpirySlot (1,1) double = NaN
        CurrentSlot (1,1) double = 0
    end
    properties (Access=private)
        TriggerSequence (1,1) double = 0
        PreparationSequence (1,1) double = 0
        PendingSequences (1,3) double = zeros(1,3)
        PreparedReports
    end
    methods
        function obj=BSRStateMachine(ueID,numLCG,periodicSlots,retxSlots)
            arguments
                ueID (1,1) double {mustBeFinite,mustBeInteger,mustBeNonnegative}
                numLCG (1,1) double {mustBeFinite,mustBeInteger,mustBePositive}
                periodicSlots (1,1) double {mustBeFinite,mustBeInteger,mustBePositive}
                retxSlots (1,1) double {mustBeFinite,mustBeInteger,mustBePositive}
            end
            assert(numLCG<=8,'sixgr:mac:InvalidLCGBufferMap','Base BSR supports at most eight LCGs.');
            obj.UEID=ueID; obj.Buffers=zeros(1,numLCG);
            obj.PeriodicTimer=periodicSlots; obj.RetxTimer=retxSlots;
            obj.PreparedReports=containers.Map('KeyType','char','ValueType','any');
        end
        function arrival(obj,lcgID,bytes)
            obj.validateBufferChange(lcgID,bytes);
            wasEmpty=sum(obj.Buffers)==0;
            total=obj.Buffers(lcgID+1)+double(bytes);
            assert(total<=flintmax,'sixgr:mac:InvalidLCGBufferMap','Buffer bytes exceed exact integer range.');
            obj.Buffers(lcgID+1)=total;
            if bytes>0 && wasEmpty, obj.trigger("regular"); end
        end
        function dequeue(obj,lcgID,bytes)
            obj.validateBufferChange(lcgID,bytes);
            assert(bytes<=obj.Buffers(lcgID+1),'sixgr:mac:BSRBufferUnderflow','Cannot remove unavailable buffer bytes.');
            obj.Buffers(lcgID+1)=obj.Buffers(lcgID+1)-double(bytes);
        end
        function trigger(obj,kind)
            kind=lower(string(kind));
            if ~isscalar(kind) || ~ismember(kind,["regular","periodic","retx","padding"])
                error("sixgr:mac:InvalidBSRTrigger","Unknown BSR trigger.");
            end
            if kind=="retx", kind="regular"; end
            obj.TriggerSequence=obj.TriggerSequence+1;
            obj.PendingSequences(["regular","periodic","padding"]==kind)=obj.TriggerSequence;
            obj.refreshTrigger();
        end
        function advanceTo(obj,slot)
            validateattributes(slot,{'numeric'},{'scalar','real','finite','integer','>=',obj.CurrentSlot});
            obj.CurrentSlot=slot;
            if slot>=obj.PeriodicExpirySlot
                obj.PeriodicExpirySlot=NaN;
                obj.trigger("periodic");
            end
            if slot>=obj.RetxExpirySlot
                obj.RetxExpirySlot=NaN;
                if any(obj.Buffers>0), obj.trigger("regular"); end
            end
        end
        function receivedNewDataGrant(obj,slot)
            % Called on received/determined new-data grant, not gNB intent.
            obj.advanceTo(slot);
            obj.RetxExpirySlot=obj.CurrentSlot+obj.RetxTimer;
        end
        function decision=buildReport(obj,grantBytes,slot,priorities)
            % grantBytes is the CE allowance AFTER LCP, including subheader.
            % 38.321 5.4.5 starts timers at CE generation, but cancellation
            % depends on transmission and coverage of the triggering events.
            if nargin<4, priorities=struct(); end
            validateattributes(grantBytes,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
            obj.advanceTo(slot);
            slot=obj.CurrentSlot;
            decision=struct("Transmit",false,"Format","none","Indices",[]);
            if obj.PendingTrigger=="none", return; end
            if obj.PendingTrigger=="padding"
                ce=sixgr.l2.mac.BSR_PHR.buildBSR(obj.Buffers,grantBytes,priorities);
                if isempty(ce), return; end
            else
                active=find(obj.Buffers>0)-1;
                if numel(active)<=1
                    if isempty(active), active=0; end
                    payload=sixgr.l2.mac.BSR_PHR.encodeShortBSR(active,obj.Buffers(active+1));
                    ce=struct('LCID',61,'Payload',payload,'Format',"short",'Truncated',false);
                else
                    ce=struct('LCID',62,'Payload',sixgr.l2.mac.BSR_PHR.encodeLongBSR(obj.Buffers), ...
                        'Format',"long",'Truncated',false);
                end
                header=sixgr.l2.mac.MACSubheaderCodec.encode('UL',ce.LCID,numel(ce.Payload));
                ce.MACSubPDUBytes=numel(header)+numel(ce.Payload);
                % Regular/periodic BSR cannot use padding truncation rules.
                if grantBytes<ce.MACSubPDUBytes, return; end
            end
            decoded=sixgr.l2.mac.BSR_PHR.decodeBSR(ce.LCID,ce.Payload,priorities);
            selected=find(decoded.BufferSizeFieldPresent);
            % Equal payloads can belong to distinct MAC-PDU preparations.
            % This local serial is not physical TX or configuration-epoch
            % authority; those bindings remain the coordinator's duty.
            assert(obj.PreparationSequence<flintmax, ...
                'sixgr:mac:BSRPreparationIdentityExhausted', ...
                'A BSR preparation identity must remain an exact integer.');
            obj.PreparationSequence=obj.PreparationSequence+1;
            decision=struct("Transmit",true,"Format",string(ce.Format), ...
                "LCGIDs",selected-1,"Indices",decoded.BufferSizeIndices(selected), ...
                "TableID",decoded.TableID,"Trigger",obj.PendingTrigger, ...
                "LCID",ce.LCID,"Payload",ce.Payload,"MACSubPDUBytes",ce.MACSubPDUBytes, ...
                "Truncated",ce.Truncated,"UEID",obj.UEID,"PreparedSlot",slot, ...
                "PreparationSequence",obj.PreparationSequence, ...
                "CoveredTriggerSequence",obj.TriggerSequence);
            decision.ReportID=sixgr.l2.mac.MACHash.of(decision);
            obj.PreparedReports(char(decision.ReportID))=decision;
            if ~ce.Truncated, obj.PeriodicExpirySlot=slot+obj.PeriodicTimer; end
            obj.RetxExpirySlot=slot+obj.RetxTimer;
        end
        function recordTransmission(obj,report,slot)
            % The normal coordinator must call this from actual TX evidence.
            % This helper validates identity/ordering, not an RF observation.
            key=obj.requirePreparation(report);
            validateattributes(slot,{'numeric'},{'scalar','real','finite','integer','>=',report.PreparedSlot});
            obj.advanceTo(slot);
            if ~report.Truncated
                obj.PendingSequences(obj.PendingSequences<=report.CoveredTriggerSequence)=0;
                obj.refreshTrigger();
            end
            obj.LastReportSlot=slot;
            remove(obj.PreparedReports,key);
        end
        function discardReport(obj,report)
            % Aborted/unqueued preparation does not cancel any trigger.
            key=obj.requirePreparation(report);
            remove(obj.PreparedReports,key);
        end
    end
    methods (Access=private)
        function refreshTrigger(obj)
            kinds=["regular","periodic","padding"];
            index=find(obj.PendingSequences>0,1);
            obj.PendingTrigger="none";
            if ~isempty(index), obj.PendingTrigger=kinds(index); end
        end
        function key=requirePreparation(obj,report)
            assert(isstruct(report) && isscalar(report) && isfield(report,'ReportID') && ...
                isstring(report.ReportID) && isscalar(report.ReportID), ...
                'sixgr:mac:UnknownBSRPreparation','An owned BSR preparation is required.');
            key=char(report.ReportID);
            assert(isKey(obj.PreparedReports,key),'sixgr:mac:UnknownBSRPreparation', ...
                'BSR preparation is unknown, discarded, or already transmitted.');
            assert(isequaln(obj.PreparedReports(key),report),'sixgr:mac:BSRPreparationMismatch', ...
                'Prepared BSR identity, payload and trigger coverage are immutable.');
        end
        function validateBufferChange(obj,lcgID,bytes)
            validateattributes(lcgID,{'numeric'},{'scalar','real','finite','integer','>=',0,'<',numel(obj.Buffers)});
            validateattributes(bytes,{'numeric'},{'scalar','real','finite','integer','nonnegative','<=',flintmax});
        end
    end
end
