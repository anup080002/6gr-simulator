classdef PDCCHMonitoringBudget
    %PDCCHMONITORINGBUDGET Release-18 per-slot monitoring capability guard.

    methods (Static)
        function result = validate(scsKHz, candidateRows)
            scsKHz = double(scsKHz);
            switch scsKHz
                case 15
                    maxCandidates = 44; maxCCE = 56;
                case 30
                    maxCandidates = 36; maxCCE = 56;
                case 60
                    maxCandidates = 22; maxCCE = 48;
                case 120
                    maxCandidates = 20; maxCCE = 32;
                otherwise
                    error("sixgr:phy:pdcch:monitoring_budget_exceeded", ...
                        "No installed monitoring budget exists for SCS %g kHz.", scsKHz);
            end
            if istable(candidateRows)
                candidateRows = table2struct(candidateRows);
            end
            count = numel(candidateRows);
            cceTokens = strings(0,1);
            for ii = 1:count
                tokens = split(string(candidateRows(ii).CCEIndices), "|");
                cceTokens = [cceTokens; tokens(:)]; %#ok<AGROW>
            end
            nonOverlappingCCE = numel(unique(cceTokens(strlength(cceTokens)>0)));
            if count > maxCandidates || nonOverlappingCCE > maxCCE
                error("sixgr:phy:pdcch:monitoring_budget_exceeded", ...
                    "Monitoring requests %d candidates and %d non-overlapping CCEs; limits are %d and %d.", ...
                    count, nonOverlappingCCE, maxCandidates, maxCCE);
            end
            result = struct("CandidateCount", count, ...
                "NonOverlappingCCECount", nonOverlappingCCE, ...
                "MaxCandidates", maxCandidates, "MaxNonOverlappingCCE", maxCCE, ...
                "Status", "PASS");
        end
    end
end
