classdef PUCCHTimingResolver
    %PUCCHTIMINGRESOLVER Exact K1 and TDD-symbol legality, without shifts.

    methods (Static)
        function result = resolveVector(row)
            pdschEnd = sixgr.phy.pucch.PUCCHUtil.number(row,"PDSCHEndSlot");
            k1 = sixgr.phy.pucch.PUCCHUtil.number(row,"K1");
            declaredDue = sixgr.phy.pucch.PUCCHUtil.number(row,"DueSlot");
            start = sixgr.phy.pucch.PUCCHUtil.number(row,"PUCCHStartSymbol");
            count = sixgr.phy.pucch.PUCCHUtil.number(row,"PUCCHNumSymbols");
            ownership = char(sixgr.phy.pucch.PUCCHUtil.text( ...
                row,"SlotSymbolOwnership"));
            flex = sixgr.phy.pucch.PUCCHUtil.truth( ...
                row,"FlexibleResolutionProvided",false);
            result = struct("DueSlot",pdschEnd+k1,"Legal",false, ...
                "StartSymbol",start,"NumSymbols",count, ...
                "SymbolShiftApplied",false,"ErrorID","", ...
                "K1Source","decoded_dci", ...
                "SlotSymbolOwnership",string(ownership));
            if ~(k1 >= 0 && k1 == fix(k1)) || result.DueSlot ~= declaredDue
                result.ErrorID = "sixgr:phy:pucch:InvalidK1";
                return;
            end
            if ~(start >= 0 && count >= 1 && start == fix(start) && ...
                    count == fix(count) && start+count <= numel(ownership))
                result.ErrorID = "sixgr:phy:pucch:IllegalTDDResource";
                return;
            end
            selected = ownership(start+(1:count));
            legal = all(selected == 'U' | (selected == 'F' & flex));
            result.Legal = legal;
            if ~legal
                result.ErrorID = "sixgr:phy:pucch:IllegalTDDResource";
            end
        end

        function result = resolve(pdschEndSlot,k1,k1Source,ownership,startSymbol,numSymbols,flexResolved)
            row = struct("PDSCHEndSlot",pdschEndSlot,"K1",k1, ...
                "DueSlot",pdschEndSlot+k1, ...
                "SlotSymbolOwnership",string(ownership), ...
                "PUCCHStartSymbol",startSymbol, ...
                "PUCCHNumSymbols",numSymbols, ...
                "FlexibleResolutionProvided",logical(flexResolved));
            result = sixgr.phy.pucch.PUCCHTimingResolver.resolveVector(row);
            result.K1Source = string(k1Source);
            if ~result.Legal
                error(result.ErrorID, ...
                    "PUCCH symbols [%d,%d) are illegal in exact due slot %d.", ...
                    startSymbol,startSymbol+numSymbols,result.DueSlot);
            end
        end
    end
end
