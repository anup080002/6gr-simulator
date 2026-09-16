function result=receiveWithCSIPresence(pusch,rate,tbs,llr,context,initialIMCS,reportConfig,shortPolicy,coding)
% Receiver-owned CSI-present/absent interpretations of the SAME observation.
% A unique current-transmission TB CRC selects the data/UCI interpretation.
% Neither UE payload/length nor an old HARQ soft buffer selects presence.
% This is a receiver algorithm, not a claim of detector qualification or a
% 3GPP-mandated ambiguity resolver. No TB / no unique CRC stays unresolved.
names={'RV','MaxIterations','Algorithm','Nref','PresenceDecisionAlgorithm'};
assert(isstruct(coding) && isscalar(coding) && all(isfield(coding,names)) && ...
    isempty(setdiff(fieldnames(coding),names)), ...
    'sixgr:pusch:InvalidCSIPresenceCodingAuthority', ...
    'Presence selection accepts only receiver coding policy, never TX bits, lengths or prior soft buffers.');
algorithm=coding.PresenceDecisionAlgorithm;
assert(((ischar(algorithm) && isrow(algorithm)) || (isstring(algorithm) && isscalar(algorithm))) && ...
    isequal(string(algorithm),"unique_current_tb_crc"), ...
    'sixgr:pusch:InvalidCSIPresenceDecisionPolicy', ...
    'phy.pusch.csiPresenceDecisionAlgorithm must be unique_current_tb_crc.');
assert(isa(context,'sixgr.phy.ul.pusch.PUSCHUCIReceiveContext') && isscalar(context), ...
    'sixgr:pusch:MissingUCIReceiveContext','Use the independently installed receive context.');
budget=context.bitBudget(reportConfig);
assert(budget.OCSI1>0,'sixgr:pusch:MissingCSIReportConfiguration', ...
    'CSI presence selection needs an installed nominal CSI obligation.');
count=double(pusch.NumCodewords);
validateattributes(tbs,{'numeric'},{'vector','real','finite','integer','nonnegative','numel',count});
validateattributes(rate,{'numeric'},{'vector','real','finite','>',0,'<',1,'numel',count});
validateattributes(coding.RV,{'numeric'},{'vector','real','finite','integer','>=',0,'<=',3,'numel',count});
validateattributes(coding.MaxIterations,{'numeric'},{'scalar','real','finite','integer','positive'});
assert(iscell(coding.Nref) && numel(coding.Nref)==count, ...
    'sixgr:pusch:InvalidCSIPresenceCodingAuthority','Retain per-codeword receiver Nref authority.');
for cw=1:count
    if ~isempty(coding.Nref{cw})
        validateattributes(coding.Nref{cw},{'numeric'},{'scalar','real','finite','integer','positive'});
    end
end
absent=context.Data; absent.CSIReportConfigID=""; absent.CSIConfigurationEpoch=NaN;
absent=sixgr.phy.ul.pusch.PUSCHUCIReceiveContext(absent);
candidates={sixgr.phy.ul.pusch.PUSCHUCIDemultiplexer.receive( ...
    pusch,rate,tbs,llr,absent,initialIMCS,[],shortPolicy), ...
    sixgr.phy.ul.pusch.PUSCHUCIDemultiplexer.receive( ...
    pusch,rate,tbs,llr,context,initialIMCS,reportConfig,shortPolicy)};
[layers,~]=sixgr.phy.ul.pusch.PUSCHLayerMapper.layerCounts(pusch.NumLayers);
modulation=string(pusch.Modulation);
if isscalar(modulation), modulation=repmat(modulation,1,count); end
% CSI determines the owner even when an absent hypothesis has no UCI.
% The CRC of a different, unaffected codeword cannot establish CSI presence.
validateattributes(initialIMCS,{'numeric'}, ...
    {'vector','real','finite','integer','nonnegative','numel',count});
