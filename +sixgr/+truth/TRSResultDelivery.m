classdef TRSResultDelivery
%TRSRESULTDELIVERY Release complete TRS evidence at the receiver clock boundary.
% This queue neither executes nor repairs an eagerly advanced physical
% channel. Shared sample execution must independently remain chronological.
    methods (Static)
        function state = enqueue(state,servingCell,ueIdx,trial,cfg,observedRE)
            validateattributes(servingCell,{'numeric'}, ...
                {'real','scalar','finite','integer','positive','<=',numel(state.TRSValidityStateByCell)});
            validateattributes(ueIdx,{'numeric'}, ...
                {'real','scalar','finite','integer','positive','<=',state.NumUsers});
            if ~isstruct(cfg)||~isscalar(cfg)||~istable(observedRE)
                error('sixgr:truth:InvalidTRSResult','TRS delivery requires its source configuration and RE evidence table.');
            end
            completion = sixgr.truth.TRSResultDelivery.validateClock(trial);
            if ~all(ismember(["ServingCell","UEIndex"],string(trial.Properties.VariableNames)))|| ...
                    ~isequal(trial.ServingCell,double(servingCell))|| ...
                    ~isequal(trial.UEIndex,double(ueIdx))
                error('sixgr:truth:TRSResultOwnerMismatch', ...
                    'Pending TRS evidence must retain its actual serving cell and receiving UE.');
            end
            items = sixgr.truth.TRSResultDelivery.pending(state);
            if any([items.ServingCell]==servingCell)
                error('sixgr:truth:DuplicatePendingTRS', ...
                    'Cell %d already has an undelivered TRS observation.',servingCell);
            end
            item = struct('ServingCell',double(servingCell),'UEIndex',double(ueIdx), ...
                'Trial',trial,'Config',cfg,'ObservedRE',observedRE,'CompletionTime_s',completion);
            state.PendingTRSResults = [items;item];
        end

        function [state,ready] = takeAvailable(state)
            now = sixgr.truth.TRSResultDelivery.now(state);
            items = sixgr.truth.TRSResultDelivery.pending(state);
            due = [items.CompletionTime_s]<=now;
            ready = items(due);
            [~,order] = sort([ready.CompletionTime_s]);
            ready = ready(order);
            for k = 1:numel(ready)
                sixgr.truth.TRSResultDelivery.validateClock(ready(k).Trial);
                ready(k).Trial.ObservationDeliverySlot = double(state.CurrentSlot);
                ready(k).Trial.ObservationDeliveryTime_s = now;
                ready(k).Trial.ObservationDeliverySource = ...
                    "canonical_slot_start_after_complete_received_window";
            end
            state.PendingTRSResults = items(~due);
        end

        function state = censor(state,items,reason)
            if isempty(items), return; end
            if ~isfield(state,'CensoredTRSResults'), state.CensoredTRSResults=cell(0,1); end
            state.CensoredTRSResults{end+1,1} = struct('Reason',string(reason),'Results',items);
        end

        function state = censorAtSweepBoundary(state)
            state = sixgr.truth.TRSResultDelivery.censorAtBoundary(state, ...
                'independent_snr_point_boundary_before_delivery');
        end

        function state = censorAtBoundary(state,reason)
            state = sixgr.truth.TRSResultDelivery.censor(state, ...
                sixgr.truth.TRSResultDelivery.pending(state),reason);
            state.PendingTRSResults = sixgr.truth.TRSResultDelivery.empty();
        end

        function slot = deliverySlot(state,trial)
            slot = double(state.CurrentSlot);
            if ismember('Slot',trial.Properties.VariableNames), slot=double(trial.Slot(end)); end
            if ~ismember('ObservationEndSampleExclusive',trial.Properties.VariableNames)|| ...
                    all(isnan(trial.ObservationEndSampleExclusive))
                runtimeTagged = ismember('RuntimeIntegrationMode',trial.Properties.VariableNames) && ...
                    any(string(trial.RuntimeIntegrationMode)=="coupled_slot_runtime");
                crashed = ismember('Crash',trial.Properties.VariableNames) && all(trial.Crash==1) && ...
                    ismember('Status',trial.Properties.VariableNames) && all(string(trial.Status)=="CRASH");
                if runtimeTagged && ~crashed
                    error('sixgr:truth:MissingTRSObservationClock', ...
                        'A runtime TRS measurement cannot omit its received observation clock.');
                end
                % Legacy state-machine fixtures and explicit crashed attempts
                % have no received capture. The runtime enqueue path rejects
                % unclocked measurement rows; these are not a rescue path.
                return;
            end
            completion = sixgr.truth.TRSResultDelivery.validateClock(trial);
            required = ["ObservationDeliverySlot","ObservationDeliveryTime_s","ObservationDeliverySource"];
            if ~all(ismember(required,string(trial.Properties.VariableNames)))
                error('sixgr:truth:TRSResultBeforeDelivery', ...
                    'TRS tracking cannot consume an observation before its delivery boundary.');
            end
            now = sixgr.truth.TRSResultDelivery.now(state);
            if ~isequal(trial.ObservationDeliverySlot,double(state.CurrentSlot))|| ...
                    ~isequal(trial.ObservationDeliveryTime_s,now)||completion>now|| ...
                    string(trial.ObservationDeliverySource)~= ...
                    "canonical_slot_start_after_complete_received_window"
                error('sixgr:truth:TRSResultBeforeDelivery', ...
                    'TRS tracking availability must follow actual received sample completion.');
            end
            slot = double(state.CurrentSlot);
        end
    end
    methods (Static,Access=private)
        function completion = validateClock(trial)
            required = ["ObservationStartSample","ObservationEndSampleExclusive", ...
                "ObservationSampleRateHz","ObservationCompletionTime_s","ObservationCoverageSource","Slot"];
            if ~istable(trial)||height(trial)~=1|| ...
                    ~all(ismember(required,string(trial.Properties.VariableNames)))
                error('sixgr:truth:MissingTRSObservationClock', ...
                    'TRS delivery requires one actual receiver row with complete sample-window evidence.');
            end
            for name = required([1:4 6])
                value = trial.(name);
                if ~isnumeric(value)||~isreal(value)||~isscalar(value)||~isfinite(value)
                    error('sixgr:truth:InvalidTRSObservationClock','TRS capture coordinates must be finite numeric scalars.');
                end
            end
            first = double(trial.ObservationStartSample);
            last = double(trial.ObservationEndSampleExclusive);
            fs = double(trial.ObservationSampleRateHz);
            completion = double(trial.ObservationCompletionTime_s);
            slot = double(trial.Slot);
            coverage = string(trial.ObservationCoverageSource);
            if first<0||first~=fix(first)||last<=first||last~=fix(last)||last>flintmax|| ...
                    fs<=0||completion~=last/fs||slot<1||slot~=fix(slot)|| ...
                    ~isscalar(coverage)||ismissing(coverage)|| ...
                    coverage~="complete_contiguous_received_sample_buffer"
                error('sixgr:truth:InvalidTRSObservationClock', ...
                    'TRS availability must equal the end of its actual complete received sample buffer.');
            end
        end
        function value = now(state)
            validateattributes(state.CurrentSlot,{'numeric'},{'real','scalar','finite','integer','positive'});
            validateattributes(state.SlotDuration_s,{'numeric'},{'real','scalar','finite','positive'});
            value = (double(state.CurrentSlot)-1)*double(state.SlotDuration_s);
        end
        function items = pending(state)
            if isfield(state,'PendingTRSResults'), items=state.PendingTRSResults;
            else, items=sixgr.truth.TRSResultDelivery.empty(); end
        end
        function items = empty()
            items = repmat(struct('ServingCell',[],'UEIndex',[],'Trial',table(), ...
                'Config',struct(),'ObservedRE',table(),'CompletionTime_s',[]),0,1);
        end
    end
end
