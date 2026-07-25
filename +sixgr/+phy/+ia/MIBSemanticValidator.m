classdef MIBSemanticValidator
    %MIBSEMANTICVALIDATOR Pack and validate the 23 MIB information bits.

    methods (Static)
        function result = resolve(varargin)
            p = inputParser;
            p.FunctionName = "sixgr.phy.ia.MIBSemanticValidator.resolve";
            addParameter(p, "CaseID", "", @localTextScalar);
            addParameter(p, "SystemFrameNumberMSB6", NaN, @localNumericScalar);
            addParameter(p, "SubCarrierSpacingCommon", "", @localTextScalar);
            addParameter(p, "SSBSubcarrierOffset", NaN, @localNumericScalar);
            addParameter(p, "DMRSTypeAPosition", "", @localTextScalar);
            addParameter(p, "PDCCHConfigSIB1", NaN, @localNumericScalar);
            addParameter(p, "CellBarred", "", @localTextScalar);
            addParameter(p, "IntraFreqReselection", "", @localTextScalar);
            addParameter(p, "Spare", 0, @localNumericScalar);
            parse(p, varargin{:});
            opt = p.Results;

            sfn = localIntegerRange(opt.SystemFrameNumberMSB6, 0, 63, ...
                "systemFrameNumber");
            kssb = localIntegerRange(opt.SSBSubcarrierOffset, 0, 15, ...
                "ssb-SubcarrierOffset");
            pdcch = localIntegerRange(opt.PDCCHConfigSIB1, 0, 255, ...
                "pdcch-ConfigSIB1");
            spare = localIntegerRange(opt.Spare, 0, 0, "spare");
            scsToken = lower(strtrim(string(opt.SubCarrierSpacingCommon)));
            if scsToken == "scs15or60"
                scsBit = 0;
            elseif scsToken == "scs30or120"
                scsBit = 1;
            else
                localSemanticError( ...
                    "subCarrierSpacingCommon must be scs15or60 or scs30or120.");
            end
            dmrsToken = lower(strtrim(string(opt.DMRSTypeAPosition)));
            if dmrsToken == "pos2"
                dmrsBit = 0;
                dmrsPosition = 2;
            elseif dmrsToken == "pos3"
                dmrsBit = 1;
                dmrsPosition = 3;
            else
                localSemanticError( ...
                    "dmrs-TypeA-Position must be pos2 or pos3.");
            end
            barredToken = lower(strtrim(string(opt.CellBarred)));
            if barredToken == "barred"
                barredBit = 0;
            elseif barredToken == "notbarred"
                barredBit = 1;
            else
                localSemanticError( ...
                    "cellBarred must be barred or notBarred.");
            end
            reselectionToken = lower(strtrim( ...
                string(opt.IntraFreqReselection)));
            if reselectionToken == "allowed"
                reselectionBit = 0;
            elseif reselectionToken == "notallowed"
                reselectionBit = 1;
            else
                localSemanticError( ...
                    "intraFreqReselection must be allowed or notAllowed.");
            end

            sfnBits = localUIntBits(sfn, 6);
            kssbBits = localUIntBits(kssb, 4);
            pdcchBits = localUIntBits(pdcch, 8);
            bits = int8([ ...
                sfnBits, scsBit, kssbBits, dmrsBit, pdcchBits, ...
                barredBit, reselectionBit, spare]);
            if numel(bits) ~= 23
                localSemanticError("MIB packing did not produce 23 bits.");
            end
            bitString = localBitsToString(bits);
            split = sixgr.phy.broadcast.splitPDCCHConfigSIB1( ...
                pdcch, "Source", "decoded_validated_mib_information_bits");
            payload = struct( ...
                "CaseID", string(opt.CaseID), ...
                "MIBInformationBits23", bitString, ...
                "NumBits", 23, ...
                "SystemFrameNumberMSB6", sfn, ...
                "SFNBits", localBitsToString(sfnBits), ...
                "SubCarrierSpacingCommon", scsToken, ...
                "SCSBit", scsBit, ...
                "SSBSubcarrierOffset", kssb, ...
                "KSSBBits", localBitsToString(kssbBits), ...
                "DMRSTypeAPosition", dmrsPosition, ...
                "DMRSTypeAPositionToken", dmrsToken, ...
                "DMRSTypeAPositionBit", dmrsBit, ...
                "PDCCHConfigSIB1", pdcch, ...
                "PDCCHConfigSIB1Bits", localBitsToString(pdcchBits), ...
                "CORESET0Index", double(split.CORESET0Index), ...
                "SearchSpaceZero", double(split.SearchSpaceZero), ...
                "CellBarred", barredToken, ...
                "CellBarredBit", barredBit, ...
                "IntraFreqReselection", reselectionToken, ...
                "IntraFreqReselectionBit", reselectionBit, ...
                "Spare", spare, ...
                "SpareBit", spare, ...
                "SemanticValidationStatus", "PASS", ...
                "Standard", "3GPP TS 38.331 V18.9.0 MIB", ...
                "InformationBits", bits(:));
            result = payload;
            result.SemanticSHA256 = sixgr.util.sha256Hex(bitString);
        end

        function result = decodeBits(bits, varargin)
            if ~(isnumeric(bits) || islogical(bits))
                localSemanticError("MIB information bits must be numeric/logical.");
            end
            bits = int8(bits(:) ~= 0);
            if numel(bits) ~= 23
                localSemanticError( ...
                    "MIB must contain exactly 23 information bits.");
            end
            result = sixgr.phy.ia.MIBSemanticValidator.resolve( ...
                "SystemFrameNumberMSB6", localBitsToUInt(bits(1:6)), ...
                "SubCarrierSpacingCommon", localSCS(bits(7)), ...
                "SSBSubcarrierOffset", localBitsToUInt(bits(8:11)), ...
                "DMRSTypeAPosition", localDMRS(bits(12)), ...
                "PDCCHConfigSIB1", localBitsToUInt(bits(13:20)), ...
                "CellBarred", localBarred(bits(21)), ...
                "IntraFreqReselection", localReselection(bits(22)), ...
                "Spare", double(bits(23)), ...
                varargin{:});
            if ~isequal(int8(result.InformationBits(:)), bits)
                localSemanticError( ...
                    "Decoded MIB fields do not round-trip to the received bits.");
            end
        end

        function result = fromVectorRow(row)
            if istable(row)
                if height(row) ~= 1
                    localSemanticError("A single MIB vector row is required.");
                end
                row = table2struct(row);
            end
            result = sixgr.phy.ia.MIBSemanticValidator.resolve( ...
                "CaseID", row.CaseID, ...
                "SystemFrameNumberMSB6", ...
                    localToDouble(row.SystemFrameNumberMSB6), ...
                "SubCarrierSpacingCommon", row.SubCarrierSpacingCommon, ...
                "SSBSubcarrierOffset", ...
                    localToDouble(row.SSBSubcarrierOffset), ...
                "DMRSTypeAPosition", row.DMRSTypeAPosition, ...
                "PDCCHConfigSIB1", ...
                    localToDouble(row.PDCCHConfigSIB1), ...
                "CellBarred", row.CellBarred, ...
                "IntraFreqReselection", row.IntraFreqReselection, ...
                "Spare", localToDouble(row.Spare));
        end
    end
