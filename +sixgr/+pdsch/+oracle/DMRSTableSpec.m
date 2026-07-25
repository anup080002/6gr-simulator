classdef DMRSTableSpec
    %DMRSTABLESPEC Independent Prompt-02 DM-RS table oracle.
    %
    % This oracle intentionally calls neither production PDSCH code nor
    % MATLAB 5G Toolbox nr* functions.

    methods (Static)
        function result = symbolPositions(request)
            mapping = upper(strtrim(string(request.MappingType)));
            dmrsLength = double(request.DMRSLength);
            start = double(request.PDSCHStartSymbol);
            ld = double(request.PDSCHDurationLd);
            typeAPosition = double(request.DMRSTypeAPosition);
            additional = double(request.DMRSAdditionalPosition);

            tableLd = ld;
            if mapping == "A"
                tableLd = start + ld;
            end
            raw = sixgr.pdsch.oracle.DMRSTableSpec.lookup( ...
                mapping, dmrsLength, tableLd, additional);
            if isempty(raw)
                result = struct("Symbols", zeros(1, 0), ...
                    "Count", 0, "Status", "ERROR", ...
                    "ErrorToken", "UnsupportedDMRSPositionCombination");
                return;
            end
            values = zeros(size(raw));
            for i = 1:numel(raw)
                switch raw(i)
                    case -1
                        if mapping == "A"
                            values(i) = typeAPosition;
                        else
                            values(i) = start;
                        end
                    case -2
                        values(i) = 11;
                    otherwise
                        if mapping == "A"
                            values(i) = raw(i);
                        else
                            values(i) = start + raw(i);
                        end
                end
            end
            if dmrsLength == 2
                values = reshape([values; values + 1], 1, []);
            end
            if any(values < start | values >= start + ld)
                result = struct("Symbols", double(values(:).'), ...
                    "Count", numel(values), "Status", "ERROR", ...
                    "ErrorToken", "UnsupportedDMRSPositionCombination");
            else
                result = struct("Symbols", double(values(:).'), ...
                    "Count", numel(values), "Status", "PASS", ...
                    "ErrorToken", "");
            end
        end

        function result = port(configType, dmrsLength, multiplexing, port)
            configType = double(configType);
            dmrsLength = double(dmrsLength);
            port = double(port);
            enhanced = lower(strtrim(string(multiplexing))) == "enhanced";

            if configType == 1 && dmrsLength == 1 && ~enhanced
                valid = 0:3;
            elseif configType == 2 && dmrsLength == 1 && ~enhanced
                valid = 0:5;
            elseif configType == 1 && dmrsLength == 2 && ~enhanced
                valid = 0:7;
            elseif configType == 2 && dmrsLength == 2 && ~enhanced
                valid = 0:11;
            elseif configType == 1 && dmrsLength == 1
                valid = [0 1 2 3 8 9 10 11];
            elseif configType == 2 && dmrsLength == 1
                valid = [0 1 2 3 4 5 12 13 14 15 16 17];
            elseif configType == 1
                valid = 0:15;
            else
                valid = 0:23;
            end
            if ~ismember(port, valid)
                result = struct("Status", "ERROR", ...
                    "ErrorToken", "DMRSPortUnsupportedForConfiguration");
                return;
            end

            if configType == 1
                group = floor(mod(port, 4) / 2);
                delta = group;
                block = floor(port / 4);
                if port < 8
                    evenPattern = [1 1 1 1];
                    oddPattern = [1 -1 1 -1];
                else
                    evenPattern = [1 1 -1 -1];
                    oddPattern = [1 -1 -1 1];
                end
            else
                group = floor(mod(port, 6) / 2);
                delta = 2 * group;
                block = floor(port / 6);
                if block == 0
                    evenPattern = [1 1 1 1];
                    oddPattern = [1 -1 1 -1];
                else
                    evenPattern = [1 1 -1 -1];
                    oddPattern = [1 -1 -1 1];
                end
            end
            if mod(port, 2) == 0
                wf = evenPattern;
            else
                wf = oddPattern;
            end
            if mod(block, 2) == 0
                wt = [1 1];
            else
                wt = [1 -1];
            end
            if dmrsLength == 2
                lprime = [0 1];
            else
                lprime = 0;
            end
            result = struct( ...
                "Status", "PASS", "ErrorToken", "", ...
                "LogicalPort", port, ...
                "PhysicalAntennaPort", 1000 + port, ...
                "SupportedLPrime", lprime, ...
                "CDMGroupLambda", group, "Delta", delta, ...
                "WF", wf, "WT", wt);
        end
    end

    methods (Static, Access = private)
        function raw = lookup(mapping, dmrsLength, ld, additional)
            raw = [];
            variants = {};
            if mapping == "A" && dmrsLength == 1
                if ismember(ld, 3:7)
                    variants = {[-1],[-1],[-1],[-1]};
                elseif ismember(ld, 8:9)
                    variants = {[-1],[-1 7],[-1 7],[-1 7]};
                elseif ismember(ld, 10:11)
                    variants = {[-1],[-1 9],[-1 6 9],[-1 6 9]};
                elseif ld == 12
                    variants = {[-1],[-1 9],[-1 6 9],[-1 5 8 11]};
                elseif ismember(ld, 13:14)
                    variants = {[-1],[-1 -2],[-1 7 11],[-1 5 8 11]};
                end
            elseif mapping == "B" && dmrsLength == 1
                if ismember(ld, 2:4)
                    variants = {[-1],[-1],[-1],[-1]};
                elseif ismember(ld, 5:7)
                    variants = {[-1],[-1 4],[-1 4],[-1 4]};
                elseif ld == 8
                    variants = {[-1],[-1 6],[-1 3 6],[-1 3 6]};
                elseif ismember(ld, 9:10)
                    variants = {[-1],[-1 7],[-1 4 7],[-1 4 7]};
                elseif ld == 11
                    variants = {[-1],[-1 8],[-1 4 8],[-1 3 6 9]};
                elseif ismember(ld, 12:13)
                    variants = {[-1],[-1 9],[-1 5 9],[-1 3 6 9]};
                end
            elseif mapping == "A" && dmrsLength == 2
                if ismember(ld, 4:9)
                    variants = {[-1],[-1],[]};
                elseif ismember(ld, 10:12)
                    variants = {[-1],[-1 8],[]};
                elseif ismember(ld, 13:14)
                    variants = {[-1],[-1 10],[]};
                end
            elseif mapping == "B" && dmrsLength == 2
                if ismember(ld, 5:7)
                    variants = {[-1],[-1],[]};
                elseif ismember(ld, 8:9)
                    variants = {[-1],[-1 5],[]};
                elseif ismember(ld, 10:11)
                    variants = {[-1],[-1 7],[]};
                elseif ismember(ld, 12:13)
                    variants = {[-1],[-1 8],[]};
                end
            end
            if additional >= 0 && additional == floor(additional) && ...
                    additional + 1 <= numel(variants)
                raw = variants{additional + 1};
            end
        end
    end
end
