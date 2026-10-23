classdef CheckpointSchedule
    % One-based completed-slot cadence, optionally anchored at a chosen slot.
    % FirstSlot=0 retains the original multiples-of-period convention.
    methods (Static)
        function tf=due(completedSlot,everySlots,firstSlot)
            validateattributes(completedSlot,{'numeric'},{'scalar','integer','positive','finite'});
            validateattributes(everySlots,{'numeric'},{'scalar','integer','positive','finite'});
            validateattributes(firstSlot,{'numeric'},{'scalar','integer','nonnegative','finite'});
            if firstSlot==0
                tf=mod(completedSlot,everySlots)==0;
            else
                tf=completedSlot>=firstSlot && mod(completedSlot-firstSlot,everySlots)==0;
            end
        end
    end
end
