classdef PUCCHFormatValidator
    %PUCCHFORMATVALIDATOR One fail-closed validator for formats 0 through 4.

    methods (Static)
        function result = validateVector(row)
            format = sixgr.phy.pucch.PUCCHUtil.number(row,"Format");
            symbols = sixgr.phy.pucch.PUCCHUtil.number(row,"NumSymbols");
            bits = sixgr.phy.pucch.PUCCHUtil.number(row,"UCIBits");
            prbs = sixgr.phy.pucch.PUCCHUtil.number(row,"NumPRBs");
            result = struct("Valid",true,"Format",format, ...
                "ParameterMutated",false,"ErrorID","");
            if ~sixgr.phy.pucch.PUCCHFormatValidator.payloadLegal(format,bits)
                result.Valid = false;
                result.ErrorID = "sixgr:phy:pucch:InvalidFormatPayload";
                return;
            end
            if ~sixgr.phy.pucch.PUCCHFormatValidator.symbolsLegal(format,symbols)
                result.Valid = false;
                result.ErrorID = "sixgr:phy:pucch:InvalidSymbolAllocation";
                return;
            end
            if ~(prbs >= 1 && prbs == fix(prbs)) || ...
                    (ismember(format,[0 1 4]) && prbs ~= 1)
                result.Valid = false;
                result.ErrorID = "sixgr:phy:pucch:InvalidPRBAllocation";
                return;
            end
            if sixgr.phy.pucch.PUCCHUtil.truth(row,"IntraSlotHopping",false)
                second = sixgr.phy.pucch.PUCCHUtil.number( ...
                    row,"SecondHopStartPRB",NaN);
                if ~(isfinite(second) && second >= 0 && second == fix(second))
                    result.Valid = false;
                    result.ErrorID = "sixgr:phy:pucch:InvalidHopping";
                    return;
                end
            end
        end

        function validateResource(data, informationBits)
            row = struct("Format",data.Format, ...
                "NumSymbols",data.NumSymbols, ...
                "UCIBits",informationBits, ...
                "NumPRBs",data.NumPRBs, ...
                "IntraSlotHopping",data.IntraSlotHopping, ...
                "SecondHopStartPRB",data.SecondHopStartPRB);
            result = sixgr.phy.pucch.PUCCHFormatValidator.validateVector(row);
            if ~result.Valid
                error(result.ErrorID, ...
                    "Invalid strict PUCCH format-%d resource tuple.",data.Format);
            end
            start = double(data.StartSymbol);
            if start < 0 || start ~= fix(start) || start+data.NumSymbols > 14
                error("sixgr:phy:pucch:InvalidSymbolAllocation", ...
                    "PUCCH symbols must stay within the 14-symbol slot.");
            end
            startPRB = double(data.StartPRB);
            if startPRB < 0 || startPRB ~= fix(startPRB)
                error("sixgr:phy:pucch:InvalidPRBAllocation", ...
                    "Starting PRB must be a nonnegative integer.");
            end
            if ismember(data.Format,[0 1])
                sixgr.phy.pucch.PUCCHUtil.assertInteger( ...
                    double(data.InitialCyclicShift),0,11, ...
                    "sixgr:phy:pucch:InvalidCyclicShift", ...
                    "InitialCyclicShift");
            end
            if data.Format == 4
                if ~ismember(double(data.OCCLength),[2 4]) || ...
                        data.OCCIndex < 0 || ...
                        data.OCCIndex >= data.OCCLength || ...
                        data.OCCIndex ~= fix(data.OCCIndex)
                    error("sixgr:phy:pucch:InvalidOCC", ...
                        "Format-4 OCC length/index is invalid.");
                end
            end
        end
    end

    methods (Static, Access=private)
        function value = payloadLegal(format,bits)
            if ~(ismember(format,[0 1 2 3 4]) && bits == fix(bits))
                value = false; return;
            end
            if ismember(format,[0 1])
                value = ismember(bits,[1 2]);
            else
                value = bits >= 3 && bits <= 1706;
            end
        end

        function value = symbolsLegal(format,symbols)
            if symbols ~= fix(symbols)
                value = false; return;
            end
            switch format
                case {0,2}
                    value = ismember(symbols,[1 2]);
                case {1,3,4}
                    value = symbols >= 4 && symbols <= 14;
                otherwise
                    value = false;
            end
        end
    end
end
