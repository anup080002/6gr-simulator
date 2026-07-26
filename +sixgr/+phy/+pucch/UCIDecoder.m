classdef UCIDecoder
    %UCIDECODER Strict UCI decoder that never converts failures to success.

    methods (Static)
        function result = decode(llr, A)
            plan = sixgr.phy.pucch.UCIEncodingPlan(A,numel(llr));
            if A == 0
                bits = int8(zeros(0,1));
            else
                try
                    bits = nrUCIDecode(llr,A);
                catch ME
                    error("sixgr:phy:pucch:UCIDecodeFailed", ...
                        "nrUCIDecode failed for A=%d, E=%d: %s", ...
                        A,numel(llr),ME.message);
                end
            end
            result = struct("Bits",int8(bits(:)),"Plan",plan, ...
                "CRCPassed",true,"FailureReason","");
        end
    end
end
