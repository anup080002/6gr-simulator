classdef UCIEncodingPlan
    %UCIENCODINGPLAN Explicit TS 38.212 coding/rate-matching decision.

    properties (SetAccess=private)
        A
        E
        CodingFamily
        CRCPolynomial
        CRCBits
        Segmentation
        CodeBlocks
        TotalCRCBits
        CodeBlockPaddingBits
        InformationAndCRCBits
        CodeBlockInputBits
        Valid
        ErrorID
        RateMatchingDigest
        Digest
    end

    methods
        function obj = UCIEncodingPlan(A,E)
            A = double(A); E = double(E);
            if ~(isscalar(A) && isfinite(A) && A == fix(A) && A >= 0) || ...
                    ~(isscalar(E) && isfinite(E) && E == fix(E) && E >= 0)
                error("sixgr:phy:pucch:UCILengthMismatch", ...
                    "UCI coding A and E must be nonnegative integers.");
            end
            obj.A = A; obj.E = E; obj.ErrorID = "";
            obj.Valid = A <= 1706;
            if ~obj.Valid
                obj.ErrorID = "sixgr:phy:pucch:InvalidFormatPayload";
            end
            if A == 0
                obj.CodingFamily = "NO_UCI";
                obj.CRCPolynomial = "NONE"; obj.CRCBits = 0;
            elseif A <= 2
                obj.CodingFamily = "SMALL_BLOCK_1_2";
                obj.CRCPolynomial = "NONE"; obj.CRCBits = 0;
            elseif A <= 11
                obj.CodingFamily = "SMALL_BLOCK_3_11";
                obj.CRCPolynomial = "NONE"; obj.CRCBits = 0;
            elseif A <= 19
                obj.CodingFamily = "POLAR";
                obj.CRCPolynomial = "CRC6"; obj.CRCBits = 6;
            else
                obj.CodingFamily = "POLAR";
                obj.CRCPolynomial = "CRC11"; obj.CRCBits = 11;
            end
            obj.Segmentation = A >= 1013 || (A >= 360 && E >= 1088);
            obj.CodeBlocks = 1 + double(obj.Segmentation);
            % CRCBits is per code block, not the total allocation overhead.
            % TS 38.212 5.2.1 and 6.3.1.2: odd segmented payloads also
            % prepend one filler bit. It is not an information or CRC bit.
            obj.TotalCRCBits = obj.CodeBlocks * obj.CRCBits;
            obj.CodeBlockPaddingBits = obj.CodeBlocks * ceil(A/obj.CodeBlocks) - A;
            obj.InformationAndCRCBits = A + obj.TotalCRCBits;
            obj.CodeBlockInputBits = obj.InformationAndCRCBits + obj.CodeBlockPaddingBits;
            obj.RateMatchingDigest = sixgr.phy.pucch.PUCCHUtil.hash( ...
                struct("A",A,"E",E,"Family",obj.CodingFamily, ...
                "CRC",obj.CRCPolynomial,"Segmented",obj.Segmentation));
            obj.Digest = obj.RateMatchingDigest;
        end
    end

    methods (Static)
        function obj = create(A,E)
            obj = sixgr.phy.pucch.UCIEncodingPlan(A,E);
        end

        function result = fromVector(row)
            plan = sixgr.phy.pucch.UCIEncodingPlan( ...
                sixgr.phy.pucch.PUCCHUtil.number(row,"A"), ...
                sixgr.phy.pucch.PUCCHUtil.number(row,"E"));
            result = struct("A",plan.A,"E",plan.E, ...
                "Scheme",plan.CodingFamily, ...
                "CRCPolynomial",plan.CRCPolynomial, ...
                "CRCBits",plan.CRCBits, ...
                "SegmentationExpected",plan.Segmentation, ...
                "CodeBlocks",plan.CodeBlocks,"Valid",plan.Valid, ...
                "ErrorID",plan.ErrorID, ...
                "RateMatchingDigest",plan.RateMatchingDigest);
        end
    end
end