[~,owner]=max(initialIMCS);
crc=nan(2,count); attempted=false(2,count); passes=false(2,1);
dataEvidence=cell(2,1);
for k=1:2
    candidate=candidates{k}; layouts=cell(1,count);
    assert(all(tbs>0) || (count==1 && tbs==0), ...
        'sixgr:pusch:UnsupportedMixedZeroTBPresenceDecision', ...
        'Mixed empty/nonempty two-codeword presence decisions need explicit per-codeword handling.');
    if all(tbs>0)
        for cw=1:count
            if candidate.ULSCHMappingResolved(cw) && ~isempty(coding.Nref{cw})
                layouts{cw}=sixgr.phy.phycode.resolveCodingLayout('Direction','UL', ...
                    'TransportBlockSize',tbs(cw),'TargetCodeRate',rate(cw),'RV',coding.RV(cw), ...
                    'Modulation',modulation(cw),'NumLayers',layers(cw), ...
                    'RateMatchedBitCount',numel(candidate.ULSCHLLR{cw}),'Nref',coding.Nref{cw});
            end
        end
        data=sixgr.phy.ul.pusch.decodeResolvedULSCH(candidate.ULSCHLLR, ...
            candidate.ULSCHMappingResolved,pusch,tbs,rate,coding.RV,layouts, ...
            coding.MaxIterations,coding.Algorithm,[],[]);
        crc(k,:)=data.CRCPass; attempted(k,:)=data.DecodeAttempted;
        dataEvidence{k}=data;
        passes(k)=data.CRCAvailable(owner) && data.CRCPass(owner)==1;
    end
end
selected=find(passes);
resolved=isscalar(selected);
if resolved
    result=candidates{selected}; detected=selected==2;
    reason="unique_current_owner_TB_CRC";
else
    detected=false; selected=NaN;
    rejection=MException('sixgr:pusch:UnresolvedCSIPresence', ...
        'CSI presence has no unique current-transmission owner-codeword TB CRC.');
    if candidates{2}.PartialReception
        rejection=MException(char(candidates{2}.CSIRejectionIdentifier), ...
            '%s',char(candidates{2}.CSIRejectionMessage));
    end
    result=sixgr.phy.ul.pusch.receiveInvariantUCI( ...
        pusch,rate,tbs,llr,context,initialIMCS,reportConfig,rejection,shortPolicy);
    reason="no_unique_current_owner_TB_CRC";
end
evidence=struct('Algorithm',string(algorithm),'ReceiverContextDigest',context.Digest, ...
    'CandidatePresence',[false true],'CandidateContextDigests',[absent.Digest context.Digest], ...
    'OwnerCodeword',owner-1,'CandidateTBDecodeAttempted',attempted, ...
    'CandidateTBCRCPass',crc,'CandidateDataEvidence',{dataEvidence}, ...
    'SelectedCandidate',selected,'Resolved',resolved,'ReportDetected',detected, ...
    'PriorHARQSoftBufferUsed',false,'TransmitterMetadataUsed',false,'Reason',reason, ...
    'Source',"same_received_LLR_independent_CSI_interpretations_and_current_TB_CRC");
% The original installed obligation remains the capture/commit identity.
% Derived candidate identities are retained explicitly above, not hidden.
result.ReceiverContextDigest=context.Digest;
result.UCIReceiverEvidence.ReceiverContextDigest=context.Digest;
result.UCIReceiverEvidence.HARQMappingDigest=context.Data.HARQMappingDigest;
result.CSIPresenceResolved=resolved; result.CSIReportDetected=detected;
result.CSIPresenceEvidence=evidence;
result.UCIReceiverEvidence.CSIPresenceResolved=resolved;
result.UCIReceiverEvidence.CSIReportDetected=detected;
result.UCIReceiverEvidence.CSIPresenceEvidence=evidence;
result.Source="independent_CSI_presence_interpretations_and_received_ULSCH_CRC";
end
