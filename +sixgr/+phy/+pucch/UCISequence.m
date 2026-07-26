classdef UCISequence
    %UCISEQUENCE Immutable serialized UCI sequence with ownership.

    properties (SetAccess=private)
        Index
        Bits
        Owners
        FieldNames
        Digest
    end

    methods
        function obj = UCISequence(index, bits, owners, fieldNames)
            bits = sixgr.phy.pucch.PUCCHUtil.bits(bits);
            owners = string(owners(:));
            fieldNames = string(fieldNames(:));
            if numel(bits) ~= numel(owners) || numel(bits) ~= numel(fieldNames)
                error("sixgr:phy:pucch:UCILengthMismatch", ...
                    "UCI sequence bit, owner and field vectors must align.");
            end
            obj.Index = double(index);
            obj.Bits = bits;
            obj.Owners = owners;
            obj.FieldNames = fieldNames;
            obj.Digest = sixgr.phy.pucch.PUCCHUtil.hash(struct( ...
                "Index", index, "Bits", bits.', "Owners", owners.', ...
                "FieldNames", fieldNames.'));
        end
    end
end
