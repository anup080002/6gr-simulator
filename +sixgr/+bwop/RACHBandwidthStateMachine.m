classdef RACHBandwidthStateMachine
    %RACHBANDWIDTHSTATEMACHINE Initial-access common/target region procedure.

    methods (Static)
        function [summary,events] = run(cfg,masterSeed)
            states=string(cfg.early_indication_states(:));policies=string(cfg.policies(:));
            rates=double(cfg.indication_error_rates(:));trials=double(cfg.trials);
            rows=cell(numel(states)*numel(policies)*numel(rates),1);eventRows={};r=0;e=0;
            for policy=policies(:).'
                for state=states(:).'
                    for errorRate=rates(:).'
                        r=r+1;seed=sixgr.bwop.RACHBandwidthStateMachine.seed(masterSeed,policy,state,errorRate);
                        stream=RandStream("Threefry","Seed",seed);
                        random=rand(stream,trials,1);
                        correct=state=="correct" & random>=errorRate;
                        commonFallback=contains(policy,"FALLBACK")||policy=="COMMON_ONLY_BASELINE";
                        unsupported=state=="unsupported_profile";
                        collision=state=="collision";
                        success=correct | commonFallback | state=="none";
                        if policy=="CAPABILITY_SPECIFIC_NO_FALLBACK"
                            success=correct & ~unsupported & ~collision;
                        end
                        silentFailure=~success & ~commonFallback;
                        recovery=~correct & success & commonFallback;
                        summaryRow=table(policy,state,errorRate,trials,mean(success), ...
                            mean(silentFailure),mean(recovery),mean(~correct),seed, ...
                            "PROCEDURE_SLS",'VariableNames',{'Policy','IndicationState', ...
                            'IndicationErrorRate','Trials','AccessSuccessProbability', ...
                            'SilentFailureProbability','CommonRecoveryProbability', ...
                            'WrongBandwidthSchedulingRisk','Seed','EvidenceClass'});
                        rows{r}=summaryRow;
                        for name=["MSG1_OR_MSGA","MSG2_OR_MSGB","MSG3","MSG4","CONTENTION_RESOLUTION"]
                            e=e+1;eventRows{e}=table(policy,state,errorRate,name,e, ...
                                localRegion(name),"executed_existing_message_type","PROCEDURE_SLS", ...
                                'VariableNames',{'Policy','IndicationState','IndicationErrorRate', ...
                                'Event','Sequence','Region','Status','EvidenceClass'}); %#ok<AGROW>
                        end
                    end
                end
            end
            summary=vertcat(rows{:});events=vertcat(eventRows{:});
        end
    end

    methods (Static,Access=private)
        function value=seed(masterSeed,policy,state,errorRate)
            token=char(string(policy)+"|"+string(state)+"|"+compose("%.9f",errorRate));
            bytes=unicode2native(token,"UTF-8");
            value=mod(double(masterSeed)+sum(double(bytes).*(1:numel(bytes))),2^31-2)+1;
        end
    end
end

function region=localRegion(event)
if any(event==["MSG2_OR_MSGB","MSG4"])
    region="common_control_plus_sib1_data_region";
elseif event=="MSG3"
    region="configured_common_ul_subset";
else
    region="common_initial_access_anchor";
end
end
