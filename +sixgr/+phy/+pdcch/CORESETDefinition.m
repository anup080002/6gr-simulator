classdef CORESETDefinition
    %CORESETDEFINITION Validated Release-18 CORESET mapping context.

    properties (SetAccess = private)
        Data
        Digest
    end

    methods
        function obj = CORESETDefinition(data)
            if ~(isstruct(data) && isscalar(data))
                error("sixgr:phy:pdcch:invalid_coreset_frequency_resources", ...
                    "CORESETDefinition requires one scalar configuration structure.");
            end
            required = ["CORESETID","NRB","DurationSymbols","MappingType", ...
                "REGBundleSize","InterleaverSize","ShiftIndex","RBStart", ...
                "StartSymbol","PrecoderGranularity"];
            missing = required(~isfield(data, cellstr(required)));
            if ~isempty(missing)
                error("sixgr:phy:pdcch:invalid_coreset_frequency_resources", ...
                    "CORESET definition is missing: %s.", strjoin(missing, ", "));
            end
            data.MappingType = lower(strrep(string(data.MappingType), "-", ""));
            data.PrecoderGranularity = string(data.PrecoderGranularity);
            nRB = localInteger(data.NRB, "NRB");
            duration = localInteger(data.DurationSymbols, "DurationSymbols");
            if nRB < 6 || mod(nRB, 6) ~= 0
                error("sixgr:phy:pdcch:invalid_coreset_frequency_resources", ...
                    "CORESET NRB must be a positive multiple of six; got %d.", nRB);
            end
            if ~ismember(duration, 1:3)
                error("sixgr:phy:pdcch:invalid_coreset_duration", ...
                    "CORESET duration must be 1, 2 or 3 OFDM symbols.");
            end
            L = localInteger(data.REGBundleSize, "REGBundleSize");
            R = localInteger(data.InterleaverSize, "InterleaverSize");
            nREG = nRB * duration;
            switch data.MappingType
                case "noninterleaved"
                    if L ~= 6
                        error("sixgr:phy:pdcch:invalid_reg_bundle_size", ...
                            "Non-interleaved CORESET mapping requires REG bundle size six.");
                    end
                    R = 0;
                case "interleaved"
                    if ~ismember(L, [2 3 6]) || mod(6, L) ~= 0 || mod(nREG, L) ~= 0
                        error("sixgr:phy:pdcch:invalid_reg_bundle_size", ...
                            "Interleaved REG bundle size must be 2, 3 or 6 and divide NREG and six.");
                    end
                    if ~ismember(R, [2 3 6]) || mod(nREG/L, R) ~= 0
                        error("sixgr:phy:pdcch:invalid_interleaver_size", ...
                            "Interleaver size must be 2, 3 or 6 and divide the REG-bundle count.");
                    end
                otherwise
                    error("sixgr:phy:pdcch:invalid_coreset_frequency_resources", ...
                        "CORESET MappingType must be interleaved or nonInterleaved.");
            end
            shift = localInteger(data.ShiftIndex, "ShiftIndex");
            if shift < 0 || shift > 274
                error("sixgr:phy:pdcch:invalid_shift_index", ...
                    "CORESET ShiftIndex must be an integer in [0,274].");
            end
            if ~ismember(data.PrecoderGranularity, ["sameAsREG-bundle","allContiguousRBs"])
                error("sixgr:phy:pdcch:invalid_coreset_frequency_resources", ...
                    "PrecoderGranularity must be sameAsREG-bundle or allContiguousRBs.");
            end
            data.NRB = nRB;
            data.DurationSymbols = duration;
            data.REGBundleSize = L;
            data.InterleaverSize = R;
            data.ShiftIndex = shift;
            data.NREG = nREG;
            data.NCCE = nREG / 6;
            obj.Data = orderfields(data);
            obj.Digest = string(sixgr.rrc.asn1.sha256Hex(uint8( ...
                unicode2native(jsonencode(obj.Data), "UTF-8"))));
        end
    end
end

function value = localInteger(value, name)
value = double(value);
if ~(isscalar(value) && isfinite(value) && value == fix(value))
    error("sixgr:phy:pdcch:invalid_coreset_frequency_resources", ...
        "%s must be a finite integer.", name);
end
end
