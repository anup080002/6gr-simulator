classdef UCIEncoder
    %UCIENCODER Strict UCI encoder retaining sequence identity.

    methods (Static)
        function result = encode(sequence, E, modulation)
            if nargin < 3 || strlength(string(modulation)) == 0
                modulation = "QPSK";
            end
            if ~isa(sequence, "sixgr.phy.pucch.UCISequence")
                error("sixgr:phy:pucch:MissingUCIReportContext", ...
                    "UCIEncoder requires a typed UCISequence.");
            end
            plan = sixgr.phy.pucch.UCIEncodingPlan(numel(sequence.Bits),E);
            if ~plan.Valid
                error(plan.ErrorID, "UCI payload exceeds the pinned 1706-bit profile.");
            end
            if plan.A == 0
                coded = int8(zeros(0,1));
            elseif E <= 0
                error("sixgr:phy:pucch:UCILengthMismatch", ...
                    "A nonempty UCI sequence requires E > 0.");
            else
                coded = nrUCIEncode(sequence.Bits, E, char(string(modulation)));
            end
            result = struct("SequenceIndex",sequence.Index, ...
                "Plan",plan,"CodedBits",coded, ...
                "CodedDigest",sixgr.phy.pucch.PUCCHUtil.hash(coded.'));
        end
    end
end
