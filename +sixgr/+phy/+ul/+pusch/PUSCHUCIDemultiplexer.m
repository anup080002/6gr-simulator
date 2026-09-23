classdef PUSCHUCIDemultiplexer
    %PUSCHUCIDEMULTIPLEXER Inverse typed UCI-on-PUSCH processing.

    methods (Static)
        function result = demultiplex(pusch, targetCodeRate, transportBlockSize, ...
                codewordLLR, expectedPayload, initialIMCS, reportConfig, shortPolicy)
            if nargin<7, reportConfig=[]; end
            if nargin<8, shortPolicy=sixgr.phy.ul.pusch.resolveShortUCIDecisionPolicy(); end
            if ~isa(expectedPayload, "sixgr.phy.ul.pusch.PUSCHUCIPayload")
                error("sixgr:pusch:MissingUCIPayload", ...
                    "UCI demultiplexing requires the expected typed payload contract.");
            end
            % Legacy/component adapter: lengths still originate at TX here.
            % Runtime callers must migrate to receive with a gNB-owned schema;
            % this adapter is not evidence of independent reception.
            reference=expectedPayload.toStruct();
            p=struct('OACK',reference.OACK,'OCSI1',reference.OCSI1, ...
                'OCSI2',reference.OCSI2,'OCGUCI',reference.OCGUCI);
            result = sixgr.phy.ul.pusch.PUSCHUCIDemultiplexer.decodeSchema( ...
                pusch,targetCodeRate,transportBlockSize,codewordLLR, ...
                p,initialIMCS,reportConfig,false,shortPolicy);
            scoring = sixgr.phy.ul.pusch.PUSCHUCIDemultiplexer.score(result,expectedPayload);
            for name=reshape(string(fieldnames(scoring)),1,[])
                result.(name)=scoring.(name);
            end
            result.Source="nrULSCHDemultiplex_nrUCIDecode_typed_payload";
            if isa(pusch,'sixgr.phy.research.PUSCHUCIResourceAdapter')
                result.Source="experimental_explicit_Qm_UCI_typed_payload_component";
                result.StandardNR=false;
            end
        end

        function result = receive(pusch,targetCodeRate,transportBlockSize, ...
                codewordLLR,context,initialIMCS,reportConfig,shortPolicy)
            % Payload-free receive boundary. No TX bits, lengths or scoring.
            if nargin<7, reportConfig=[]; end
            if nargin<8, shortPolicy=sixgr.phy.ul.pusch.resolveShortUCIDecisionPolicy(); end
            assert(isa(context,'sixgr.phy.ul.pusch.PUSCHUCIReceiveContext') && isscalar(context), ...
                'sixgr:pusch:MissingUCIReceiveContext', ...
                'PUSCH reception requires its independently installed receive schema.');
            p=context.bitBudget(reportConfig);
            try
                result=sixgr.phy.ul.pusch.PUSCHUCIDemultiplexer.decodeSchema( ...
                    pusch,targetCodeRate,transportBlockSize,codewordLLR,p,initialIMCS,reportConfig,true,shortPolicy);
                result.ULSCHMappingResolved=true(1,double(pusch.NumCodewords));
                result.CSIPart1Usable=p.OCSI1>0 && ~isempty(reportConfig) && ...
                    result.UCIReceiverEvidence.CSI1.DecodeUsable;
                result.PartialReception=false;
                result.CSIRejectionIdentifier="";
            catch err
                % Only received CSI interpretation failures permit partial
                % reception. Invalid configuration, ownership, resource and
                % implementation errors remain fatal, never rescue paths.
                receivedErrors=["sixgr:pusch:UnresolvedReceivedCSIPart1", ...
                    "sixgr:mimo:InvalidCRI","sixgr:mimo:InvalidRI", ...
                    "sixgr:mimo:InvalidCSIPadding", ...
                    "sixgr:mimo:InvalidTypeIINonzeroCounts","sixgr:mimo:InvalidTypeIIInactiveCount"];
                if p.OCSI1==0 || ~ismember(string(err.identifier),receivedErrors)
                    rethrow(err);
                end
                result=sixgr.phy.ul.pusch.receiveInvariantUCI( ...
                    pusch,targetCodeRate,transportBlockSize,codewordLLR, ...
                    context,initialIMCS,reportConfig,err,shortPolicy);
            end
            result.ReceiverContextDigest=context.Digest;
            result.UCIReceiverEvidence.ReceiverContextDigest=context.Digest;
            result.UCIReceiverEvidence.HARQMappingDigest=context.Data.HARQMappingDigest;
            if ~result.PartialReception
                result.Source="nrULSCHDemultiplex_nrUCIDecode_independent_receive_schema";
            end
            if isa(pusch,'sixgr.phy.research.PUSCHUCIResourceAdapter')
                result.Source="experimental_explicit_Qm_UCI_independent_receive_schema";
                result.StandardNR=false;
            end
        end

        function scoring = score(result,payload)
            % Optional post-reception comparison; never changes RX evidence.
            assert(isa(payload,'sixgr.phy.ul.pusch.PUSCHUCIPayload') && isscalar(payload), ...
                'sixgr:pusch:MissingUCIPayload','Scoring requires a typed TX reference.');
            scoring=struct( ...
                'HARQACKContentMatch',isequal(result.DecodedHARQACK(:),payload.HARQACK(:)), ...
                'CSI1ContentMatch',isequal(result.DecodedCSIPart1(:),payload.CSIPart1(:)), ...
                'CSI2ContentMatch',isequal(result.DecodedCSIPart2(:),payload.CSIPart2(:)), ...
                'ConfiguredGrantUCIMatch',isequal(result.DecodedConfiguredGrantUCI(:),payload.ConfiguredGrantUCI(:)));
        end
    end

    methods (Static, Access=private)
        function result = decodeSchema(pusch,targetCodeRate,transportBlockSize, ...
                codewordLLR,p,initialIMCS,reportConfig,independentReceive,shortPolicy)
            shortPolicy=sixgr.phy.ul.pusch.resolveShortUCIDecisionPolicy(shortPolicy);
            nCodewords = double(pusch.NumCodewords);
            targetCodeRate = localPerCodeword(targetCodeRate, nCodewords, "TargetCodeRate");
            transportBlockSize = localPerCodeword(transportBlockSize, nCodewords, "TransportBlockSize");
            initialIMCS = localPerCodeword(initialIMCS, nCodewords, "InitialIMCS");
            codewordLLR = localLLRCells(codewordLLR, nCodewords);
            owner = localOwner(p, initialIMCS);
            sizeSource="explicit_fixed_length_uci_contract";
            part1First=false;
            if ~isempty(reportConfig) && p.OCSI1>0
                assert(isa(reportConfig,'sixgr.phy.mimo.CSIReportConfiguration'), ...
                    'sixgr:pusch:MissingCSIReportConfiguration', ...
                    'Runtime CSI decoding requires its active immutable report configuration.');
                assert(reportConfig.UCIChannel=="PUSCH", ...
                    'sixgr:pusch:CSITransportLayoutMismatch', ...
                    'PUSCH demultiplexing requires a PUSCH receive binding while retaining the configured CSI reporting format.');
                p.OCSI1=reportConfig.part1BitCount();
                modulation=string(pusch.Modulation);
                if ~isscalar(modulation), modulation=modulation(owner+1); end
                % For UL-SCH, CSI1 resources do not depend on CSI2 size.
                % UCI-only additionally depends on presence (not size), so
                % consider only presence states permitted by configuration.
                presence=unique((reportConfig.part2BitCountCandidates()+p.OCGUCI)>0);
                if transportBlockSize(owner+1)>0, presence=false; end
                matches=0; resolvedCount=NaN; firstBits=int8([]); lastRejection=[];
                for present=reshape(presence,1,[])
                    [~,~,firstLLR,~]=sixgr.phy.ul.pusch.demultiplexUCIStreams(pusch,targetCodeRate,transportBlockSize, ...
                        p.OACK,p.OCSI1,double(present),localUnwrapOne(codewordLLR));
                    [bits,evidence]=sixgr.phy.ul.pusch.decodeUCIWithEvidence(firstLLR,p.OCSI1,modulation,shortPolicy);
                    if ~evidence.DecodeUsable, continue; end
                    try
                        [~,resolved]=reportConfig.decodePart1(bits);
                    catch err
                        if ~independentReceive || ~ismember(string(err.identifier), ...
                                ["sixgr:mimo:InvalidCRI","sixgr:mimo:InvalidRI","sixgr:mimo:InvalidCSIPadding", ...
                                 "sixgr:mimo:InvalidTypeIINonzeroCounts","sixgr:mimo:InvalidTypeIIInactiveCount"])
                            rethrow(err);
                        end
                        % A wrong UCI-only presence interpretation must not
                        % prevent checking another configured presence state.
                        lastRejection=err;
                        continue;
                    end
                    count=resolved.part2BitCount();
                    if transportBlockSize(owner+1)==0 && (count+p.OCGUCI>0)~=present, continue; end
                    matches=matches+1; resolvedCount=count; firstBits=bits;
                end
                if matches==0 && ~isempty(lastRejection), rethrow(lastRejection); end
                assert(matches==1,'sixgr:pusch:UnresolvedReceivedCSIPart1', ...
                    'CSI Part 2/UL-SCH cannot be demapped without one usable received Part-1 interpretation.');
                p.OCSI2=resolvedCount;
                sizeSource="received_csi_part1_and_active_report_configuration";
                part1First=true;
            end
            combinedCSI2Length = p.OCSI2 + p.OCGUCI;

            if p.OACK+p.OCSI1+p.OCSI2+p.OCGUCI>0
                [ulsch, ackLLR, csi1LLR, csi2LLR] = sixgr.phy.ul.pusch.demultiplexUCIStreams( ...
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
            [decodedACK,ackEvidence] = sixgr.phy.ul.pusch.decodeUCIWithEvidence(ackLLR,p.OACK,modulation,shortPolicy);
            [decodedCSI1,csi1Evidence] = sixgr.phy.ul.pusch.decodeUCIWithEvidence(csi1LLR,p.OCSI1,modulation,shortPolicy);
            if part1First
                assert(isequal(decodedCSI1,firstBits),'sixgr:pusch:CSI1ResourceMappingMismatch', ...
                    'Resolving CSI Part-2 size must not change received CSI Part-1 resources.');
            end
            [decodedCSI2Combined,csi2Evidence] = sixgr.phy.ul.pusch.decodeUCIWithEvidence(csi2LLR,combinedCSI2Length,modulation,shortPolicy);
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
                "UCIReceiverEvidence",struct('HARQACK',ackEvidence,'CSI1',csi1Evidence, ...
                    'CSI2AndConfiguredGrantUCI',csi2Evidence, ...
                    'CSI2LengthAuthority',sizeSource, ...
                    'CSIPart1DecodedBeforePart2',part1First, ...
                    'ResolvedCSI1BitCount',p.OCSI1,'ResolvedCSI2BitCount',p.OCSI2), ...
                "Source", "nrULSCHDemultiplex_nrUCIDecode_receive_schema_core");
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

function owner = localOwner(p, initialIMCS)
if p.OACK+p.OCSI1+p.OCSI2+p.OCGUCI==0 || numel(initialIMCS) == 1
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
