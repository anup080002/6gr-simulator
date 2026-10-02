function T=auditPopulationFeasibility(p,cases)
%AUDITPOPULATIONFEASIBILITY Deterministic upper bounds before waveform work.
% A later HARQ attempt occurs only after all prior CRC failures. Summing
% frozen starting TBs therefore gives an upper bound, not a trial count.
roles=["reference","reference_validation","fit","validation"];
counts=sixgr.calibration.startingPopulations(p,cases);
rows=cell(0,1);
for c=1:numel(cases)
    for r=1:numel(roles)
        fullHistory=sixgr.calibration.historyGrid(p,roles(r));
        target=double(p.qualification.minimum_conditional_trials);
        if any(roles(r)==["reference","reference_validation"])
            target=sixgr.calibration.referencePairPlanningFloor(p.qualification);
        end
        for a=1:numel(p.rv_sequence)
            prefixPolicy=p; prefixPolicy.rv_sequence=p.rv_sequence(1:a);
            prefixes=sixgr.calibration.historyGrid(prefixPolicy,roles(r));
            for k=1:size(prefixes,1)
                same=all(fullHistory(:,1:a)==prefixes(k,:),2);
                maximum=sum(double(counts{c,r}(same)));
                rows{end+1,1}=struct( ...
                    'CaseID',string(cases(c).ID), ...
                    'Direction',string(cases(c).Direction), ...
                    'Role',roles(r),'Attempt',a, ...
                    'History_dB',string(jsonencode(prefixes(k,:))), ...
                    'MaximumConditionalAttempts',maximum, ...
                    'RequiredConditionalTrials',target, ...
                    'PotentiallyQualifiableUnderFrozenPopulation',maximum>=target, ...
                    'EvidenceType',"planning_upper_bound_not_executed_trials", ...
                    'PrimaryStudyAccepted',false); %#ok<AGROW>
            end
        end
    end
end
T=struct2table(vertcat(rows{:}));
end
