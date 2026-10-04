function ok = testKPIWaveformExecutionScope()
%TESTKPIWAVEFORMEXECUTIONSCOPE Exercise the production export mode binding.
% These empty metadata fixtures test applicability, not PHY performance.
setup6GRSimToolkit("Verbose",false);
root=tempname; mkdir(root);
cleanup=onCleanup(@() rmdir(root,'s')); %#ok<NASGU>
s=struct('scenario',struct('runner_profile','waveform_bundle'), ...
    'users',struct('execution_model','independent_link_sweep'), ...
    'pdsch',struct('execution_profile','phy_calibration'), ...
    'pusch',struct('execution_profile','phy_calibration'));
for variant=["independent","connected","unknown","system","missing_profile"]
    scenario=s;
    switch variant
        case "connected"
            scenario.users.execution_model='slot_coupled_truth';
            scenario.pdsch.execution_profile='scheduler_truth';
            scenario.pusch.execution_profile='scheduler_truth';
        case "unknown"
            scenario=struct();
        case "system"
            scenario.scenario.runner_profile='system_level_lls';
        case "missing_profile"
            scenario=rmfield(scenario,'pusch');
    end
    cfg=struct('lls6g',struct('resolvedConfig',scenario), ...
        'phy',struct('harq',struct('enable',true)), ...
        'run',struct('strictMode',true));
    folder=fullfile(root,variant); mkdir(folder);
    sixgr.link.exportLinkKPIs(folder,table(),struct('Config',cfg), ...
        'SaveCSV',true,'SaveMAT',false,'SaveFigures',false);
    binding=readtable(fullfile(folder,'reports','csv','kpi_objective_binding.csv'), ...
        'TextType','string','VariableNamingRule','preserve');
    owned=contains(binding.KPIName,["HARQ_NACK","Retransmission","PRB_Utilization"]);
    assert(nnz(owned)==6,'Expected all six runtime-owned KPI bindings.');
    if variant=="independent"
        assert(all(~binding.MandatoryInScenarioObjective(owned)) && ...
            all(binding.Status(owned)=="not_applicable"), ...
            'test:IndependentWaveformRequiresConnectedEvidence', ...
            'Independent PHY attempts cannot claim connected HARQ/scheduler KPIs.');
        assert(all(startsWith(binding.ApplicabilityReason(owned), ...
            "independent_waveform_attempts_")), ...
            'Report the execution scope, not a falsely disabled HARQ configuration.');
    else
        assert(all(binding.MandatoryInScenarioObjective(owned)) && ...
            all(binding.Status(owned)=="fail"), ...
            'Missing runtime evidence must remain mandatory for %s.',variant);
    end
    phy=ismember(binding.KPIName,["DL_BLER","UL_BLER"]);
    assert(nnz(phy)==2 && all(binding.MandatoryInScenarioObjective(phy)) && ...
        all(binding.Status(phy)=="fail"), ...
        'Execution scope must never waive absent primary PHY measurements.');
end
ok=true;
end
