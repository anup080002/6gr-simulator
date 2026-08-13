classdef PostIATransitionStateMachine
    %POSTIATRANSITIONSTATEMACHINE Bounded post-access activation/fallback.

    methods (Static)
        function [summary,events] = run(cfg,masterSeed)
            kAct=double(cfg.k_act_slots(:));kFallback=double(cfg.k_fallback_slots(:));
            classes=double(cfg.transition_classes(:));references=string(cfg.activation_references(:));
            cease=string(cfg.early_cease_rules(:));trials=double(cfg.trials);
            rows={};eventRows={};r=0;e=0;
            for classId=classes(:).'
                for reference=references(:).'
                    for ka=kAct(:).'
                        for kf=kFallback(:).'
                            for rule=cease(:).'
                                r=r+1;seed=localSeed(masterSeed,classId,reference,ka,kf,rule);
                                stream=RandStream("Threefry","Seed",seed);
                                supported=rand(stream,trials,1)<double(cfg.target_profile_support_probability);
                                refOK=rand(stream,trials,1)<double(cfg.confirming_ul_success_probability);
                                targetOK=rand(stream,trials,1)<double(cfg.target_pdcch_success_probability);
                                commonOK=rand(stream,trials,1)<double(cfg.common_pdcch_success_probability);
                                activated=supported & refOK;
                                targetConfirmed=activated & targetOK;
                                recoverable=(~targetConfirmed) & commonOK & kf>0;
                                recovered=targetConfirmed|recoverable|(~supported&commonOK);
                                falseActivation=activated&~supported;
                                mismatch=activated&~targetConfirmed;
                                if rule=="target_pdsch_harq_ack"
                                    monitorSlots=min(kf,max(1,ka+1));
                                elseif rule=="target_pdcch_diagnostic"
                                    monitorSlots=min(kf,double(cfg.target_diagnostic_observation_slots));
                                else
                                    monitorSlots=kf;
                                end
                                latency=ka+1+mean(~targetConfirmed)* ...
                                    min(kf,double(cfg.latency_fallback_cap_slots));
                                rows{r}=table(classId,reference,ka,kf,rule,trials, ...
                                    mean(activated),mean(targetConfirmed),mean(mismatch), ...
                                    mean(falseActivation),mean(recovered),latency,monitorSlots,seed, ...
                                    "PROCEDURE_SLS",'VariableNames',{'TransitionClass', ...
                                    'ActivationReference','KActSlots','KFallbackSlots','EarlyCeaseRule', ...
                                    'Trials','ActivationProbability','TargetConfirmationProbability', ...
                                    'StateMismatchProbability','FalseActivationProbability', ...
                                    'RecoverySuccessProbability','MeanActivationLatencySlots', ...
                                    'MeanCommonMonitoringSlots','Seed','EvidenceClass'}); %#ok<AGROW>
                                for event=["MSG4_RECEIVED","CONFIRMING_UL","TARGET_ACTIVATION", ...
                                        "DUAL_MONITORING","TARGET_CONFIRMATION_OR_FALLBACK","TERMINAL"]
                                    e=e+1;eventRows{e}=table(r,event,e,event=="TERMINAL", ...
                                        "existing_message_or_state_transition","PROCEDURE_SLS", ...
                                        'VariableNames',{'ScenarioOrdinal','Event','Sequence', ...
                                        'Terminal','Source','EvidenceClass'}); %#ok<AGROW>
                                end
                            end
                        end
                    end
                end
            end
            summary=vertcat(rows{:});events=vertcat(eventRows{:});
            localAssertNoDeadlock(events,height(summary));
        end

        function classId=deriveClass(commonStart,commonSize,targetStart,targetSize)
            classId=sixgr.bwop.RegionGeometry.transitionClass(commonStart,commonSize,targetStart,targetSize);
        end
    end
end

function value=localSeed(masterSeed,classId,reference,ka,kf,rule)
token=char(string(classId)+"|"+reference+"|"+string(ka)+"|"+string(kf)+"|"+rule);
bytes=unicode2native(token,"UTF-8");
value=mod(double(masterSeed)+sum(double(bytes).*(1:numel(bytes))),2^31-2)+1;
end

function localAssertNoDeadlock(events,scenarios)
terminal=groupsummary(events,"ScenarioOrdinal","sum","Terminal");
if height(terminal)~=scenarios||any(terminal.sum_Terminal~=1)
    error("sixgr:bwop:PostIAStateMachineDeadlock", ...
        "Every post-IA scenario must reach exactly one terminal state.");
end
end
