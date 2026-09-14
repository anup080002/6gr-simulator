function result=receiveInvariantUCI(pusch,targetCodeRate,transportBlockSize, ...
        codewordLLR,context,initialIMCS,reportConfig,rejection)
% Retain actual received fields only where every configured mapping agrees.
% A failed CSI interpretation is not a reason to discard independent ACK.
% This does not qualify a short-UCI detector or supply a missing TB CRC.
budget=context.bitBudget(reportConfig);
plan=sixgr.phy.ul.pusch.inspectUCIResourceInvariance(pusch,targetCodeRate, ...
    transportBlockSize,codewordLLR,context,initialIMCS,reportConfig);
if ~iscell(codewordLLR), codewordLLR={codewordLLR}; end
streams=cellfun(@(x)double(x(:)),reshape(codewordLLR,1,[]),'UniformOutput',false);
received=vertcat(streams{:});
modulation=string(pusch.Modulation);
assert(isscalar(modulation) || numel(modulation)==numel(streams), ...
    'sixgr:pusch:InvalidUCIBitBudget','Modulation must identify the UCI-owning codeword.');
if ~isscalar(modulation), modulation=modulation(plan.OwnerCodeword+1); end
[ack,ackLLR,ackEvidence]=localField(received,plan.HARQSourceIndices1Based, ...
    plan.HARQMappingInvariant,budget.OACK,modulation);
[csi1,csi1LLR,csi1Evidence]=localField(received,plan.CSI1SourceIndices1Based, ...
    plan.CSI1MappingInvariant,budget.OCSI1,modulation);
% Preserve the decoder's actual CRC/usability flags separately. A CRC-free
% decoded bit vector is not proof of a valid configured CSI report.
csi1Evidence.SchemaUsable=false;
csi1Evidence.SchemaRejectionIdentifier=string(rejection.identifier);
ulsch=cell(1,numel(streams));
for cw=1:numel(streams)
    ulsch{cw}=zeros(0,1);
    if plan.ULSCHMappingInvariant(cw)
        index=plan.ULSCHSourceIndices1Based{cw};
        ulsch{cw}=zeros(size(index));
        observed=index>0;
        ulsch{cw}(observed)=received(index(observed));
        % Remaining zeros are public-demultiplexer puncturing erasures,
        % never fabricated samples or a substituted unresolved codeword.
    end
end
csi2=zeros(0,1,'int8'); cguci=csi2; csi2LLR=zeros(0,1);
part2Count=NaN; authority="unresolved_received_csi_part1";
csi2Evidence=localUnavailable(NaN,modulation,"unresolved_information_length");
if isscalar(plan.CandidatePart2BitCounts)
    % A fixed configured length does not require selecting a received RI.
    % Its coded block can still carry independently usable configured UCI.
    part2Count=plan.CandidatePart2BitCounts(1);
    authority="single_length_in_active_report_configuration";
    source=streams; if isscalar(source), source=source{1}; end
    [~,~,~,csi2LLR]=nrULSCHDemultiplex(pusch,targetCodeRate,transportBlockSize, ...
        budget.OACK,budget.OCSI1,part2Count+budget.OCGUCI,source);
    [combined,csi2Evidence]=sixgr.phy.ul.pusch.decodeUCIWithEvidence( ...
        csi2LLR,part2Count+budget.OCGUCI,modulation);
    csi2Evidence.DecodeAttempted=part2Count+budget.OCGUCI>0;
    csi2=combined(1:part2Count);
    cguci=combined(part2Count+(1:budget.OCGUCI));
end
result=struct('ULSCHLLR',{ulsch},'ULSCHMappingResolved',plan.ULSCHMappingInvariant, ...
    'OwnerCodeword',plan.OwnerCodeword, ...
    'ResolvedCSI1BitCount',budget.OCSI1,'ResolvedCSI2BitCount',part2Count, ...
    'CSI2LengthAuthority',authority,'CSIPart1DecodedBeforePart2',false, ...
    'DecodedHARQACK',ack,'DecodedCSIPart1',csi1,'DecodedCSIPart2',csi2, ...
    'DecodedConfiguredGrantUCI',cguci,'HARQACKLLR',ackLLR,'CSI1LLR',csi1LLR, ...
    'CSI2AndCGUCILLR',double(csi2LLR(:)), ...
    'HARQACKCRCOK',ackEvidence.CRCPass,'CSI1CRCOK',csi1Evidence.CRCPass, ...
    'CSI2CRCOK',csi2Evidence.CRCPass,'PartialReception',true, ...
    'CSIPart1Usable',false,'CSIRejectionIdentifier',string(rejection.identifier), ...
    'CSIRejectionMessage',string(rejection.message),'ResourceResolution',plan, ...
    'UCIReceiverEvidence',struct('HARQACK',ackEvidence,'CSI1',csi1Evidence, ...
        'CSI2AndConfiguredGrantUCI',csi2Evidence,'CSIPart1Usable',false, ...
        'CSI2LengthAuthority',authority,'CSIPart1DecodedBeforePart2',false, ...
        'ResolvedCSI1BitCount',budget.OCSI1,'ResolvedCSI2BitCount',part2Count), ...
    'Source',"received_LLR_with_configured_invariant_resource_mapping");
end

function [bits,llr,evidence]=localField(received,index,invariant,count,modulation)
bits=zeros(0,1,'int8'); llr=zeros(0,1);
if ~invariant
    evidence=localUnavailable(count,modulation,"unresolved_resource_mapping");
    return;
end
llr=received(index);
[bits,evidence]=sixgr.phy.ul.pusch.decodeUCIWithEvidence(llr,count,modulation);
evidence.DecodeAttempted=count>0;
evidence.ResourceMappingResolved=true;
end

function evidence=localUnavailable(count,modulation,reason)
% Unavailable metadata, not a failed CRC or a zero-information decoded row.
applicable=NaN; if isfinite(count), applicable=double(count>=12); end
evidence=struct('InformationBitCount',count,'CRCApplicable',applicable, ...
    'CRCPass',NaN,'CodeBlockErrors',false(0,1),'DecodeUsable',false, ...
    'DecodeAttempted',false,'ResourceMappingResolved',false, ...
    'Source',"not_decoded",'Reason',reason,'Modulation',modulation);
end
