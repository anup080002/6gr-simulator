classdef PUSCHUCIDemultiplexer
    %PUSCHUCIDEMULTIPLEXER Inverse typed UCI-on-PUSCH processing.

    methods (Static)
        function result = demultiplex(pusch, targetCodeRate, transportBlockSize, ...
                codewordLLR, expectedPayload, initialIMCS, reportConfig)
            if nargin<7, reportConfig=[]; end
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
            sizeSource="explicit_fixed_length_uci_contract";
            part1First=false;
            if ~isempty(reportConfig) && p.OCSI1>0
                assert(isa(reportConfig,'sixgr.phy.mimo.CSIReportConfiguration'), ...
                    'sixgr:pusch:MissingCSIReportConfiguration', ...
                    'Runtime CSI decoding requires its active immutable report configuration.');
                assert(reportConfig.UCIChannel=="PUSCH", ...
                    'sixgr:pusch:CSITransportLayoutMismatch', ...
                    'PUSCH demultiplexing requires the PUSCH CSI layout, not unchanged PUCCH report bits.');
                p.OCSI1=reportConfig.part1BitCount();
                modulation=string(pusch.Modulation);
                if ~isscalar(modulation), modulation=modulation(owner+1); end
                % For UL-SCH, CSI1 resources do not depend on CSI2 size.
                % UCI-only additionally depends on presence (not size), so
                % consider only presence states permitted by configuration.
                presence=unique((reportConfig.part2BitCountCandidates()+p.OCGUCI)>0);
                if transportBlockSize(owner+1)>0, presence=false; end
                matches=0; resolvedCount=NaN; firstBits=int8([]);
                for present=reshape(presence,1,[])
                    [~,~,firstLLR,~]=nrULSCHDemultiplex(pusch,targetCodeRate,transportBlockSize, ...
                        p.OACK,p.OCSI1,double(present),localUnwrapOne(codewordLLR));
                    [bits,evidence]=sixgr.phy.ul.pusch.decodeUCIWithEvidence(firstLLR,p.OCSI1,modulation);
                    if ~evidence.DecodeUsable, continue; end
                    [~,resolved]=reportConfig.decodePart1(bits);
                    count=resolved.part2BitCount();
                    if transportBlockSize(owner+1)==0 && (count+p.OCGUCI>0)~=present, continue; end
                    matches=matches+1; resolvedCount=count; firstBits=bits;
                end
                assert(matches==1,'sixgr:pusch:UnresolvedReceivedCSIPart1', ...
                    'CSI Part 2/UL-SCH cannot be demapped without one usable received Part-1 interpretation.');
                p.OCSI2=resolvedCount;
                sizeSource="received_csi_part1_and_active_report_configuration";
                part1First=true;
            end
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
            modulation=string(pusch.Modulation);
            assert(isscalar(modulation) || numel(modulation)==nCodewords, ...
                'sixgr:pusch:InvalidUCIBitBudget','Modulation must identify the actual UCI-owning codeword.');
            if ~isscalar(modulation), modulation=modulation(owner+1); end
            [decodedACK,ackEvidence] = sixgr.phy.ul.pusch.decodeUCIWithEvidence(ackLLR,p.OACK,modulation);
            [decodedCSI1,csi1Evidence] = sixgr.phy.ul.pusch.decodeUCIWithEvidence(csi1LLR,p.OCSI1,modulation);
            if part1First
                assert(isequal(decodedCSI1,firstBits),'sixgr:pusch:CSI1ResourceMappingMismatch', ...
                    'Resolving CSI Part-2 size must not change received CSI Part-1 resources.');
            end
            [decodedCSI2Combined,csi2Evidence] = sixgr.phy.ul.pusch.decodeUCIWithEvidence(csi2LLR,combinedCSI2Length,modulation);
            decodedCSI2 = decodedCSI2Combined(1:p.OCSI2);
            decodedCGUCI = decodedCSI2Combined(p.OCSI2 + (1:p.OCGUCI));

            result = struct( ...
                "ULSCHLLR", {ulsch}, ...
                "OwnerCodeword", owner, ...
                "ResolvedCSI1BitCount",p.OCSI1,"ResolvedCSI2BitCount",p.OCSI2, ...
                "CSI2LengthAuthority",sizeSource,"CSIPart1DecodedBeforePart2",part1First, ...
                "DecodedHARQACK", decodedACK, ...
                "DecodedCSIPart1", decodedCSI1, ...
                "DecodedCSIPart2", decodedCSI2, ...
                "DecodedConfiguredGrantUCI", decodedCGUCI, ...
                "HARQACKLLR", double(ackLLR(:)), ...
                "CSI1LLR", double(csi1LLR(:)), ...
                "CSI2AndCGUCILLR", double(csi2LLR(:)), ...
                "HARQACKCRCOK", ackEvidence.CRCPass, ...
                "CSI1CRCOK", csi1Evidence.CRCPass, ...
                "CSI2CRCOK", csi2Evidence.CRCPass, ...
                "HARQACKContentMatch", isequal(decodedACK(:), expectedPayload.HARQACK(:)), ...
                "CSI1ContentMatch", isequal(decodedCSI1(:), expectedPayload.CSIPart1(:)), ...
                "CSI2ContentMatch", isequal(decodedCSI2(:), expectedPayload.CSIPart2(:)), ...
                "UCIReceiverEvidence",struct('HARQACK',ackEvidence,'CSI1',csi1Evidence, ...
                    'CSI2AndConfiguredGrantUCI',csi2Evidence, ...
                    'CSI2LengthAuthority',sizeSource, ...
                    'CSIPart1DecodedBeforePart2',part1First, ...
                    'ResolvedCSI1BitCount',p.OCSI1,'ResolvedCSI2BitCount',p.OCSI2), ...
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

function value = localUnwrapOne(cells)
if isscalar(cells)
    value = cells{1};
else
    value = cells;
end
end
