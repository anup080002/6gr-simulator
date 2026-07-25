classdef ReservedREUnionSpec
    %RESERVEDREUNIONSPEC Independent reservation-union oracle.
    %
    % Encoded vector fields are parsed and resolved locally.  This class
    % calls neither production ownership code nor MATLAB nr* functions.

    methods (Static)
        function result = resolveEncoded(allocationText, sourceTexts)
            allocation = sixgr.pdsch.oracle.ReservedREUnionSpec. ...
                decode(allocationText);
            if ~iscell(sourceTexts) && ~isstring(sourceTexts)
                error("sixgr:pdsch:oracle:InvalidReservationInput", ...
                    "Independent reservation source text must be a cell or string array.");
            end
            sourceTexts = string(sourceTexts);
            sourceSets = cell(1, numel(sourceTexts));
            for i = 1:numel(sourceTexts)
                sourceSets{i} = sixgr.pdsch.oracle. ...
                    ReservedREUnionSpec.decode(sourceTexts(i));
            end
            unionAll = unique([sourceSets{:}], "sorted");
            outside = setdiff(unionAll, allocation, "stable");
            unionInside = intersect(allocation, unionAll, "stable");
            data = setdiff(allocation, unionInside, "stable");
            pairwise = 0;
            for i = 1:numel(sourceSets)
                for j = (i + 1):numel(sourceSets)
                    pairwise = pairwise + ...
                        numel(intersect(sourceSets{i}, sourceSets{j}));
                end
            end
            status = "PASS";
            token = "";
            if ~isempty(outside)
                status = "ERROR";
                token = "ReservedREOutsideAllocation";
            elseif isempty(data)
                status = "ERROR";
                token = "NoPDSCHDataREAfterReservation";
            end
            result = struct( ...
                "AllocationIndices", allocation(:).', ...
                "ReservedUnionIndices", unionInside(:).', ...
                "DataIndices", data(:).', ...
                "OutsideReservationIndices", outside(:).', ...
                "AllocationRECount", numel(allocation), ...
                "ReservedUnionCount", numel(unionInside), ...
                "DataRECount", numel(data), ...
                "ReservedOutsideAllocationCount", numel(outside), ...
                "PairwiseOverlapMultiplicity", double(pairwise), ...
                "Status", string(status), "ErrorToken", string(token), ...
                "IndexBase", "zero_based");
        end
    end

    methods (Static, Access = private)
        function values = decode(text)
            text = strtrim(string(text));
            if ismissing(text) || strlength(text) == 0
                values = zeros(1, 0);
                return;
            end
            tokens = split(text, "|");
            values = zeros(1, 0);
            for i = 1:numel(tokens)
                token = strtrim(tokens(i));
                bounds = split(token, "-");
                if numel(bounds) == 1
                    values(end + 1) = str2double(bounds(1)); %#ok<AGROW>
                elseif numel(bounds) == 2
                    first = str2double(bounds(1));
                    last = str2double(bounds(2));
                    values = [values first:last]; %#ok<AGROW>
                else
                    error("sixgr:pdsch:oracle:InvalidEncodedRESet", ...
                        "Malformed encoded RE set token '%s'.", token);
                end
            end
            if any(~isfinite(values)) || any(values ~= floor(values)) || ...
                    any(values < 0) || ...
                    numel(unique(values, "stable")) ~= numel(values)
                error("sixgr:pdsch:oracle:InvalidEncodedRESet", ...
                    "Encoded RE sets must contain unique nonnegative integers.");
            end
            values = sort(double(values));
        end
    end
end
