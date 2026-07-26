classdef PairedRNGStreams
    %PAIREDRNGSTREAMS Deterministic streams shared by impact pair members.

    methods (Static)
        function streams = resolve(row, seedList)
            pairID = localText(row, "PairID", "unpaired");
            designCell = localText(row, "DesignCell", "");
            seeds = double(seedList(:).');
            if isempty(seeds) || any(~isfinite(seeds) | seeds ~= fix(seeds))
                error("sixgr:pusch:ImpactSeedListInvalid", ...
                    "Impact SeedList must contain finite integers.");
            end
            key = char(pairID + "|" + designCell);
            digest = char(sixgr.util.sha256Hex(uint8(unicode2native(key, "UTF-8"))));
            offset = mod(hex2dec(digest(1:8)), 2^31 - 1);
            base = mod(seeds(1) + offset, 2^31 - 1);
            streams = struct( ...
                "Seed", double(base), ...
                "PayloadSeed", double(mod(base + 101, 2^31 - 1)), ...
                "ChannelSeed", double(mod(base + 211, 2^31 - 1)), ...
                "NoiseSeed", double(mod(base + 307, 2^31 - 1)), ...
                "PayloadRNGStreamID", "payload_" + string(base + 101), ...
                "ChannelRNGStreamID", "channel_" + string(base + 211), ...
                "NoiseRNGStreamID", "noise_" + string(base + 307));
        end
    end
end
function value = localText(row, name, defaultValue)
if istable(row)
    if ismember(name, string(row.Properties.VariableNames))
        value = string(row.(name)(1));
    else
        value = string(defaultValue);
    end
elseif isstruct(row) && isfield(row, name)
    value = string(row.(name));
else
    value = string(defaultValue);
end
if ismissing(value) || strlength(strtrim(value)) == 0
    value = string(defaultValue);
end
end
