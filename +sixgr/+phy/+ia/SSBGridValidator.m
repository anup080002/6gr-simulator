classdef SSBGridValidator
    %SSBGRIDVALIDATOR Validate SS/PBCH placement without clamp or retry.

    methods (Static)
        function result = validate(varargin)
            p = inputParser;
            p.FunctionName = "sixgr.phy.ia.SSBGridValidator.validate";
            addParameter(p, "CarrierSubcarrierSpacingKHz", NaN, ...
                @localPositiveFinite);
            addParameter(p, "SSBSubcarrierSpacingKHz", NaN, ...
                @localPositiveFinite);
            addParameter(p, "NStartGrid", 0, @localNonnegativeInteger);
            addParameter(p, "NSizeGrid", NaN, @localPositiveInteger);
            addParameter(p, "NStartBWP", 0, @localNonnegativeInteger);
            addParameter(p, "NSizeBWP", NaN, @localPositiveInteger);
            addParameter(p, "NCRBSSB", 0, @localNonnegativeInteger);
            addParameter(p, "KSSB", 0, @localNonnegativeInteger);
            parse(p, varargin{:});
            opt = p.Results;

            carrierSCS = double(opt.CarrierSubcarrierSpacingKHz);
            ssbSCS = double(opt.SSBSubcarrierSpacingKHz);
            nStart = double(opt.NStartGrid);
            nSize = double(opt.NSizeGrid);
            bwpStart = double(opt.NStartBWP);
            bwpSize = double(opt.NSizeBWP);
            ncrb = double(opt.NCRBSSB);
            kssb = double(opt.KSSB);

            if bwpStart < nStart || bwpStart + bwpSize > nStart + nSize
                error("sixgr:phy:ia:InvalidCarrierGrid", ...
                    "DL BWP [%g,%g) is outside carrier grid [%g,%g).", ...
                    bwpStart, bwpStart + bwpSize, nStart, nStart + nSize);
            end
            if any(ssbSCS == [15, 30])
                referenceSCS = 15;
                maxKSSB = 23;
            else
                referenceSCS = 60;
                maxKSSB = 11;
            end
            if kssb > maxKSSB
                error("sixgr:phy:ia:InvalidCarrierGrid", ...
                    "KSSB=%d exceeds %d for SSB SCS %g kHz.", ...
                    kssb, maxKSSB, ssbSCS);
            end

            carrierLowHz = nStart * 12 * carrierSCS * 1e3;
            carrierHighHz = (nStart + nSize) * 12 * carrierSCS * 1e3;
            ssbLowHz = (ncrb * 12 + kssb) * referenceSCS * 1e3;
            ssbHighHz = ssbLowHz + 240 * ssbSCS * 1e3;
            toleranceHz = max(1e-9 * carrierHighHz, 1e-6);
            if ssbLowHz < carrierLowHz - toleranceHz || ...
                    ssbHighHz > carrierHighHz + toleranceHz
                error("sixgr:phy:ia:SSBOutsideCarrier", ...
                    "SS/PBCH [%g,%g) Hz is outside carrier [%g,%g) Hz.", ...
                    ssbLowHz, ssbHighHz, carrierLowHz, carrierHighHz);
            end

            payload = struct( ...
                "CarrierSubcarrierSpacingKHz", carrierSCS, ...
                "SSBSubcarrierSpacingKHz", ssbSCS, ...
                "NStartGrid", nStart, ...
                "NSizeGrid", nSize, ...
                "NStartBWP", bwpStart, ...
                "NSizeBWP", bwpSize, ...
                "NCRBSSB", ncrb, ...
                "KSSB", kssb, ...
                "PointAReferenceSCSKHz", referenceSCS, ...
                "SSBLowOffsetFromPointAHz", ssbLowHz, ...
                "SSBHighOffsetFromPointAHz", ssbHighHz, ...
                "CarrierLowOffsetFromPointAHz", carrierLowHz, ...
                "CarrierHighOffsetFromPointAHz", carrierHighHz, ...
                "ResolvedValid", true);
            result = payload;
            result.ValidationSHA256 = sixgr.util.sha256Hex(jsonencode(payload));
        end
    end
end

function tf = localPositiveFinite(value)
tf = isnumeric(value) && isscalar(value) && isfinite(value) && value > 0;
end

function tf = localNonnegativeInteger(value)
tf = isnumeric(value) && isscalar(value) && isfinite(value) && ...
    value >= 0 && value == fix(value);
end

function tf = localPositiveInteger(value)
tf = isnumeric(value) && isscalar(value) && isfinite(value) && ...
    value >= 1 && value == fix(value);
end
