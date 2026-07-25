classdef PUSCHLayerMapper
    %PUSCHLAYERMAPPER Exact one/two-codeword PUSCH layer mapping.

    methods (Static)
        function [output, info] = map(codewords, rank)
            [layerCounts, rank] = sixgr.phy.ul.pusch.PUSCHLayerMapper.layerCounts(rank);
            codewords = sixgr.phy.ul.pusch.PUSCHLayerMapper.normalizeCodewords( ...
                codewords, numel(layerCounts));
            layers = cell(rank, 1);
            offset = 0;
            for cw = 1:numel(codewords)
                stream = codewords{cw};
                count = layerCounts(cw);
                if mod(numel(stream), count) ~= 0
                    error("sixgr:pusch:LayerSymbolCountMismatch", ...
                        "Codeword %d has %d symbols, which is not divisible by %d layers.", ...
                        cw - 1, numel(stream), count);
                end
                for localLayer = 1:count
                    layers{offset + localLayer} = stream(localLayer:count:end);
                end
                offset = offset + count;
            end
            lengths = cellfun(@numel, layers);
            if all(lengths == lengths(1))
                output = horzcat(layers{:});
            else
                output = layers;
            end
            info = sixgr.phy.ul.pusch.PUSCHLayerMapper.info(rank, layerCounts, "map");
        end

        function [output, info] = demap(layers, rank)
            [layerCounts, rank] = sixgr.phy.ul.pusch.PUSCHLayerMapper.layerCounts(rank);
            layers = sixgr.phy.ul.pusch.PUSCHLayerMapper.normalizeLayers(layers, rank);
            output = cell(1, numel(layerCounts));
            offset = 0;
            for cw = 1:numel(layerCounts)
                selected = layers(offset + (1:layerCounts(cw)));
                lengths = cellfun(@numel, selected);
                if ~all(lengths == lengths(1))
                    error("sixgr:pusch:LayerDemappingLengthMismatch", ...
                        "Layers for codeword %d do not have equal lengths.", cw - 1);
                end
                output{cw} = reshape(horzcat(selected{:}).', [], 1);
                offset = offset + layerCounts(cw);
            end
            if isscalar(output)
                output = output{1};
            end
            info = sixgr.phy.ul.pusch.PUSCHLayerMapper.info(rank, layerCounts, "demap");
        end

        function [counts, rank] = layerCounts(rank)
            rank = double(rank);
            if ~(isscalar(rank) && isfinite(rank) && rank == fix(rank) ...
                    && rank >= 1)
                error("sixgr:pusch:InvalidRank", ...
                    "PUSCH rank must be a positive integer.");
            end
            if rank > 8
                error("sixgr:pusch:UnsupportedRank", ...
                    "PUSCH rank %d is unsupported; the supported range is 1 through 8.", ...
                    rank);
            end
            if rank <= 4
                counts = rank;
            else
                switch rank
                    case 5
                        counts = [2 3];
                    case 6
                        counts = [3 3];
                    case 7
                        counts = [3 4];
                    case 8
                        counts = [4 4];
                end
            end
        end
    end

    methods (Static, Access = private)
        function codewords = normalizeCodewords(value, count)
            if count == 1 && ~iscell(value)
                codewords = {value};
            elseif iscell(value)
                codewords = reshape(value, 1, []);
            else
                codewords = {value};
            end
            if numel(codewords) ~= count
                error("sixgr:pusch:InvalidCodewordCount", ...
                    "This rank requires %d UL-SCH codeword(s), not %d.", ...
                    count, numel(codewords));
            end
            for cw = 1:count
                if ~(isnumeric(codewords{cw}) && isvector(codewords{cw}))
                    error("sixgr:pusch:InvalidCodewordSymbols", ...
                        "Codeword %d symbols must be a numeric vector.", cw - 1);
                end
                codewords{cw} = codewords{cw}(:);
            end
        end

        function layers = normalizeLayers(value, rank)
            if iscell(value)
                layers = value(:);
            elseif isnumeric(value) && ismatrix(value) && size(value, 2) == rank
                layers = cell(rank, 1);
                for layer = 1:rank
                    layers{layer} = value(:, layer);
                end
            elseif isnumeric(value) && isvector(value) && rank == 1
                layers = {value(:)};
            else
                error("sixgr:pusch:LayerDemappingCountMismatch", ...
                    "PUSCH layer input must provide exactly rank=%d streams.", rank);
            end
            if numel(layers) ~= rank
                error("sixgr:pusch:LayerDemappingCountMismatch", ...
                    "PUSCH layer input provides %d streams; rank=%d.", ...
                    numel(layers), rank);
            end
        end

        function value = info(rank, layerCounts, operation)
            index = zeros(1, rank);
            offset = 0;
            for cw = 1:numel(layerCounts)
                index(offset + (1:layerCounts(cw))) = cw - 1;
                offset = offset + layerCounts(cw);
            end
            value = struct( ...
                "Operation", operation, ...
                "Rank", rank, ...
                "NumCodewords", numel(layerCounts), ...
                "LayerCountPerCodeword", layerCounts, ...
                "CodewordIndexPerLayer", index, ...
                "IndexConvention", "zero_based", ...
                "Source", "3GPP_TS_38_211_6_3_1_3");
        end
    end
end