end

function value = localIntegerRange(raw, minimum, maximum, name)
value = double(raw);
if ~(isscalar(value) && isfinite(value) && value == fix(value) && ...
        value >= minimum && value <= maximum)
    localSemanticError(sprintf( ...
        "%s must be an integer in [%d,%d].", name, minimum, maximum));
end
end

function bits = localUIntBits(value, width)
bits = zeros(1, width, "int8");
for i = 1:width
    bits(i) = int8(bitget(uint64(value), width - i + 1));
end
end

function value = localBitsToUInt(bits)
value = 0;
for i = 1:numel(bits)
    value = value * 2 + double(bits(i));
end
end

function text = localBitsToString(bits)
chars = repmat('0', 1, numel(bits));
chars(logical(bits(:).')) = '1';
text = string(chars);
end

function value = localSCS(bit)
if bit == 0
    value = "scs15or60";
else
    value = "scs30or120";
end
end

function value = localDMRS(bit)
if bit == 0
    value = "pos2";
else
    value = "pos3";
end
end

function value = localBarred(bit)
if bit == 0
    value = "barred";
else
    value = "notBarred";
end
end

function value = localReselection(bit)
if bit == 0
    value = "allowed";
else
    value = "notAllowed";
end
end

function value = localToDouble(raw)
if isnumeric(raw)
    value = double(raw);
else
    value = str2double(string(raw));
end
end

function localSemanticError(message)
error("sixgr:phy:ia:MIBSemanticFailure", "%s", message);
end

function tf = localTextScalar(value)
tf = ischar(value) || (isstring(value) && isscalar(value));
end

function tf = localNumericScalar(value)
tf = (isnumeric(value) || islogical(value)) && isscalar(value);
end
