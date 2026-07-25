classdef PTRSIndexSpec
    %PTRSINDEXSPEC Independent zero-based PT-RS index oracle.
    %
    % No production method and no MATLAB nr* primitive is called.

    methods (Static)
        function result = resolve(request)
            prbs = sort(double(request.PRBSet(:).'));
            startSymbol = double(request.SymbolAllocation(1));
            duration = double(request.SymbolAllocation(2));
            dmrs = double(request.DMRSSymbols(:).');
            timeDensity = double(request.TimeDensity);
            frequencyDensity = double(request.FrequencyDensity);
            gridNumPRB = double(request.GridNumPRB);
            rnti = 0;
            if isfield(request,"RNTI")
                rnti = double(request.RNTI);
            end
            configType = 1;
            if isfield(request,"DMRSConfigurationType")
                configType = double(request.DMRSConfigurationType);
            end
            labels = ["00","01","10","11"];
            offsets = [0 2 6 8];
            offsetPosition = find( ...
                strtrim(string(request.REOffset)) == labels, 1);
            if isempty(offsetPosition)
                error("sixgr:pdsch:oracle:InvalidPTRSREOffset", ...
                    "Independent PT-RS oracle received an invalid RE offset.");
            end

            scheduled = startSymbol:(startSymbol + duration - 1);
            chosenSymbols = zeros(1,0);
            for candidateSymbol = scheduled
                if ismember(candidateSymbol,dmrs)
                    continue;
                end
                precedingDMRS = dmrs(dmrs < candidateSymbol);
                if isempty(precedingDMRS)
                    anchor = startSymbol;
                else
                    anchor = precedingDMRS(end);
                end
                if mod(candidateSymbol-anchor,timeDensity) == 0
                    chosenSymbols(end+1) = candidateSymbol; %#ok<AGROW>
                end
            end
            rbRemainder = mod(numel(prbs),frequencyDensity);
            if rbRemainder == 0
                rbRemainder = frequencyDensity;
            end
            firstPRB = mod(rnti,rbRemainder) + 1;
            chosenPRBs = prbs(firstPRB:frequencyDensity:numel(prbs));
            associatedPort = 0;
            if isfield(request,"AssociatedDMRSPort")
                associatedPort = double(request.AssociatedDMRSPort);
            end
            offsets = localOffsetCatalog(configType);
            if associatedPort < 0 || associatedPort ~= fix(associatedPort) ...
                    || associatedPort >= size(offsets,1)
                error("sixgr:pdsch:oracle:InvalidPTRSPortSet", ...
                    "Independent PT-RS oracle received an invalid port.");
            end
            count = numel(chosenPRBs) * numel(chosenSymbols);
            coordinates = zeros(count, 2);
            cursor = 0;
            for symbol = chosenSymbols
                for prb = chosenPRBs
                    cursor = cursor + 1;
                    coordinates(cursor, :) = [ ...
                        12 * prb ...
                        + offsets(associatedPort+1,offsetPosition), symbol];
                end
            end
            indices = coordinates(:, 1) + ...
                12 * gridNumPRB .* coordinates(:, 2);
            result = struct( ...
                "Indices0Based", double(indices(:)), ...
                "Coordinates0Based", double(coordinates), ...
                "Symbols0Based", double(chosenSymbols(:).'), ...
                "PRBSet0Based", double(chosenPRBs(:).'), ...
                "IndexBase", "zero_based");
        end
    end
end

function offsets = localOffsetCatalog(configType)
if configType == 1
    offsets = [ ...
        0 2 6 8; 2 4 8 10; 1 3 7 9; 3 5 9 11; ...
        zeros(4,4); ...
        4 6 10 0; 6 8 0 2; 5 7 11 1; 7 9 1 3];
else
    offsets = [ ...
        0 1 6 7; 1 6 7 0; 2 3 8 9; 3 8 9 2; ...
        4 5 10 11; 5 10 11 4; ...
        zeros(6,4); ...
        6 7 0 1; 7 0 1 6; 8 9 2 3; ...
        9 2 3 8; 10 11 4 5; 11 4 5 10];
end
end
