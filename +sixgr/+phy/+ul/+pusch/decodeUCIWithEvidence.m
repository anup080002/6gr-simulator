function [bits,evidence]=decodeUCIWithEvidence(llr,count,modulation,shortPolicy)
% Received-only TS 38.212 UCI decoder evidence; no transmitted-bit oracle.
if nargin<4, shortPolicy=sixgr.phy.ul.pusch.resolveShortUCIDecisionPolicy(); end
shortPolicy=sixgr.phy.ul.pusch.resolveShortUCIDecisionPolicy(shortPolicy);
validateattributes(count,{'numeric'},{'scalar','integer','nonnegative','<=',1706});
evidence=struct('InformationBitCount',double(count),'CRCApplicable',count>=12, ...
    'CRCPass',NaN,'CodeBlockErrors',false(0,1),'DecodeUsable',false, ...
    'Source',"nrUCIDecode_received_LLR_and_code_block_error_flags", ...
    'Modulation',string(modulation),'DecoderWordUsable',false, ...
    'ShortConfidenceApplicable',count>0 && count<12,'ShortConfidence',struct());
evidence.StandardNR=string(modulation)~="1024QAM";
if ~evidence.StandardNR
    evidence.Source="experimental_Qm10_UCI_received_LLR_and_native_coding_primitives";
    evidence.ResearchClass="optional_research_experiment";
end
bits=zeros(0,1,'int8');
if count==0, return; end
validateattributes(llr,{'single','double'},{'vector','real','nonempty','nonnan'});
if string(modulation)=="1024QAM" && count<=2
    % Experimental square-QAM extension: only the first two bit positions
    % per symbol carry the short mother code; x filler carries no evidence.
    positions=mod((0:numel(llr)-1).',10);
    [bits,errors]=nrUCIDecode(llr(positions<2),count,'QPSK');
else
    [bits,errors]=nrUCIDecode(llr(:),count,char(modulation));
end
bits=int8(bits(:));
if evidence.CRCApplicable
    assert(islogical(errors) && ~isempty(errors),'sixgr:pusch:MissingUCICRC', ...
        'CRC-protected UCI requires actual per-code-block decoder error flags.');
    evidence.CodeBlockErrors=errors(:);
    evidence.CRCPass=double(~any(errors(:)));
end
evidence.DecoderWordUsable=numel(bits)==count && all(ismember(bits,int8([0 1]))) && ...
    (~evidence.CRCApplicable || evidence.CRCPass==1);
evidence.DecodeUsable=evidence.DecoderWordUsable;
if evidence.ShortConfidenceApplicable
    evidence.ShortConfidence=sixgr.phy.ul.pusch.shortUCICodewordConfidence( ...
        llr,bits,count,modulation,shortPolicy);
    evidence.DecodeUsable=evidence.DecoderWordUsable && evidence.ShortConfidence.Accepted;
end
end
