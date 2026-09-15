classdef BroadcastResultDelivery
%BROADCASTRESULTDELIVERY Keep decoded observations private until their end time.
% This is a result-delivery boundary, not a channel executor. In particular,
% queuing an eagerly computed result does not make eager channel execution
% causal. The sample composer/receiver dispatcher must still own that clock.
    methods(Static)
        function state=enqueue(state,ueIdx,trial,recovery,trackingOnly)
            validateattributes(ueIdx,{'numeric'},{'scalar','integer','positive', ...
                '<=',state.NumUsers});
            validateattributes(trackingOnly,{'logical'},{'scalar'});
            if ~istable(trial)||isempty(trial)||~isstruct(recovery)||~isscalar(recovery)
                error("sixgr:truth:InvalidBroadcastResult","A broadcast needs receiver rows and one decoded recovery structure.");
            end
            required=["ObservationStartSample","ObservationEndSampleExclusive", ...
                "ObservationSampleRateHz","ObservationCompletionTime_s", ...
                "ObservationCoverageSource","Slot"];
            if ~all(ismember(required,string(trial.Properties.VariableNames)))
                error("sixgr:truth:MissingBroadcastObservationClock", ...
                    "Coupled broadcast delivery requires the receiver's actual sample-window evidence.");
            end
            for name=required([1:4 6])
                values=trial.(name);
                if ~isnumeric(values)||~isreal(values)||size(values,2)~=1|| ...
                        any(~isfinite(values))||any(values~=values(1))
                    error("sixgr:truth:InvalidBroadcastObservationClock", ...
                        "Every candidate must belong to the same finite received broadcast window.");
                end
            end
            first=double(trial.ObservationStartSample(1));
            last=double(trial.ObservationEndSampleExclusive(1));
            fs=double(trial.ObservationSampleRateHz(1));
            completion=double(trial.ObservationCompletionTime_s(1));
            sourceSlot=double(trial.Slot(1));
            validateattributes(state.SlotDuration_s,{'numeric'}, ...
                {'scalar','finite','positive'});
            if first<0||first~=fix(first)||last<=first||last~=fix(last)|| ...
                    fs<=0||completion~=last/fs|| ...
                    sourceSlot<1||sourceSlot~=fix(sourceSlot)|| ...
                    first~=round((sourceSlot-1)*double(state.SlotDuration_s)*fs)|| ...
                    any(string(trial.ObservationCoverageSource)~= ...
                    "complete_contiguous_received_sample_buffer")
                error("sixgr:truth:InvalidBroadcastObservationClock", ...
                    "Broadcast availability and source slot must match the actual complete capture's sample clock.");
            end
            pending=sixgr.truth.BroadcastResultDelivery.pending(state);
            if any([pending.UEIndex]==ueIdx)
                error("sixgr:truth:DuplicatePendingBroadcast", ...
                    "UE %d already has an undelivered broadcast observation.",ueIdx);
            end
            item=struct("UEIndex",double(ueIdx),"Trial",trial, ...
                "Recovery",recovery,"TrackingOnly",trackingOnly, ...
                "CompletionTime_s",completion);
            state.PendingBroadcastResults=[pending;item];
        end

        function tf=hasPending(state,ueIdx)
            items=sixgr.truth.BroadcastResultDelivery.pending(state);
            tf=any([items.UEIndex]==ueIdx);
        end

        function [state,ready]=takeAvailable(state)
            validateattributes(state.CurrentSlot,{'numeric'}, ...
                {'scalar','finite','integer','positive'});
            validateattributes(state.SlotDuration_s,{'numeric'}, ...
                {'scalar','finite','positive'});
            % Called at the canonical slot-start boundary, before consumers.
            now_s=(double(state.CurrentSlot)-1)*double(state.SlotDuration_s);
            items=sixgr.truth.BroadcastResultDelivery.pending(state);
            due=[items.CompletionTime_s]<=now_s;
            ready=items(due);
            [~,order]=sort([ready.CompletionTime_s]);
            ready=ready(order);
            for k=1:numel(ready)
                n=height(ready(k).Trial);
                ready(k).Trial.ObservationDeliverySlot=repmat(double(state.CurrentSlot),n,1);
                ready(k).Trial.ObservationDeliveryTime_s=repmat(now_s,n,1);
                ready(k).Trial.ObservationDeliverySource=repmat( ...
                    "canonical_slot_start_after_complete_received_window",n,1);
                if ismember('MeasurementClockEpoch',ready(k).Trial.Properties.VariableNames)
                    ready(k).Trial=sixgr.truth.bindSharedReferenceDeliveryClock(ready(k).Trial,state);
                end
            end
            state.PendingBroadcastResults=items(~due);
        end

        function state=censorAtSweepBoundary(state)
            items=sixgr.truth.BroadcastResultDelivery.pending(state);
            if ~isempty(items)
                if ~isfield(state,"CensoredBroadcastResults")
                    state.CensoredBroadcastResults=cell(0,1);
                end
                state.CensoredBroadcastResults{end+1,1}=struct( ...
                    "Reason","independent_snr_point_boundary_before_delivery", ...
                    "Results",items);
            end
            state.PendingBroadcastResults=sixgr.truth.BroadcastResultDelivery.empty();
        end

        function slot=deliverySlot(state,trial)
            slot=double(state.CurrentSlot);
            if ismember("Slot",string(trial.Properties.VariableNames))
                slot=double(trial.Slot(end));
            end
            if ~ismember("ObservationEndSampleExclusive",string(trial.Properties.VariableNames))|| ...
                    all(isnan(trial.ObservationEndSampleExclusive))
                % Legacy single-trial fixtures carry no multi-slot capture.
                % The coupled delivery queue does not accept such rows.
                return;
            end
            required=["ObservationDeliverySlot","ObservationDeliveryTime_s", ...
                "ObservationSampleRateHz","ObservationCompletionTime_s"];
            if ~all(ismember(required,string(trial.Properties.VariableNames)))
                error("sixgr:truth:BroadcastResultBeforeDelivery", ...
                    "A received multi-slot broadcast must cross its causal delivery boundary before use.");
            end
            now_s=(double(state.CurrentSlot)-1)*double(state.SlotDuration_s);
            if any(trial.ObservationDeliverySlot~=state.CurrentSlot)|| ...
                    any(trial.ObservationDeliveryTime_s~=now_s)|| ...
                    any(~isfinite(trial.ObservationCompletionTime_s))|| ...
                    any(trial.ObservationCompletionTime_s>now_s)|| ...
                    any(trial.ObservationCompletionTime_s~= ...
                    trial.ObservationEndSampleExclusive./trial.ObservationSampleRateHz)
                error("sixgr:truth:BroadcastResultBeforeDelivery", ...
                    "Broadcast acquisition/measurement cannot precede the received observation's completion.");
            end
            slot=double(state.CurrentSlot);
        end
    end
    methods(Static,Access=private)
        function items=pending(state)
            if isfield(state,"PendingBroadcastResults")
                items=state.PendingBroadcastResults;
            else
                items=sixgr.truth.BroadcastResultDelivery.empty();
            end
        end
        function items=empty()
            items=repmat(struct("UEIndex",[],"Trial",table(), ...
                "Recovery",struct(),"TrackingOnly",false, ...
                "CompletionTime_s",[]),0,1);
        end
    end
end
