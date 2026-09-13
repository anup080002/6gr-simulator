classdef UCIDecoder
    % Preserve the actual decoder's per-codeblock CRC outcome.
    methods (Static)
        function result=decode(llr,A)
            plan=sixgr.phy.pucch.UCIEncodingPlan(A,numel(llr));
            if ~plan.Valid
                error(plan.ErrorID,'UCI payload exceeds the pinned 1706-bit profile.');
            end
            applicable=plan.CRCBits>0;
            if A==0
                bits=int8(zeros(0,1)); rawErrors=false(0,1);
            else
                try
                    [bits,rawErrors]=nrUCIDecode(llr,A);
                catch cause
                    error('sixgr:phy:pucch:UCIDecodeFailed', ...
                        'nrUCIDecode failed for A=%d, E=%d: %s',A,numel(llr),cause.message);
                end
            end
            if applicable
                assert((islogical(rawErrors)||isnumeric(rawErrors)) && isreal(rawErrors) && ...
                    isvector(rawErrors) && numel(rawErrors)==plan.CodeBlocks && ...
                    all(isfinite(rawErrors(:))) && all(rawErrors(:)==0 | rawErrors(:)==1), ...
                    'sixgr:phy:pucch:MissingUCICRCEvidence', ...
                    'CRC-protected UCI requires one actual binary result per decoded code block.');
                passed=~any(rawErrors(:)); status="checked";
                errors=logical(rawErrors(:));
            else
                % No CRC exists for small-block UCI. Keep the boolean gate's
                % neutral value, but never label it a measured CRC pass.
                passed=true; status="not_applicable"; errors=false(0,1);
            end
            reason=""; if ~passed, reason="uci_crc_failed"; end
            result=struct('Bits',int8(bits(:)),'Plan',plan,'CRCPassed',logical(passed), ...
                'CRCApplicable',logical(applicable),'CRCStatus',status, ...
                'CodeBlockCRCError',errors,'FailureReason',reason);
        end
    end
end
