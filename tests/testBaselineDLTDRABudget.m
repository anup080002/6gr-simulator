function ok=testBaselineDLTDRABudget(outputRoot)
% Call the main scheduler's budget producer for one configured radio frame.
% This checks resource selection, not PDCCH decoding or K1/UCI execution.
setup6GRSimToolkit('Verbose',false);
if nargin<1, outputRoot=tempname; end
assert(~isfolder(outputRoot),'test:EvidenceExists','Choose a new evidence directory.');
mkdir(outputRoot);
v=sixgr.lls6g.config.readConfigFile('simulator/configs/validation/baseline_dl_tdra_budget.yaml');
s=sixgr.lls6g.config.loadScenarioConfig(v.scenario_path);
cfg=sixgr.lls6g.buildInternalConfig(s,outputRoot);
multi=struct('Enabled',true,'NumUsers',double(s.Data.users.n_users), ...
    'RNTIStart',double(s.Data.users.rnti_start),'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,outputRoot,multi,struct(),1);
catalog=cfg.phy.pdsch.timeDomainAllocations;
rows={}; budgets={};
for slot0=0:state.SlotsPerFrame-1
    partition=sixgr.util.resolveTDDSlotPartition(cfg,slot0);
    region=double(partition.DLSymbolAllocation);
    if region(2)==0, continue; end
    state.CurrentSlot=slot0+1; state.CurrentDirection='DL';
    state.CurrentSlotDLSymbolStart=region(1); state.CurrentSlotDLNumSymbols=region(2);
    state.TimingControlAbsoluteSlot0Based=slot0;
    budget=sixgr.truth.CoupledTruthRuntime.configuredSlotBudgetRuntime(state);
    eligible=catalog(:,4)==0 & catalog(:,2)>=region(1) & ...
        catalog(:,2)+catalog(:,3)<=sum(region);
    selected=double(budget.SymbolAllocation);
    selectionLegal=any(eligible & catalog(:,2)==selected(1) & catalog(:,3)==selected(2));
    dciIndex=NaN;
    if selectionLegal
        % DCI binding check only: no fabricated TB, grant trace or decoded DCI.
        candidate=struct('SymbolAllocation',selected,'RNTI',multi.RNTIStart,'K0',0);
        [context,dciIndex]=sixgr.phy.pdcch.DCIContextFactory.fromScheduledGrant(cfg,candidate,'1_1');
        active=context.Data.DLTimeDomainAllocations;
        match=active(active(:,1)==dciIndex,:);
        assert(size(match,1)==1 && isequal(double(match(1,2:4)),[selected 0]));
    end
    rows{end+1}=struct('AbsoluteSlot0',slot0,'DLSymbolStart',region(1), ...
        'DLNumSymbols',region(2),'IsSpecialSlot',logical(partition.IsSpecialSlot), ...
        'LegalConfiguredTDRAExists',any(eligible),'BudgetPRBs',budget.NPRB, ...
        'SelectedStart',selected(1),'SelectedLength',selected(2), ...
        'SelectionMatchesLegalCatalogRow',selectionLegal, ...
        'DCITDRAIndex',dciIndex, ...
        'UnavailableReason',string(sixgr.util.structGet(budget,'UnavailableReason','')), ...
        'EvidenceScope',string(v.evidence_scope)); %#ok<AGROW>
    budgets{end+1}=budget; %#ok<AGROW>
end
results=struct2table(vertcat(rows{:}));
writetable(results,fullfile(outputRoot,'dl_tdra_budget.csv'));
resolvedScenario=s.Data;
save(fullfile(outputRoot,'dl_tdra_budget.mat'),'cfg','resolvedScenario','v','catalog','results','budgets');
disp(results);
assert(any(results.IsSpecialSlot & results.LegalConfiguredTDRAExists), ...
    'The baseline must exercise a configured special-slot allocation.');
assert(all(~results.LegalConfiguredTDRAExists | ...
    (results.BudgetPRBs>0 & results.SelectionMatchesLegalCatalogRow)), ...
    'sixgr:test:BaselineDLTDRACatalogIgnored', ...
    'The main budget producer must select an eligible YAML TDRA instead of rejecting the special slot.');
special=results(find(results.IsSpecialSlot,1),:);
region=[special.DLSymbolStart special.DLNumSymbols];
wrongOffset=sixgr.truth.selectConfiguredTDRARow(cfg,'DL',region,max(catalog(:,4))+1);
assert(isempty(wrongOffset),'Selection must not silently rewrite the scheduled K0.');
assert(isempty(sixgr.truth.selectConfiguredTDRARow(cfg,'DL',[0 0],0)), ...
    'A zero-DL region must not create data resources.');
bad=cfg; bad.phy.pdsch.TimeDomainAllocations(1,3)=1;
rejected=false;
try
    sixgr.truth.selectConfiguredTDRARow(bad,'DL',region,0);
catch cause
    rejected=strcmp(cause.identifier,'sixgr:truth:ConflictingTDRACatalog');
end
assert(rejected,'Conflicting catalog aliases must not be silently preferred.');
ok=true; disp('BASELINE_DL_TDRA_BUDGET_PASS');
end
