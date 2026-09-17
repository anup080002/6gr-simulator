function ok=testResearchDLHeavyConfig()
% Slot/allocation contract only; no throughput or calibration pass is implied.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
c=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_7ghz_400mhz_adaptive_dl5_ul2_30db.yaml');
s=c.toStruct(); frame=sixgr.phy.FrameStructureEngine(s,'FrameCoreOnly',true);
assert(frame.NRB==264 && frame.SCSkHz==120 && frame.FFTSize==4096 && frame.SampleRate_Hz==491520000);
assert(s.frequency.center_frequency_hz==7e9 && s.frequency.bandwidth_hz==400e6);
assert(s.simulation.n_slots==80 && s.simulation.snr_db==30 && s.simulation.random_seed==20260920);
assert(s.research_awgn_mimo.physical_ports==4 && s.research_dl.num_prbs==264 && s.research_ul.num_prbs==264);
assert(s.research_link.capture_iq && s.research_link.export_keysight && s.research_link.save_plots);
assert(s.research_adaptation.enabled && s.harq.enabled && ...
    all(s.research_adaptation.candidate_code_rates<=0.9));
dl=false(1,s.simulation.n_slots); ul=dl;
for slot=0:s.simulation.n_slots-1
    dl(slot+1)=frame.IsDLAllocation(slot,s.research_dl.symbol_allocation);
    ul(slot+1)=frame.IsULAllocation(slot,s.research_ul.symbol_allocation);
end
assert(isequal(dl,repmat([true true true true true false false false],1,10)));
assert(isequal(ul,repmat([false false false false false false true true],1,10)));
assert(sum(dl)==50 && sum(ul)==20 && ~any(dl & ul));
% TDD airtime changes, but the calibrated active PHY profile must not change.
base=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_7ghz_400mhz_adaptive_rank_qam_rate_30db.yaml');
original=base.toStruct();
for direction=["DL","UL"]
    for k=1:numel(s.research_adaptation.candidate_layers)
        proposed=sixgr.phy.research.AWGNLinkAdaptation.candidate(s,direction,k);
        prior=sixgr.phy.research.AWGNLinkAdaptation.candidate(original,direction,k);
        assert(sixgr.phy.research.AWGNLinkAdaptation.physicalProfileHash(proposed,direction)== ...
            sixgr.phy.research.AWGNLinkAdaptation.physicalProfileHash(prior,direction));
    end
end
ok=true;
fprintf('RESEARCH_DL_HEAVY_CONFIG_PASS DL_opportunities=50 UL_opportunities=20 integrated_run=0\n');
end
