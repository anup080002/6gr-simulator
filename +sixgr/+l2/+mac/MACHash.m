classdef MACHash
    %MACHASH Stable SHA-256 helpers for immutable MAC identities.

    methods (Static)
        function value = of(data)
            if isa(data, "uint8")
                bytes = data(:);
            elseif ischar(data) || isstring(data)
                bytes = uint8(unicode2native(char(string(data)), "UTF-8"));
                bytes = bytes(:);
            else
                bytes = uint8(unicode2native(jsonencode(data), "UTF-8"));
                bytes = bytes(:);
            end
            value = string(sixgr.rrc.asn1.asn1SHA256Hex(bytes));
        end

        function value = file(path)
            fileID = fopen(path, "rb");
            if fileID < 0
                error("sixgr:mac:MissingEvidenceSource", ...
                    "Cannot open %s.", string(path));
            end
            cleanup = onCleanup(@() fclose(fileID)); %#ok<NASGU>
            value = sixgr.l2.mac.MACHash.of(fread(fileID, inf, "*uint8"));
        end
    end
end
