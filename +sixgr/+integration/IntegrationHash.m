classdef IntegrationHash
    %INTEGRATIONHASH Stable SHA-256 helpers for configuration and evidence.
    methods (Static)
        function value = bytes(input)
            if ischar(input) || isstring(input)
                input = uint8(unicode2native(char(string(input)),"UTF-8"));
            else
                input = uint8(input(:));
            end
            value = string(sixgr.util.sha256Hex(input));
        end
        function value = file(path)
            path = char(string(path));
            if ~isfile(path)
                error("sixgr:integration:StaleArtifact", ...
                    "Cannot hash missing artifact %s.",path);
            end
            fileID = fopen(path,"rb");
            if fileID < 0
                error("sixgr:integration:StaleArtifact", ...
                    "Cannot open artifact %s.",path);
            end
            cleanup = onCleanup(@() fclose(fileID));
            bytes = fread(fileID,inf,"*uint8");
            clear cleanup
            value = string(sixgr.util.sha256Hex(bytes));
        end
        function value = data(input)
            encoded = jsonencode(input,"PrettyPrint",false);
            value = sixgr.integration.IntegrationHash.bytes(encoded);
        end
    end
end
