classdef IntegrationArtifactExporter
    %INTEGRATIONARTIFACTEXPORTER Atomic writers for actual integration evidence.
    methods (Static)
        function writeTable(outputRoot,relativePath,value)
            if ~istable(value) || height(value) == 0
                error("sixgr:integration:MissingActualEvidence", ...
                    "Refusing to write empty primary artifact %s.",relativePath);
            end
            target = fullfile(outputRoot,relativePath);
            folder = fileparts(target);
            if ~isfolder(folder), mkdir(folder); end
            temporary = target + ".staging.csv";
            writetable(value,temporary);
            movefile(temporary,target,"f");
        end
        function value = manifestRow(configuration,status)
            products = ver;
            toolbox = products(strcmp({products.Name},"5G Toolbox"));
            toolboxVersion = "unavailable";
            if ~isempty(toolbox), toolboxVersion = string(toolbox(1).Version); end
            [gitStatus,commit] = system("git rev-parse HEAD");
            if gitStatus ~= 0, commit = "unavailable"; end
            planning = configuration.Planning;
            value = table(configuration.RunID,planning.RunMode, ...
                planning.RadioProfile,configuration.ScenarioID, ...
                configuration.ResolvedSHA256,strtrim(string(commit)), ...
                string(version),toolboxVersion,string(status), ...
                'VariableNames',{'RunID','Mode','RadioProfile','ScenarioID', ...
                'ResolvedConfigSHA256','SourceCommit','MatlabVersion', ...
                'ToolboxVersion','Status'});
        end
        function value = configRow(configuration)
            value = table(configuration.RunID,configuration.SourceYAML, ...
                configuration.SourceSHA256,configuration.EffectiveSHA256, ...
                configuration.ResolvedSHA256,configuration.ExecutedSHA256, ...
                "PASS",'VariableNames',{'RunID','SourceYAML','SourceSHA256', ...
                'EffectiveSHA256','ResolvedSHA256','ExecutedSHA256','Status'});
        end
        function value = profileRow(configuration)
            p = configuration.Planning;
            value = table(configuration.RunID,p.RunMode,p.RadioProfile, ...
                p.RunClass,p.Normative,"PASS",'VariableNames', ...
                {'RunID','RunMode','RadioProfile','RunClass','Normative','Status'});
        end
    end
end
