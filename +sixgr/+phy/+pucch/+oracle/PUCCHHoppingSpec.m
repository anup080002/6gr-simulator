classdef PUCCHHoppingSpec
    %PUCCHHOPPINGSPEC Independent hop/repetition PRB schedule.
    methods (Static)
        function out = resolve(startPRB,secondHopPRB,intraSlot,repetitionSlots)
            slots=(0:double(repetitionSlots)-1).';
            first=repmat(double(startPRB),numel(slots),1);
            second=first;
            if logical(intraSlot),second(:)=double(secondHopPRB);end
            out=table(slots,first,second, ...
                'VariableNames',{'Repetition','FirstHopPRB','SecondHopPRB'});
        end
    end
end
