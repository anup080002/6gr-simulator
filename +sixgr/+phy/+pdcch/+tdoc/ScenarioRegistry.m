classdef ScenarioRegistry
    %SCENARIOREGISTRY Requirement and figure inventory for AI 10.5.2.1.
    methods (Static)
        function T=catalog()
            ids=["ANA-"+compose("%02d",(1:13)');"SCH-"+compose("%02d",(1:10)'); ...
                "LLS-"+compose("%02d",(0:12)');"SLS-"+compose("%02d",(1:3)')];
            family=extractBefore(ids,"-");evidence=strings(size(ids));
            evidence(family=="ANA")="ANALYTICAL_EXACT";evidence(ids=="ANA-01"|ids=="ANA-13")="STATIC_VISUAL";
            evidence(family=="SCH")="SCHEDULER_PLACEMENT";evidence(ismember(ids,["SCH-08","SCH-09"]))="PROCEDURE_MODEL";
            evidence(family=="LLS")="LLS_COMMON_EVM";evidence(family=="SLS")="SLS_FULL";
            required=true(size(ids));T=table(ids,family,evidence,required, ...
                'VariableNames',{'ScenarioID','Family','RequiredEvidenceClass','Required'});
        end
        function T=figures()
            ids="tdoc_fig"+compose("%02d",(1:15)');
            scenarios=["ANA-01";"ANA-02";"ANA-03";"ANA-04";"ANA-06";"ANA-07"; ...
                "ANA-08";"ANA-08";"ANA-09";"ANA-11";"ANA-12";"ANA-13";"ANA-13";"SCH-01";"SCH-01"];
            T=table(ids,scenarios,"Fig."+string((1:15)'), ...
                'VariableNames',{'FigurePrefix','ScenarioID','TDocFigureNumber'});
        end
    end
end
