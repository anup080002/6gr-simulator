function ok=testCalibrationPopulationPlanning()
% Numerical planning contract, not physical calibration evidence.
p=sixgr.lls6g.config.readConfigFile('configs/calibration/nr_dl_ul_harq_baseline.yaml');
[reference,ra]=sixgr.calibration.historyGrid(p,"reference");
[~,referenceValidationAxis]=sixgr.calibration.historyGrid(p,"reference_validation");
[target,ta]=sixgr.calibration.historyGrid(p,"fit");
assert(size(reference,1)==64 && size(target,1)==9);
assert(isequal(ta,[-6 0 6]) && min(ra)<min(ta) && max(ra)>max(ta) && ...
    isequal(ra,referenceValidationAxis));
p.reference_snr_axis_db=[-30 -20 -10 0 10 20 30];
assert(isequal(target,sixgr.calibration.historyGrid(p,"validation")), ...
    'Widening the AWGN domain must not move the target operating points.');
legacy=rmfield(p,{'reference_snr_axis_db','target_snr_axis_db'}); legacy.snr_axis_db=[-6 0 6];
assert(isequal(target,sixgr.calibration.historyGrid(legacy,"reference")));
cases=struct('ID',{'dl','ul'});
cases(1).Direction="DL"; cases(2).Direction="UL";
feasibility=sixgr.calibration.auditPopulationFeasibility(p,cases);
assert(height(feasibility)>0 && ...
    ~any(feasibility.PotentiallyQualifiableUnderFrozenPopulation) && ...
    all(feasibility.EvidenceType=="planning_upper_bound_not_executed_trials"), ...
    'The 100-start pilot cannot qualify any conditional cell under the frozen policy.');
large=p; large.populations=struct('reference',10000,'reference_validation',10000, ...
    'fit',10000,'validation',10000);
feasible=sixgr.calibration.auditPopulationFeasibility(large,cases);
assert(all(feasible.PotentiallyQualifiableUnderFrozenPopulation), ...
    'A sufficiently large frozen population must remain potentially qualifiable.');
p.starting_population_overrides=struct('case_id','ul','role','fit','history_index',2,'starting_tbs',50000);
quotas=sixgr.calibration.startingPopulations(p,cases);
assert(quotas{2,3}(2)==50000 && quotas{1,3}(2)==p.populations.fit && ...
    quotas{2,4}(2)==p.populations.validation,'Frozen overrides must not leak across cases or roles.');
[rare,lower,tail]=sixgr.calibration.requiredStartingPopulation(10,100,2000,.95,.95,1000000);
[common,~,~]=sixgr.calibration.requiredStartingPopulation(90,100,2000,.95,.95,1000000);
assert(rare>common && common>2000 && tail>=.95);
assert(betainc(lower,2000,rare-2000)<.95,'Planner did not return the minimum fixed population.');
[none,lower,~]=sixgr.calibration.requiredStartingPopulation(0,100,2000,.95,.95,1000000);
assert(isinf(none) && lower==0,'Zero observed failures cannot manufacture reachability.');
[limited,~,~]=sixgr.calibration.requiredStartingPopulation(1,1000,2000,.95,.95,3000);
assert(isinf(limited),'Population budgets must be enforced.');
policy=p.qualification; policy.minimum_conditional_trials=2000;
referenceFloor=sixgr.calibration.referencePairPlanningFloor(policy);
assert(referenceFloor>2000 && referenceFloor<20000, ...
    'Independent reference comparison needs more than the generic per-cell minimum.');
[transitionLow,transitionHigh]=sixgr.lls.stats.wilsonInterval(1000,2000,policy.confidence_level);
assert(transitionHigh-transitionLow>policy.maximum_validation_absolute_bler_error, ...
    'The original 2,000-trial plan must not be treated as sufficient at the BLER transition.');
[plannedLow,plannedHigh]=sixgr.lls.stats.wilsonInterval(referenceFloor/2,referenceFloor,policy.confidence_level);
assert(plannedHigh-plannedLow<=policy.maximum_validation_absolute_bler_error+1e-12, ...
    'Reference planning floor must satisfy the implemented Wilson comparison at p=0.5.');
ref=struct('TrialCount',[40000;40000],'ErrorCount',[20000;0]);
independent=struct('TrialCount',[40000;40000],'ErrorCount',[20010;1]);
check=sixgr.calibration.validateIndependentReference(ref,independent,policy);
assert(check.Passed && check.MaximumAbsoluteBLERDifferenceBound<.02);
independent.ErrorCount(1)=30000;
check=sixgr.calibration.validateIndependentReference(ref,independent,policy);
assert(~check.Passed,'Changed held-out waveform outcomes must reject the reference.');
ok=true; fprintf('CALIBRATION_POPULATION_PLANNING_PASS rare=%d common=%d\n',rare,common);
end
