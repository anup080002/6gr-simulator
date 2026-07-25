classdef PUSCHModulator
    %PUSCHMODULATOR Strict PUSCH modulation with explicit procedure state.

    methods (Static)
        function [symbols, info] = modulate(bits, modulation, transformPrecoding)
            bits = sixgr.phy.ul.pusch.PUSCHModulator.validateBits(bits);
            modulation = sixgr.phy.ul.pusch.PUSCHModulator.normalizeModulation(modulation);
            transformPrecoding = logical(transformPrecoding);

            if modulation == "PI/2-BPSK" && ~transformPrecoding
                error("sixgr:pusch:TransformPrecodingRequired", ...
                    "PI/2-BPSK is legal only for an explicitly transform-precoded PUSCH.");
            end
            qm = sixgr.phy.ul.pusch.PUSCHModulator.modulationOrder(modulation);
            if mod(numel(bits), qm) ~= 0
                error("sixgr:pusch:BitCountNotDivisibleByQm", ...
                    "PUSCH %s requires a bit count divisible by Qm=%d.", ...
                    modulation, qm);
            end

            if modulation == "PI/2-BPSK"
                n = (0:numel(bits)-1).';
                symbols = (1 - 2 * double(bits)) .* ...
                    exp(1j * (pi / 4 + pi * n / 2));
                engine = "explicit_ts38211_pi_over_2_bpsk";
            else
                symbols = nrSymbolModulate(bits, char(modulation));
                engine = "nrSymbolModulate";
            end
            symbols = complex(double(symbols(:)));
            info = struct( ...
                "Modulation", modulation, ...
                "Qm", double(qm), ...
                "TransformPrecoding", transformPrecoding, ...
                "InputBitCount", double(numel(bits)), ...
                "OutputSymbolCount", double(numel(symbols)), ...
                "Engine", engine, ...
                "Source", "production_pusch_modulator");
        end

        function modulation = normalizeModulation(value)
            modulation = upper(strrep(strtrim(string(value)), " ", ""));
            if ~isscalar(modulation) || strlength(modulation) == 0
                error("sixgr:pusch:MissingModulation", ...
                    "Strict PUSCH modulation must be configured explicitly.");
            end
            if modulation == "PI2-BPSK"
                modulation = "PI/2-BPSK";
            end
            allowed = ["PI/2-BPSK","QPSK","16QAM","64QAM","256QAM"];
            if ~ismember(modulation, allowed)
                error("sixgr:pusch:UnsupportedModulation", ...
                    "Strict PUSCH modulation must be one of %s; received '%s'.", ...
                    strjoin(allowed, ", "), char(string(value)));
            end
        end

        function qm = modulationOrder(modulation)
            modulation = sixgr.phy.ul.pusch.PUSCHModulator.normalizeModulation(modulation);
            switch modulation
                case "PI/2-BPSK"
                    qm = 1;
                case "QPSK"
                    qm = 2;
                case "16QAM"
                    qm = 4;
                case "64QAM"
                    qm = 6;
                case "256QAM"
                    qm = 8;
            end
        end
    end

    methods (Static, Access = private)
        function bits = validateBits(bits)
            if ~((isnumeric(bits) || islogical(bits)) && isvector(bits))
                error("sixgr:pusch:NonBinaryInput", ...
                    "PUSCH modulation input must be a binary vector.");
            end
            bits = double(bits(:));
            if any(~isfinite(bits) | (bits ~= 0 & bits ~= 1))
                error("sixgr:pusch:NonBinaryInput", ...
                    "PUSCH modulation input must contain only zero and one.");
            end
            bits = int8(bits);
        end
    end
end
