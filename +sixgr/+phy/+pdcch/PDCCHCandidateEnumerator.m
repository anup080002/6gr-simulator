classdef PDCCHCandidateEnumerator
    %PDCCHCANDIDATEENUMERATOR Exact CSS/USS candidate equation.

    methods (Static)
        function result = enumerate(searchSpaceType, nCCE, aggregationLevel, ...
                numCandidates, coresetID, rnti, absoluteSlot, nCI)
            searchSpaceType = upper(strrep(string(searchSpaceType), "-", "_"));
            nCCE = localInteger(nCCE, 1, intmax("int32"), "NCCE");
            aggregationLevel = localInteger(aggregationLevel, 1, 16, "AggregationLevel");
            if ~ismember(aggregationLevel, [1 2 4 8 16])
                error("sixgr:phy:pdcch:invalid_aggregation_level", ...
                    "AggregationLevel must be exactly 1, 2, 4, 8 or 16.");
            end
            numCandidates = localInteger(numCandidates, 0, nCCE, "NumCandidates");
            nGroups = floor(nCCE / aggregationLevel);
            if numCandidates > nGroups
                error("sixgr:phy:pdcch:candidate_count_exceeds_cce_groups", ...
                    "%d candidates exceed %d CCE groups at AL%d.", ...
                    numCandidates, nGroups, aggregationLevel);
            end
            if nGroups < 1 && numCandidates > 0
                error("sixgr:phy:pdcch:invalid_candidate_count", ...
                    "CORESET has no complete AL%d candidate.", aggregationLevel);
            end
            coresetID = localInteger(coresetID, 0, 11, "CORESETID");
            rnti = localInteger(rnti, 0, 65535, "RNTI");
            absoluteSlot = localInteger(absoluteSlot, 0, intmax("int32"), "AbsoluteSlot");
            nCI = localInteger(nCI, 0, 65535, "NCI");
            if any(searchSpaceType == ["CSS","TYPE0","TYPE0A","TYPE1","TYPE2","TYPE3"])
                Y = 0;
            elseif searchSpaceType == "USS"
                constants = [39827 39829 39839];
                A = constants(mod(coresetID, 3) + 1);
                Y = rnti;
                for slot = 0:absoluteSlot %#ok<NASGU>
                    Y = mod(A * Y, 65537);
                end
            else
                error("sixgr:phy:pdcch:invalid_search_space_periodicity", ...
                    "Unsupported SearchSpaceType %s.", searchSpaceType);
            end
            rows = repmat(localRow(), numCandidates, 1);
            for m = 0:numCandidates-1
                first = aggregationLevel * mod(Y + ...
                    floor(m*nCCE/(aggregationLevel*numCandidates)) + nCI, nGroups);
                row = localRow();
                row.AggregationLevel = aggregationLevel;
                row.CandidateIndex = m;
                row.FirstCCE = first;
                row.CCEIndices = join(string(first:first+aggregationLevel-1), "|");
                row.YValue = Y;
                row.NCI = nCI;
                row.FormulaMismatchCount = 0;
                row.Status = "PASS";
                rows(m+1) = row;
            end
            result = struct("Rows", rows, ...
                "Table", struct2table(rows, "AsArray", true), ...
                "Y", Y, "FirstCCEIndices", [rows.FirstCCE], ...
                "Status", "PASS");
        end
    end
end

function value = localInteger(value, minimum, maximum, name)
value = double(value);
if ~(isscalar(value) && isfinite(value) && value >= minimum && value <= maximum && value == fix(value))
    error("sixgr:phy:pdcch:invalid_candidate_count", ...
        "%s must be an integer in [%d,%d].", name, minimum, maximum);
end
end

function row = localRow()
row = struct("AggregationLevel", NaN, "CandidateIndex", NaN, ...
    "FirstCCE", NaN, "CCEIndices", "", "YValue", NaN, "NCI", NaN, ...
    "FormulaMismatchCount", NaN, "Status", "");
end
