classdef PUSCHUCIDemultiplexer
    %PUSCHUCIDEMULTIPLEXER Inverse typed UCI-on-PUSCH processing.

    methods (Static)
        function result = demultiplex(pusch, targetCodeRate, transportBlockSize, ...
                codewordLLR, expectedPayload, initialIMCS)
            if ~isa(expectedPayload, "sixgr.phy.ul.pusch.PUSCHUCIPayload")
                error("sixgr:pusch:MissingUCIPayload", ...
                    "UCI demultiplexing requires the expected typed payload contract.");
            end
            nCodewords = double(pusch.NumCodewords);
            targetCodeRate = localPerCodeword(targetCodeRate, nCodewords, "TargetCodeRate");
            transportBlockSize = localPerCodeword(transportBlockSize, nCodewords, "TransportBlockSize");
            initialIMCS = localPerCodeword(initialIMCS, nCodewords, "InitialIMCS");
            codewordLLR = localLLRCells(codewordLLR, nCodewords);
            owner = localOwner(expectedPayload, initialIMCS);
            p = expectedPayload.toStruct();
            combinedCSI2Length = p.OCSI2 + p.OCGUCI;

            if expectedPayload.hasPayload()
                [ulsch, ackLLR, csi1LLR, csi2LLR] = nrULSCHDemultiplex( ...
                    pusch, targetCodeRate, transportBlockSize, ...
                    p.OACK, p.OCSI1, combinedCSI2Length, ...
                    localUnwrapOne(codewordLLR));
            else
                ulsch = localUnwrapOne(codewordLLR);
                ackLLR = [];
                csi1LLR = [];
                csi2LLR = [];
            end
            ulsch = localLLRCells(ulsch, nCodewords);
            decodedACK = localDecode(ackLLR, p.OACK);
            decodedCSI1 = localDecode(csi1LLR, p.OCSI1);
            decodedCSI2Combined = localDecode(csi2LLR, combinedCSI2Length);
            decodedCSI2 = decodedCSI2Combined(1:p.OCSI2);
            decodedCGUCI = decodedCSI2Combined(p.OCSI2 + (1:p.OCGUCI));

            result = struct( ...
                "ULSCHLLR", {ulsch}, ...
                "OwnerCodeword", owner, ...
                "DecodedHARQACK", decodedACK, ...
                "DecodedCSIPart1", decodedCSI1, ...
                "DecodedCSIPart2", decodedCSI2, ...
                "DecodedConfiguredGrantUCI", decodedCGUCI, ...
                "HARQACKLLR", double(ackLLR(:)), ...
                "CSI1LLR", double(csi1LLR(:)), ...
                "CSI2AndCGUCILLR", double(csi2LLR(:)), ...
                "HARQACKCRCOK", isequal(decodedACK(:), expectedPayload.HARQACK(:)), ...
                "CSI1CRCOK", isequal(decodedCSI1(:), expectedPayload.CSIPart1(:)), ...
                "CSI2CRCOK", isequal(decodedCSI2(:), expectedPayload.CSIPart2(:)), ...
                "ConfiguredGrantUCIMatch", ...
                    isequal(decodedCGUCI(:), expectedPayload.ConfiguredGrantUCI(:)), ...
                "Source", "nrULSCHDemultiplex_nrUCIDecode_typed_payload");
        end
    end
end

function values = localPerCodeword(value, count, label)
values = double(value(:).');
if numel(values) ~= count || any(~isfinite(values))
    error("sixgr:pusch:InvalidUCIBitBudget", ...
        "%s must provide one finite value per codeword.", label);
end
end

function cells = localLLRCells(value, count)
if count == 1 && ~iscell(value)
    cells = {value};
elseif iscell(value)
    cells = reshape(value, 1, []);
else
    cells = {value};
end
if numel(cells) ~= count
    error("sixgr:pusch:InvalidUCIBitBudget", ...
        "Expected %d codeword LLR stream(s), received %d.", count, numel(cells));
end
for cw = 1:count
    cells{cw} = double(cells{cw}(:));
    if any(isnan(cells{cw}))
        error("sixgr:pusch:InvalidUCIBitBudget", ...
            "Codeword %d LLR stream contains NaN.", cw - 1);
    end
end
end

function owner = localOwner(payload, initialIMCS)
if ~payload.hasPayload() || numel(initialIMCS) == 1
    owner = 0;
    return;
end
[~, idx] = max(initialIMCS);
owner = idx - 1;
end

function bits = localDecode(llr, count)
if count == 0
    % Typed UCI payloads use canonical column vectors. Preserve that shape
    % for an absent field so optional CSI cannot falsify HARQ-ACK status.
    bits = zeros(0, 1, "int8");
    return;
end
if isempty(llr)
    error("sixgr:pusch:UCIProcessingUnavailable", ...
        "Mandatory UCI LLR stream is empty.");
end
bits = int8(nrUCIDecode(llr, count));
bits = bits(:);
end

function value = localUnwrapOne(cells)
if isscalar(cells)
    value = cells{1};
else
    value = cells;
end
end
