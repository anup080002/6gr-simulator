classdef FocusedCheck
    %FOCUSEDCHECK Dedicated AI 10.5.1.3 acceptance checks.

    methods (Static)
        function run(checkName)
            checkName=string(checkName);
            persistent campaignCache
            if isempty(campaignCache)
                campaignCache=sixgr.bwop.loadCampaignConfig( ...
                    "simulator/configs/bwop_ai10513/master_campaign.yaml","smoke");
            end
            campaign=campaignCache;
            cfg=campaign.Config;a=cfg.analytical;
            switch checkName
                case "min_rb_screening"
                    out=sixgr.bwop.PBCHPayloadStudy.run(a);
                    assert(height(out.MinimumRB)==numel(a.sib1_payload_bits)*numel(a.effective_code_rates));
                    assert(all(out.MinimumRB.MinimumRB>=1));
                case "pbch_cost_arithmetic"
                    out=sixgr.bwop.PBCHPayloadStudy.run(a);T=out.PayloadCost;
                    expected=10*log10((double(a.pbch_baseline_input_bits)+double(a.pbch_added_bits(:)))/double(a.pbch_baseline_input_bits));
                    assert(max(abs(T.ClosedFormDeltaEsN0Db-expected))<1e-12);
                case "riv_fdra"
                    for N=double(a.fdra_reference_bandwidth_rb(:)).'
                        for L=1:N
                            for S=0:N-L
                                riv=sixgr.bwop.RIVFDRA.encode(N,S,L);
                                [decodedS,decodedL]=sixgr.bwop.RIVFDRA.decode(N,riv);
                                assert(decodedS==S&&decodedL==L);
                            end
                        end
                    end
                case "cce_feasibility"
                    T=sixgr.bwop.RIVFDRA.cceTable(24,3,[1 2 4 8 16]);
                    assert(all(T.NCCE==12));assert(~T.Feasible(T.AggregationLevel==16));
                case "power_normalization"
                    T=sixgr.bwop.PowerNormalizer.sourceArithmetic(32,216,6.5,.7);
                    assert(abs(T.OccupiedEnergyRatioDb-10*log10(216/32))<1e-12);
                    for mode=["fixed_psd","fixed_total_power"]
                        P=sixgr.bwop.PowerNormalizer.accounting([32 216],132,12,mode);
                        sixgr.bwop.PowerNormalizer.assertClosure(P);
                    end
                case "region_relations"
                    [s,r]=sixgr.bwop.RegionGeometry.derive("CASE_2B",48,24,96);
                    assert(s==12&&r=="centre_preserving");
                    assert(sixgr.bwop.RegionGeometry.transitionClass(48,24,12,96)==1);
                case "rf_span_containment"
                    pass=sixgr.bwop.RFSpanFeasibility.evaluate(20,96,273,0,137,4,20,20);
                    fail=sixgr.bwop.RFSpanFeasibility.evaluate(150,96,273,0,137,4,20,20);
                    assert(pass.Feasible&&~fail.Feasible&&contains(fail.Reason,"mandatory_rf_span"));
                case "distributed_prb_mapping"
                    T=sixgr.bwop.PDSCHStudy.allocationCases(cfg.downlink);
                    row=T(T.CaseID=="WIDER_S_DISTRIBUTED_A",:);
                    assert(height(row)==1&&row.NonContiguous&&row.ActualAllocationRB>0);
                case "pdcch_al_capacity"
                    T=sixgr.bwop.PDCCHStudy.run(a,cfg.downlink);
                    assert(any(T.Feasible)&&any(~T.Feasible));
                    assert(all(T.AnalyticalDCIPayloadBits==double(a.dci_non_fdra_bits)+T.FDRABits));
                case "joint_sib1_success"
                    pdcch=table([-3;0],[1000;1000],[100;10], ...
                        'VariableNames',{'SNRdB','Trials','Errors'});
                    pdsch=table([-3;0],[1000;1000],[200;20], ...
                        'VariableNames',{'SNRdB','Trials','Errors'});
                    T=sixgr.bwop.JointSIB1Study.combine(pdcch,pdsch);
                    assert(max(abs(T.JointAcquisitionBLER-[.28;.0298]))<1e-12);
                case "common_control_scheduler"
                    T=sixgr.bwop.CommonControlScheduler.run(cfg.common_control);
                    assert(all(T.BlockingProbability>=0&T.BlockingProbability<=1));
                    assert(all(T.CCEUtilization>=0&T.CCEUtilization<=1));
                case "initial_ul_subset_mapping"
                    T=sixgr.bwop.InitialULStudy.run(cfg.initial_ul);
                    assert(all(T.AllResourcesContained));
                    sixgr.bwop.InitialULStudy.assertPRBSet([0 2 4 6],51);
                case "transition_class_derivation"
                    assert(sixgr.bwop.RegionGeometry.transitionClass(0,24,0,24)==0);
                    assert(sixgr.bwop.RegionGeometry.transitionClass(0,24,-12,48)==1);
                    assert(sixgr.bwop.RegionGeometry.transitionClass(0,24,1,24)==2);
                case {"activation_reference","early_cease","unsupported_profile_recovery"}
                    post=cfg.post_ia;post.trials=32;
                    [T,E]=sixgr.bwop.PostIATransitionStateMachine.run(post,cfg.master_seed);
                    if checkName=="activation_reference"
                        assert(all(ismember(string(post.activation_references),unique(T.ActivationReference))));
                        assert(all(groupsummary(E,"ScenarioOrdinal","sum","Terminal").sum_Terminal==1));
                    elseif checkName=="early_cease"
                        fixed=T(T.EarlyCeaseRule=="fixed_window",:);
                        diag=T(T.EarlyCeaseRule=="target_pdcch_diagnostic",:);
                        assert(mean(diag.MeanCommonMonitoringSlots)<=mean(fixed.MeanCommonMonitoringSlots));
                    else
                        rach=cfg.rach;rach.trials=32;
                        R=sixgr.bwop.RACHBandwidthStateMachine.run(rach,cfg.master_seed);
                        fallbackPolicy=R.Policy=="CAPABILITY_SPECIFIC_WITH_COMMON_FALLBACK"| ...
                            R.Policy=="COMMON_ONLY_BASELINE";
                        rows=R(R.IndicationState=="unsupported_profile"&fallbackPolicy,:);
                        assert(~isempty(rows)&&all(rows.AccessSuccessProbability==1));
                    end
                case "dual_monitor_budget"
                    T=sixgr.bwop.CommonControlScheduler.monitoringBudget(cfg.post_ia);
                    assert(all(T.BudgetValid));
                    assert(all(T.CommonBD+T.TargetBD<=T.MaxBD));
                    assert(all(T.CommonCCE+T.TargetCCE<=T.MaxCCE));
                otherwise
                    error("sixgr:bwop:UnknownFocusedCheck","Unknown focused check '%s'.",checkName);
            end
            fprintf("BWOP focused check %s: PASS\n",checkName);
        end
    end
end
