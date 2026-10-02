function T=planConditionalPopulations(folder)
%PLANCONDITIONALPOPULATIONS Planning-only; never read held-out outcomes.
% A new fixed population must be frozen before collection. Do not top up a
% validation cohort until it passes, force retransmissions, or pool pilots.
m=load(fullfile(folder,'campaign.mat'),'p','cases','identity');
q=m.p.qualification; policy=m.p.population_planning;
roles=["reference","fit"]; grids=cell(1,2); counts=cell(numel(m.cases),2);
nr=numel(m.p.rv_sequence);
for r=1:2
    grids{r}=sixgr.calibration.historyGrid(m.p,roles(r));
    for c=1:numel(m.cases), counts{c,r}=zeros(size(grids{r},1),nr); end
end
files=dir(fullfile(folder,'episodes','episode_*.mat'));
for k=1:numel(files)
    path=fullfile(files(k).folder,files(k).name);
    sixgr.calibration.verifyEpisodeFile(path);
    x=load(path,'episode'); e=x.episode;
    assert(e.CampaignIdentity==m.identity,'sixgr:calibration:ResumeIdentity','Mixed pilot source identities.');
    if any(e.Role==["validation","reference_validation"]), continue; end % held-out outcomes cannot plan populations
    c=find(string({m.cases.ID})==e.CaseID); r=find(roles==e.Role);
    assert(isscalar(c) && isscalar(r),'sixgr:calibration:History','Unknown pilot case/role.');
    [present,h]=ismember(e.PlannedSNRHistory_dB,grids{r},'rows');
    assert(present,'sixgr:calibration:History','Unexpected pilot history.');
    assert(all([e.Attempts(1:end-1).CRCError]), ...
        'sixgr:calibration:HARQHistory','Only preceding failures can create later attempts.');
    counts{c,r}(h,1:numel(e.Attempts))=counts{c,r}(h,1:numel(e.Attempts))+1;
end
% Simultaneous bounds over ALL planned conditional cells (Bonferroni).
cells=numel(m.cases)*sum(cellfun(@(h)size(h,1),grids))*max(1,nr-1);
confidence=1-(1-q.confidence_level)/cells;
reach=1-(1-policy.reach_confidence)/cells;
rows=cell(0,1);
for c=1:numel(m.cases), for r=1:2, for h=1:size(grids{r},1)
    starts=counts{c,r}(h,1);
    target=q.minimum_conditional_trials;
    if roles(r)=="reference"
        target=sixgr.calibration.referencePairPlanningFloor(q);
    end
    for a=1:nr
        n=counts{c,r}(h,a); lower=NaN; required=NaN; probability=NaN;
        status="insufficient_independent_pilot_starts";
        if a==1
            lower=1; required=target; probability=1;
            status="fixed_population_candidate";
        elseif starts>=policy.minimum_pilot_starts
            [required,lower,probability]=sixgr.calibration.requiredStartingPopulation( ...
                n,starts,target,confidence,reach, ...
                policy.maximum_starting_episodes_per_history);
            status="fixed_population_candidate";
            if ~isfinite(required), status="unsupported_prior_failure_population_within_budget"; end
        end
        rows{end+1,1}=struct('CaseID',m.cases(c).ID,'Direction',m.cases(c).Direction, ...
            'PilotRole',roles(r),'HistoryIndex',h,'History_dB',string(jsonencode(grids{r}(h,:))), ...
            'Attempt',a,'PilotStartingTBs',starts,'PilotPrecedingFailureCount',n, ...
            'PrecedingFailureProbabilityLower',lower,'RequiredConditionalTrials',target, ...
            'RequiredStartingTBs',required,'ConditionalCountReachProbability',probability, ...
            'PerCellBoundConfidence',confidence,'PerCellReachTarget',reach,'Status',status, ...
            'PlanningSourceIdentity',m.identity,'PrimaryStudyAccepted',false); %#ok<AGROW>
    end
end, end, end
T=struct2table(vertcat(rows{:}));
writetable(T,fullfile(folder,'conditional_population_plan.csv'));
end
