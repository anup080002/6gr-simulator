classdef IndependentVectorCatalog
    %INDEPENDENTVECTORCATALOG Hash-verified independent vector files.
    methods (Static)
        function result = verify(path,expectedSHA256)
            path = string(path);
            if ~(isscalar(path) && isfile(path))
                error("sixgr:validation:OperatingPointMissing", ...
                    "Independent vector file is missing: %s.",path);
            end
            fid = fopen(path,"rb");
            if fid < 0
                error("sixgr:validation:OperatingPointMissing", ...
                    "Independent vector file cannot be opened: %s.",path);
            end
            cleanup = onCleanup(@()fclose(fid));
            bytes = fread(fid,Inf,"*uint8");
            actual = string(sixgr.util.sha256Hex(bytes));
            if nargin >= 2 && strlength(string(expectedSHA256)) > 0 && ...
                    lower(actual) ~= lower(string(expectedSHA256))
                error("sixgr:validation:OracleHashMismatch", ...
                    "Independent vector hash mismatch for %s.",path);
            end
            result = struct("Path",path,"ArtifactSHA256",lower(actual), ...
                "Status","PASS");
        end
    end
end
