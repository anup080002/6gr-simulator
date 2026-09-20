classdef PUSCHUCIMultiplexer
    %PUSCHUCIMULTIPLEXER Typed TS 38.212 UCI-on-PUSCH processing.

    methods (Static)
        function result = multiplex(pusch, targetCodeRate, transportBlockSize, ...
                ulschRateMatchedBits, payload, initialIMCS)
            experimental=isa(pusch,'sixgr.phy.research.PUSCHUCIResourceAdapter');
            if ~isa(pusch, "nrPUSCHConfig") && ~experimental
                error("sixgr:pusch:InvalidPUSCHConfiguration", ...
                    "UCI multiplexing requires a native configuration or explicit research adapter.");
            end
            if ~isa(payload, "sixgr.phy.ul.pusch.PUSCHUCIPayload")
                error("sixgr:pusch:MissingUCIPayload", ...
                    "UCI multiplexing requires a typed PUSCHUCIPayload.");
            end
            nCodewords = double(pusch.NumCodewords);
            targetCodeRate = localPerCodeword(targetCodeRate, nCodewords, "TargetCodeRate");
            transportBlockSize = localPerCodeword(transportBlockSize, nCodewords, "TransportBlockSize");
            initialIMCS = localPerCodeword(initialIMCS, nCodewords, "InitialIMCS");
            ulschRateMatchedBits = localBitCells( ...
                ulschRateMatchedBits, nCodewords, false);
            owner = localOwner(payload, initialIMCS);

            p = payload.toStruct();
            csi2Combined = [payload.CSIPart2; payload.ConfiguredGrantUCI];
            if experimental
                info=pusch.resourcePlan(targetCodeRate,transportBlockSize, ...
                    [p.OACK p.OCSI1 numel(csi2Combined)]);
            else
                info = nrULSCHInfo(pusch, targetCodeRate, transportBlockSize, ...
                    p.OACK, p.OCSI1, numel(csi2Combined));
            end
            gULSCH = double(info.GULSCH(:).');
            if numel(gULSCH) ~= nCodewords
                error("sixgr:pusch:InvalidUCIBitBudget", ...
                    "nrULSCHInfo did not return one GULSCH value per codeword.");
            end
            for cw = 1:nCodewords
                if numel(ulschRateMatchedBits{cw}) ~= gULSCH(cw)
                    error("sixgr:pusch:InvalidUCIBitBudget", ...
                        "Codeword %d UL-SCH stream has %d bits; GULSCH=%d.", ...
                        cw - 1, numel(ulschRateMatchedBits{cw}), gULSCH(cw));
                end
            end

            modulation = localModulation(pusch.Modulation, owner + 1);
            ack = localEncode(payload.HARQACK, info.GACK(owner + 1), modulation);
            csi1 = localEncode(payload.CSIPart1, info.GCSI1(owner + 1), modulation);
            csi2 = localEncode(csi2Combined, info.GCSI2(owner + 1), modulation);
            if experimental
                codewords=sixgr.phy.research.PUSCHUCIResourceAdapter.multiplex( ...
                    info,ulschRateMatchedBits{1},ack,csi1,csi2);
                names=["ULSCHIndices","ACKIndices","CSI1Indices","CSI2Indices"];
                muxInfo=struct();
                for k=1:4
                    index=info.StreamIndices{k}; muxInfo.(names(k))=uint32(index(index>0));
                end
                muxInfo.UCIXIndices=uint32(find(codewords==-1));
                muxInfo.UCIYIndices=uint32(find(codewords==-2)); muxInfo.QUCI=0;
            elseif payload.hasPayload()
                [codewords, muxInfo] = nrULSCHMultiplex( ...
                    pusch, targetCodeRate, transportBlockSize, ...
                    localUnwrapOne(ulschRateMatchedBits), ack, csi1, csi2);
            else
                codewords = localUnwrapOne(ulschRateMatchedBits);
                muxInfo = struct( ...
                    "ULSCHIndices", uint32((1:sum(gULSCH)).'), ...
                    "ACKIndices", uint32([]), ...
                    "CSI1Indices", uint32([]), ...
                    "CSI2Indices", uint32([]), ...
                    "UCIXIndices", uint32([]), ...
                    "UCIYIndices", uint32([]));
            end
            % nrULSCHMultiplex represents TS 38.212 placeholder bits as
            % -1/-2.  They are valid inputs to nrPUSCH and must remain
            % distinguishable until scrambling/modulation; accepting them
            % here is not a relaxation of the binary UL-SCH input contract.
            codewords = localBitCells(codewords, nCodewords, true);
            result = struct( ...
                "Codewords", {codewords}, ...
                "OwnerCodeword", owner, ...
                "Payload", p, ...
                "GPerCodeword", cellfun(@numel, codewords), ...
                "GULSCHPerCodeword", gULSCH, ...
                "GACK", double(info.GACK(:).'), ...
                "GCSI1", double(info.GCSI1(:).'), ...
                "GCSI2Combined", double(info.GCSI2(:).'), ...
                "ACKCodedBits", ack, ...
                "CSI1CodedBits", csi1, ...
                "CSI2AndCGUCICodedBits", csi2, ...
                "MuxInfo", muxInfo, ...
                "PlaceholderXCount", numel(sixgr.util.structGet(muxInfo, "UCIXIndices", [])), ...
                "PlaceholderYCount", numel(sixgr.util.structGet(muxInfo, "UCIYIndices", [])), ...
                "Source", "nrULSCHInfo_nrUCIEncode_nrULSCHMultiplex_typed_payload");
            if experimental
                result.Source="experimental_explicit_Qm_ULSCH_UCI_typed_payload";
                result.StandardNR=false;
            end
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

function cells = localBitCells(value, count, allowPlaceholders)
if count == 1 && ~iscell(value)
    cells = {value};
elseif iscell(value)
    cells = reshape(value, 1, []);
else
    cells = {value};
end
if numel(cells) ~= count
    error("sixgr:pusch:InvalidUCIBitBudget", ...
        "Expected %d codeword bit stream(s), received %d.", count, numel(cells));
end
for cw = 1:count
    bits = double(cells{cw}(:));
    accepted = bits == 0 | bits == 1;
    if allowPlaceholders
        accepted = accepted | bits == -1 | bits == -2;
    end
    if any(~isfinite(bits) | ~accepted)
        error("sixgr:pusch:InvalidUCIBitBudget", ...
            "UL-SCH codeword %d contains an invalid bit or placeholder value.", ...
            cw - 1);
    end
    cells{cw} = int8(bits);
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

function bits = localEncode(payload, g, modulation)
g = double(g);
if isempty(payload)
    bits = int8([]);
    if g ~= 0
        error("sixgr:pusch:InvalidUCIBitBudget", ...
            "Empty UCI payload received a nonzero coded-bit allocation G=%d.", g);
    end
    return;
end
if ~(isscalar(g) && isfinite(g) && g > 0 && g == fix(g))
    error("sixgr:pusch:InvalidUCIBitBudget", ...
        "Nonempty UCI payload requires a positive integer coded-bit allocation.");
end
bits = sixgr.phy.research.encodePUSCHUCI(payload, g, modulation);
bits = bits(:);
end

function value = localModulation(raw, index)
if iscell(raw)
    value = char(string(raw{index}));
else
    values = string(raw);
    value = char(values(index));
end
end

function value = localUnwrapOne(cells)
if isscalar(cells)
    value = cells{1};
else
    value = cells;
end
end
