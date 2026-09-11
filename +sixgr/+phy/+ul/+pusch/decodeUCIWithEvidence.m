function [bits,evidence]=decodeUCIWithEvidence(llr,count,modulation)
% Received-only TS 38.212 UCI decoder evidence; no transmitted-bit oracle.
validateattributes(count,{'numeric'},{'scalar','integer','nonnegative','<=',1706});
evidence=struct('InformationBitCount',double(count),'CRCApplicable',count>=12, ...
    'CRCPass',NaN,'CodeBlockErrors',false(0,1),'DecodeUsable',false, ...
    'Source',"nrUCIDecode_received_LLR_and_code_block_error_flags", ...
    'Modulation',string(modulation));
bits=zeros(0,1,'int8');
if count==0, return; end
validateattributes(llr,{'single','double'},{'vector','real','nonempty','nonnan'});
[bits,errors]=nrUCIDecode(llr(:),count,char(modulation));
bits=int8(bits(:));
if evidence.CRCApplicable
    assert(islogical(errors) && ~isempty(errors),'sixgr:pusch:MissingUCICRC', ...
        'CRC-protected UCI requires actual per-code-block decoder error flags.');
    evidence.CodeBlockErrors=errors(:);
    evidence.CRCPass=double(~any(errors(:)));
end
evidence.DecodeUsable=numel(bits)==count && all(ismember(bits,int8([0 1]))) && ...
    (~evidence.CRCApplicable || evidence.CRCPass==1);
end
