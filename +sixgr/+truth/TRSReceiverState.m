classdef TRSReceiverState
% Receiver-owned TRS state. A common transmitted RS is not a common estimate.
% Single-UE state retains its existing cell-indexed representation. Multi-UE
% consumers must select an explicit UE; unassigned cell aliases stay empty
% of measurements and cannot grant another UE tracking authority.
    methods (Static)
        function state=initialize(state)
            blank=sixgr.truth.TRSReceiverState.capture(state);
            state.TRSUnassignedCellState=blank;
            state.TRSReceiverStateByUE=cell(state.NumUsers,1);
            for ue=1:state.NumUsers
                receiver=blank;
                for cellIdx=1:numel(receiver.ReceiverTrackingStateByCell)
                    receiver.ReceiverTrackingStateByCell(cellIdx).UEIndex=double(ue);
                end
                state.TRSReceiverStateByUE{ue}=receiver;
            end
            if state.NumUsers==1
                state=sixgr.truth.TRSReceiverState.assign(state,state.TRSReceiverStateByUE{1});
            end
        end

        function state=forUE(state,ue)
            validateattributes(ue,{'numeric'}, ...
                {'real','finite','scalar','integer','positive','<=',state.NumUsers});
            if state.NumUsers>1
                assert(isfield(state,'TRSReceiverStateByUE') && ...
                    numel(state.TRSReceiverStateByUE)==state.NumUsers, ...
                    'sixgr:truth:MissingReceiverOwnedTRSState', ...
                    'Multi-UE tracking requires separately initialized receiver state.');
                state=sixgr.truth.TRSReceiverState.assign(state,state.TRSReceiverStateByUE{ue});
            end
            state.TRSActiveReceiverUE=double(ue);
        end

        function state=commit(state,ue)
            assert(isfield(state,'TRSActiveReceiverUE') && state.TRSActiveReceiverUE==ue, ...
                'sixgr:truth:TRSReceiverStateOwnerMismatch','Commit only the selected receiver state.');
            if state.NumUsers>1
                state.TRSReceiverStateByUE{ue}=sixgr.truth.TRSReceiverState.capture(state);
                state=sixgr.truth.TRSReceiverState.assign(state,state.TRSUnassignedCellState);
            end
            state=rmfield(state,'TRSActiveReceiverUE');
        end

        function ue=owner(state,row)
            if ismember('UEIndex',row.Properties.VariableNames)
                ue=double(row.UEIndex);
            elseif state.NumUsers==1
                ue=1; % Unambiguous legacy single-receiver state-machine input.
            else
                error('sixgr:truth:MissingTRSReceiverOwner','A multi-UE TRS result must identify its receiver.');
            end
            validateattributes(ue,{'numeric'}, ...
                {'real','finite','scalar','integer','positive','<=',state.NumUsers});
        end
    end
    methods (Static,Access=private)
        function names=fields()
            names=["TRSValidityStateByCell","TrackingEligibilityByCell", ...
                "LastSuccessfulTRSSlotByCell","LastTRSObservedSlotByCell", ...
                "LastEstimatedTRSDopplerHzByCell","TRSFailureCountByCell", ...
                "ReceiverTrackingStateByCell"];
        end
        function receiver=capture(state)
            receiver=struct();
            for name=sixgr.truth.TRSReceiverState.fields()
                receiver.(name)=state.(name);
            end
        end
        function state=assign(state,receiver)
            for name=sixgr.truth.TRSReceiverState.fields()
                state.(name)=receiver.(name);
            end
        end
    end
end
