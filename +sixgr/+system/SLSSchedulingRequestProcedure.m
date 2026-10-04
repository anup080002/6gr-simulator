classdef SLSSchedulingRequestProcedure < handle
    % Per-UE/per-SR-ID MAC state for explicitly modeled SLS control.
    % TS 38.321 5.4.4: planning is not transmission; SR stays pending after TX.
    % The traffic/MAC owner supplies triggers and qualified cancellation events.
    properties (SetAccess=private)
        Identity struct
        Policy struct
        Pending (1,1) logical = false
        Counter (1,1) double = 0
        TriggerSequence (1,1) double = 0
        ProhibitUntilSlot0 (1,1) double = 0
        CurrentSlot0 (1,1) double = 0
        RequiresRandomAccess (1,1) logical = false
        Trace table = table()
    end
    properties (Access=private)
        LastTransmissionSlot0 (1,1) double = -1
        TriggerIDs string = strings(0,1)
    end
    methods
        function obj=SLSSchedulingRequestProcedure(identity,policy)
            required={'UEIndex','RNTI','CellID','SchedulingRequestID'};
            assert(isstruct(identity) && isscalar(identity) && all(isfield(identity,required)), ...
                'sixgr:system:MissingSRIdentity','Install explicit UE, RNTI, cell and SR identity.');
            for field=required
                validateattributes(identity.(field{1}),{'numeric'},{'scalar','real','finite','integer','nonnegative'});
            end
            assert(identity.UEIndex>0 && identity.CellID>0 && identity.RNTI>0 && identity.RNTI<=65535, ...
                'sixgr:system:MissingSRIdentity','Invalid configured UE/cell/RNTI.');
            assert(isstruct(policy) && isscalar(policy) && ...
                all(isfield(policy,{'ProhibitTimerSlots','MaxTransmissions'})), ...
                'sixgr:system:MissingSRPolicy','Provide resolved SR timer and transmission limit.');
            validateattributes(policy.ProhibitTimerSlots,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
            validateattributes(policy.MaxTransmissions,{'numeric'},{'scalar','real','finite','integer','positive'});
            obj.Identity=identity; obj.Policy=policy;
        end
        function trigger(obj,slot,eventID)
            obj.validateClock(slot); eventID=string(eventID);
            assert(isscalar(eventID) && ~ismissing(eventID) && strlength(eventID)>0, ...
                'sixgr:system:MissingSRTrigger','A MAC trigger needs its owned event identity.');
            assert(~ismember(eventID,obj.TriggerIDs),'sixgr:system:DuplicateSRTrigger','Do not replay a trigger.');
            assert(~obj.RequiresRandomAccess,'sixgr:system:SRRandomAccessRequired', ...
                'Complete the declared recovery/reconfiguration before new SR triggers.');
            obj.CurrentSlot0=slot;
            obj.TriggerIDs(end+1)=eventID; obj.TriggerSequence=obj.TriggerSequence+1;
            if ~obj.Pending, obj.Counter=0; end
            obj.Pending=true; obj.append("trigger",eventID);
        end
        function state=project(obj,slot)
            % Read-only projection: repeated/future planning consumes nothing.
            obj.validateClock(slot);
            state=struct('Identity',obj.Identity,'AbsoluteSlot0',slot, ...
                'TriggerSequence',obj.TriggerSequence,'Pending',obj.Pending, ...
                'Counter',obj.Counter,'ProhibitUntilSlot0',obj.ProhibitUntilSlot0, ...
                'MayTransmit',obj.Pending && ~obj.RequiresRandomAccess && ...
                    slot>=obj.ProhibitUntilSlot0 && obj.Counter<obj.Policy.MaxTransmissions, ...
                'RequiresRandomAccess',obj.RequiresRandomAccess || (obj.Pending && ...
                    slot>=obj.ProhibitUntilSlot0 && obj.Counter>=obj.Policy.MaxTransmissions), ...
                'Source',"modeled_MAC_SR_state_not_physical_reception");
        end
        function commitTransmission(obj,snapshot,eventID)
            assert(isstruct(snapshot) && isscalar(snapshot) && isfield(snapshot,'AbsoluteSlot0'), ...
                'sixgr:system:InvalidSRTransmission','Retain the prepared procedure snapshot.');
            current=obj.project(snapshot.AbsoluteSlot0);
            assert(isequaln(current,snapshot),'sixgr:system:StaleSRTransmission', ...
                'Pending state changed after preparation; do not transmit stale SR state.');
            eventID=string(eventID);
            assert(isscalar(eventID) && ~ismissing(eventID) && strlength(eventID)>0, ...
                'sixgr:system:InvalidSRTransmission','An actual modeled TX needs an event identity.');
            assert(snapshot.MayTransmit && snapshot.AbsoluteSlot0~=obj.LastTransmissionSlot0, ...
                'sixgr:system:InvalidSRTransmission','No prohibited, repeated or exhausted SR transmission.');
            obj.CurrentSlot0=snapshot.AbsoluteSlot0; obj.LastTransmissionSlot0=obj.CurrentSlot0;
            obj.Counter=obj.Counter+1;
            obj.ProhibitUntilSlot0=obj.CurrentSlot0+obj.Policy.ProhibitTimerSlots;
            obj.append("modeled_positive_SR_transmitted",eventID);
        end
        function cancelForGrant(obj,slot,capacityBytes,pendingNewDataBytes,eventID)
            % Capacity is MAC payload capacity AFTER overhead/LCP, not raw TBS.
            obj.validateClock(slot);
            validateattributes(capacityBytes,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
            validateattributes(pendingNewDataBytes,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
            assert(capacityBytes>=pendingNewDataBytes, ...
                'sixgr:system:SRGrantDoesNotCoverPendingData','An arbitrary/partial UL grant cannot cancel SR.');
            obj.cancel(slot,"all_pending_data_accommodated",eventID);
        end
        function cancelForTransmittedBSR(obj,slot,coveredSequence,format,eventID)
            obj.validateClock(slot);
            validateattributes(coveredSequence,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
            assert(coveredSequence==obj.TriggerSequence && ...
                isscalar(string(format)) && any(string(format)==["short","long"]), ...
                'sixgr:system:SRBSRDoesNotCoverTrigger', ...
                'Only an actually transmitted nontruncated BSR covering all owned triggers cancels SR.');
            obj.cancel(slot,"qualifying_BSR_transmitted",eventID);
        end
        function requireRecovery(obj,slot)
            state=obj.project(slot);
            assert(state.RequiresRandomAccess,'sixgr:system:PrematureSRRecovery', ...
                'Recovery is required only after the configured counter and prohibit interval.');
            obj.CurrentSlot0=slot; obj.RequiresRandomAccess=true; obj.Pending=false;
            obj.ProhibitUntilSlot0=slot;
            obj.append("random_access_required_not_executed","sr_transmission_limit");
            % The network owner must release/reconfigure resources and execute
            % recovery. This event is not successful RA or a fabricated grant.
        end
    end
    methods (Access=private)
        function validateClock(obj,slot)
            validateattributes(slot,{'numeric'},{'scalar','real','finite','integer','>=',obj.CurrentSlot0});
        end
        function cancel(obj,slot,reason,eventID)
            eventID=string(eventID);
            assert(isscalar(eventID) && ~ismissing(eventID) && strlength(eventID)>0, ...
                'sixgr:system:MissingSRCancellationEvidence','Cancellation needs its owned grant or TX identity.');
            assert(~obj.RequiresRandomAccess,'sixgr:system:SRRandomAccessRequired', ...
                'Cancellation must not silently undo a requested recovery.');
            obj.CurrentSlot0=slot; obj.Pending=false; obj.ProhibitUntilSlot0=slot;
            obj.append(reason,eventID);
        end
        function append(obj,event,eventID)
            id=obj.Identity;
            row=table(id.UEIndex,id.RNTI,id.CellID,id.SchedulingRequestID, ...
                obj.CurrentSlot0,string(event),string(eventID),obj.TriggerSequence, ...
                obj.Pending,obj.Counter,obj.ProhibitUntilSlot0,obj.RequiresRandomAccess, ...
                "modeled_MAC_procedure_not_physical_SR_decode",false, ...
                'VariableNames',{'UEIndex','RNTI','CellID','SchedulingRequestID', ...
                'AbsoluteSlot0','Event','EventID','TriggerSequence','Pending','Counter', ...
                'ProhibitUntilSlot0','RequiresRandomAccess','Source','WaveformBacked'});
            obj.Trace=[obj.Trace;row];
        end
    end
end
