classdef PUCCHHoppingPlan
    %PUCCHHOPPINGPLAN Immutable exact intra/inter-slot hopping coordinates.

    properties (SetAccess=private)
        Rows
        Digest
    end

    methods
        function obj = PUCCHHoppingPlan(resource,repetitionSlots)
            d = resource.Data;
            rowCount = double(repetitionSlots) * ...
                (1 + double(logical(d.IntraSlotHopping)));
            rows = table(zeros(rowCount,1),zeros(rowCount,1), ...
                zeros(rowCount,1),zeros(rowCount,1),zeros(rowCount,1), ...
                'VariableNames',{'Slot','RepetitionIndex','HopIndex', ...
                'StartPRB','NumPRBs'});
            count = 0;
            for repetition = 0:repetitionSlots-1
                hops = 0;
                if d.IntraSlotHopping, hops = [0 1]; end
                for hop = hops
                    count = count+1;
                    start = d.StartPRB;
                    if hop == 1, start = d.SecondHopStartPRB; end
                    rows.Slot(count,1) = repetition;
                    rows.RepetitionIndex(count,1) = repetition;
                    rows.HopIndex(count,1) = hop;
                    rows.StartPRB(count,1) = start;
                    rows.NumPRBs(count,1) = d.NumPRBs;
                end
            end
            obj.Rows = rows;
            obj.Digest = sixgr.phy.pucch.PUCCHUtil.hash(table2struct(rows));
        end
    end
end
