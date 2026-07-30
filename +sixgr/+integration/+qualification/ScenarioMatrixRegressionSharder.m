classdef ScenarioMatrixRegressionSharder
    %SCENARIOMATRIXREGRESSIONSHARDER Independent bounded matrix test tasks.
    methods (Static)
        function T=timeoutClasses()
            timeoutClass=["UNIT";"COMPONENT";"INTEGRATION"; ...
                "SCENARIO_MATRIX";"FULL_REGRESSION"];
            budgetSeconds=[120;600;1200;2100;5400];
            rationale=[ ...
                "isolated deterministic unit ceiling"; ...
                "measured production component runner plus startup margin"; ...
                "cross-domain integration runner plus evidence export margin"; ...
                "source >1500 s lower bound plus 40% split-task margin"; ...
                "repository regression aggregate wall-clock ceiling"];
            T=table(timeoutClass,budgetSeconds,rationale, ...
                'VariableNames',{'TimeoutClass','BudgetSeconds', ...
                'BudgetRationale'});
        end

        function T=enumeratedTests()
            suiteName=["test6GScenarioMatrixRunner"; ...
                "test6GScenarioMatrixRunnerNoSummary"];
            fileName=suiteName+".m";
            for index=1:numel(suiteName)
                resolved=string(which(suiteName(index)));
                if strlength(resolved)==0 || ...
                        ~endsWith(lower(resolved),lower(fileName(index)))
                    error("FULLSTACK:ScenarioMatrixTaskMissing", ...
                        "Scenario-matrix task '%s' is not independently callable.", ...
                        suiteName(index));
                end
            end
            T=table(suiteName,fileName, ...
                'VariableNames',{'SuiteName','FileName'});
        end

        function T=tasks()
            taskID=["MATRIX-SUMMARY";"MATRIX-NO-SUMMARY"];
            testName=["test6GScenarioMatrixRunner"; ...
                "test6GScenarioMatrixRunnerNoSummary"];
            timeoutClass=repmat("SCENARIO_MATRIX",2,1);
            % The source run established a >1500 s lower bound for the
            % original three-run monolith.  The two-task split assigns the
            % two-scenario summary group a 2100 s measured-plus-40% budget
            % and a 900 s isolated one-scenario budget.
            timeoutSeconds=[2100;900];
            rationale=["source lower bound 1500 s plus 40% split-task margin"; ...
                "single reduced PRACH scenario baseline ceiling"];
            T=table(taskID,testName,timeoutClass,timeoutSeconds,rationale, ...
                'VariableNames',{'TaskID','TestName','TimeoutClass', ...
                'TimeoutSeconds','BudgetRationale'});
        end

        function results=run(resultsPath,countPath)
            tasks=sixgr.integration.qualification. ...
                ScenarioMatrixRegressionSharder.tasks();
            repository=sixgr.integration.qualification. ...
                FullStackQualificationProfile.repoRoot();
            scratch=string(getenv("SIXGR_REGRESSION_SCRATCH_ROOT"));
            if strlength(strtrim(scratch))==0
                scratch=string(tempdir)+"sixgr-regression-scratch";
            end
            if ~isfolder(scratch),mkdir(scratch);end
            rows=repmat(localRow(),height(tasks),1);
            matlabExecutable=fullfile(matlabroot,"bin","matlab");
            wrapper=fullfile(repository,"tools","run_bounded_command.py");
            for index=1:height(tasks)
                task=tasks(index,:);
                taskScratch=fullfile(scratch,task.TaskID);
                if ~isfolder(taskScratch),mkdir(taskScratch);end
                logPath=fullfile(fileparts(resultsPath), ...
                    lower(task.TaskID)+".log");
                heartbeat=fullfile(fileparts(resultsPath), ...
                    lower(task.TaskID)+"_heartbeat.json");
                code="setup6GRSimToolkit('Verbose',false);" + ...
                    "fprintf('FULLSTACK_TEST_START "+task.TestName+"\n');" + ...
                    "ok="+task.TestName+"();" + ...
                    "fprintf('FULLSTACK_TEST_END "+task.TestName+ ...
                    " PASS\n');assert(ok);";
                command=strjoin([localQuote("python"),localQuote(wrapper), ...
                    "--timeout-seconds",string(task.TimeoutSeconds), ...
                    "--per-test-timeout-seconds", ...
                    string(task.TimeoutSeconds), ...
                    "--heartbeat-seconds","30","--heartbeat-file", ...
                    localQuote(heartbeat),"--log",localQuote(logPath), ...
                    "--",localQuote(matlabExecutable),"-batch", ...
                    localQuote(code)]," ");
                oldScratch=getenv("SIXGR_REGRESSION_SCRATCH_ROOT");
                cleanup=onCleanup(@()setenv( ...
                    "SIXGR_REGRESSION_SCRATCH_ROOT",oldScratch));
                setenv("SIXGR_REGRESSION_SCRATCH_ROOT",taskScratch);
                started=tic;
                [exitCode,~]=system(command);
                duration=toc(started);
                delete(cleanup);
                row=localRow();
                row.TaskID=task.TaskID;
                row.TestName=task.TestName;
                row.Status=localPass(exitCode==0);
                row.DurationSeconds=duration;
                row.FailureIdentifier=localFailureIdentifier(exitCode);
                row.FailureMessage=localFailureMessage(exitCode,logPath);
                row.LastHeartbeat=string(heartbeat);
                row.ChildRunRoot=string(taskScratch);
                row.TimeoutClass=task.TimeoutClass;
                row.TimeoutSeconds=task.TimeoutSeconds;
                rows(index)=row;
            end
            results=struct2table(rows,"AsArray",true);
            sixgr.integration.qualification.QualificationAtomicWriter. ...
                writeTable(resultsPath,results);
            counts=[height(results),nnz(results.Status=="PASS"), ...
                nnz(results.Status~="PASS"),0];
            writematrix(counts,countPath);
        end
    end
end

function value=localQuote(value)
value=replace(string(value),'"','\"');
value='"'+value+'"';
end

function value=localPass(tf)
if tf,value="PASS";else,value="FAIL";end
end

function value=localFailureIdentifier(exitCode)
if exitCode==0
    value="";
elseif exitCode==124
    value="FULLSTACK:RegressionTimeout";
elseif exitCode==125
    value="FULLSTACK:PerTestTimeout";
else
    value="FULLSTACK:ScenarioMatrixTaskFailed";
end
end

function value=localFailureMessage(exitCode,logPath)
if exitCode==0,value="";return;end
value="ExitCode="+exitCode+" Log="+string(logPath);
end

function row=localRow()
row=struct("TaskID","","TestName","","Status","FAIL", ...
    "DurationSeconds",NaN,"FailureIdentifier","","FailureMessage","", ...
    "LastHeartbeat","","ChildRunRoot","","TimeoutClass","", ...
    "TimeoutSeconds",NaN);
end
