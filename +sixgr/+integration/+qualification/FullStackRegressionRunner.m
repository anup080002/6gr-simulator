classdef FullStackRegressionRunner
    %FULLSTACKREGRESSIONRUNNER Execute ten gates within the SC-30 budget.
    %
    % Tests run in child processes so an over-budget suite can be stopped
    % without terminating the WebGUI-owned orchestrator or an IDE MATLAB
    % session. The summary is rewritten after every suite.
    methods (Static)
        function T = pending(ctx)
            rows = localPendingRows();
            T = localWrite(ctx,rows);
        end

        function T = run(ctx)
            rows = localPendingRows();
            localWrite(ctx,rows);
            budgetSeconds = localBudgetSeconds(ctx);
            budgetTimer = tic;
            countDir = fullfile(ctx.ReportsDir,"regression");
            sixgr.util.ensureFolder(countDir);
            matlabExecutable = fullfile(matlabroot,"bin","matlab");

            countPath = fullfile(countDir,"matlab_full_regression_counts.csv");
            code = localTestAllCode(countPath, ...
                "testAll('Verbose',false,'ShowSlowest',10)");
            rows(1) = localBoundedGate(ctx,rows(1).Suite, ...
                [matlabExecutable,"-batch",code],countPath, ...
                localSuiteTimeout(ctx,budgetSeconds,budgetTimer, ...
                rows(1).Suite),1,numel(rows));
            localWrite(ctx,rows);

            countPath = fullfile(countDir,"matlab_fullstack_counts.csv");
            code = localRuntestsCode(countPath,"*FullStack*");
            rows(2) = localBoundedGate(ctx,rows(2).Suite, ...
                [matlabExecutable,"-batch",code],countPath, ...
                localSuiteTimeout(ctx,budgetSeconds,budgetTimer, ...
                rows(2).Suite),2,numel(rows));
            localWrite(ctx,rows);

            countPath = fullfile(countDir,"matlab_integration_counts.csv");
            code = localRuntestsCode(countPath,"*Integration*");
            rows(3) = localBoundedGate(ctx,rows(3).Suite, ...
                [matlabExecutable,"-batch",code],countPath, ...
                localSuiteTimeout(ctx,budgetSeconds,budgetTimer, ...
                rows(3).Suite),3,numel(rows));
            localWrite(ctx,rows);

            countPath = fullfile(countDir,"matlab_config_channel_counts.csv");
            call = "testAll('Names',{'testConfig','testLLS_DL'," + ...
                "'testLLS_UL','testLLS_ReferencePoints'}," + ...
                "'Verbose',false,'ShowSlowest',4)";
            code = localTestAllCode(countPath,call);
            rows(4) = localBoundedGate(ctx,rows(4).Suite, ...
                [matlabExecutable,"-batch",code],countPath, ...
                localSuiteTimeout(ctx,budgetSeconds,budgetTimer, ...
                rows(4).Suite),4,numel(rows));
            localWrite(ctx,rows);

            countPath = fullfile(countDir,"matlab_truth_export_counts.csv");
            call = "testAll('Names',{'testE2E_FastVsTruth'," + ...
                "'testE2E_TruthPacketSemanticCampaign'," + ...
                "'testStrictProxyGuards','testSchedulerGrantConsistency'," + ...
                "'testArtifactIntegrity'},'Verbose',false,'ShowSlowest',5)";
            code = localTestAllCode(countPath,call);
            rows(5) = localBoundedGate(ctx,rows(5).Suite, ...
                [matlabExecutable,"-batch",code],countPath, ...
                localSuiteTimeout(ctx,budgetSeconds,budgetTimer, ...
                rows(5).Suite),5,numel(rows));
            localWrite(ctx,rows);

            rows(6) = localBoundedGate(ctx,rows(6).Suite, ...
                ["python","-m","compileall","apps","backend","frontend", ...
                "tests"],"",localSuiteTimeout(ctx,budgetSeconds, ...
                budgetTimer,rows(6).Suite),6,numel(rows));
            localWrite(ctx,rows);
            rows(7) = localBoundedGate(ctx,rows(7).Suite, ...
                ["python","-m","pytest","-q"],"", ...
                localSuiteTimeout(ctx,budgetSeconds,budgetTimer, ...
                rows(7).Suite),7,numel(rows));
            localWrite(ctx,rows);
            rows(8) = localBoundedGate(ctx,rows(8).Suite, ...
                ["python","-m","pytest","-q","tests","-k", ...
                "lls_web_dashboard"],"", ...
                localSuiteTimeout(ctx,budgetSeconds,budgetTimer, ...
                rows(8).Suite),8,numel(rows));
            localWrite(ctx,rows);
            rows(9) = localBoundedGate(ctx,rows(9).Suite, ...
                ["python","-m","pytest","-q", ...
                "tests/test_full_stack_webgui_e2e.py"],"", ...
                localSuiteTimeout(ctx,budgetSeconds,budgetTimer, ...
                rows(9).Suite),9,numel(rows));
            localWrite(ctx,rows);
            verifier = fullfile(ctx.Profile.PackRoot, ...
                "verify_full_stack_qualification_artifacts.py");
            rows(10) = localBoundedGate(ctx,rows(10).Suite, ...
                ["python",verifier,ctx.RunFolder,ctx.Profile.PackRoot, ...
                "--preset",ctx.Profile.Preset],"", ...
                localSuiteTimeout(ctx,budgetSeconds,budgetTimer, ...
                rows(10).Suite),10,numel(rows));
            T = localWrite(ctx,rows);
        end
    end
end

function rows = localPendingRows()
names = ["MATLAB_FULL_REGRESSION";"MATLAB_FULLSTACK_FOCUSED"; ...
    "MATLAB_INTEGRATION_FOCUSED";"MATLAB_CONFIG_CHANNEL_GATES"; ...
    "MATLAB_TRUTH_EXPORT_GATES";"PYTHON_COMPILEALL";"PYTEST"; ...
    "WEBGUI_UNIT_TESTS";"PLAYWRIGHT_FULLSTACK"; ...
    "QUALIFICATION_ARTIFACT_VERIFIER"];
rows = repmat(localRow(),numel(names),1);
for index = 1:numel(names)
    rows(index).Suite = char(names(index));
    rows(index).MandatoryTests = 1;
    rows(index).BlockedTests = 1;
    rows(index).Details = "Regression gate has not executed yet.";
end
end

function row = localBoundedGate(ctx,name,args,countPath,timeoutSeconds, ...
        shardIndex,shardCount)
row = localRow();
row.Suite = char(name);
row.MandatoryTests = 1;
row.ShardIndex = shardIndex;
row.ShardCount = shardCount;
row.SuiteTimeoutSeconds = timeoutSeconds;
row.PerTestTimeoutSeconds = localRegressionNumber(ctx, ...
    "per_test_timeout_minutes",25)*60;
if ~(isfinite(timeoutSeconds) && timeoutSeconds >= 1)
    row.BlockedTests = 1;
    row.Details = "FULLSTACK:RegressionBudgetExhausted: " + ...
        "SC-30 wall-clock budget was exhausted before this suite.";
    return;
end
logDir = fullfile(ctx.ReportsDir,"regression");
sixgr.util.ensureFolder(logDir);
logPath = fullfile(logDir,lower(string(name))+".log");
heartbeatPath = fullfile(logDir,lower(string(name))+"_heartbeat.json");
row.HeartbeatArtifact = char(replace(string(heartbeatPath), ...
    string(ctx.RunFolder)+filesep,""));
wrapper = fullfile(ctx.Profile.RepositoryRoot,"tools", ...
    "run_bounded_command.py");
heartbeatSeconds = localRegressionNumber(ctx,"heartbeat_seconds",30);
command = strjoin([localQuote("python"),localQuote(wrapper), ...
    "--timeout-seconds",compose("%.3f",timeoutSeconds), ...
    "--per-test-timeout-seconds", ...
    compose("%.3f",row.PerTestTimeoutSeconds), ...
    "--heartbeat-seconds",compose("%.3f",heartbeatSeconds), ...
    "--heartbeat-file",localQuote(heartbeatPath), ...
    "--log",localQuote(logPath),"--",arrayfun(@localQuote,args)]," ");
started = tic;
[exitCode,launcherOutput] = system(command);
row.DurationSeconds = toc(started);
row.ExecutedTests = 1;
if strlength(string(countPath)) > 0 && isfile(countPath)
    counts = readmatrix(countPath);
    counts = reshape(double(counts),1,[]);
    if numel(counts) >= 4 && all(isfinite(counts(1:4)))
        row.MandatoryTests = counts(1);
        row.ExecutedTests = counts(1);
        row.PassedTests = counts(2);
        row.FailedTests = counts(3);
        row.SkippedTests = counts(4);
    end
end
if exitCode == 0
    row.PassedTests = max(row.PassedTests,1);
    row.Status = "PASS";
elseif exitCode == 124
    row.FailedTests = max(row.FailedTests,1);
    row.BlockedTests = 1;
    row.Details = sprintf( ...
        "FULLSTACK:RegressionTimeout: %s exceeded %.3f seconds. Log: %s", ...
        name,timeoutSeconds,logPath);
else
    row.FailedTests = max(row.FailedTests,1);
    row.Details = localFailureDetails(exitCode,logPath,launcherOutput);
end
row.LastTest = char(localLastTest(logPath));
end

function value = localFailureDetails(exitCode,logPath,launcherOutput)
text = string(launcherOutput);
if isfile(logPath)
    text = string(fileread(logPath));
end
if strlength(text) > 4096
    text = extractAfter(text,strlength(text)-4096);
end
value = sprintf("ExitCode=%d Log=%s Output=%s", ...
    exitCode,logPath,text);
end

function secondsValue = localBudgetSeconds(ctx)
minutesValue = localRegressionNumber(ctx,"total_budget_minutes",NaN);
if ~(isscalar(minutesValue)&&isfinite(minutesValue)&&minutesValue>0)
    error("FULLSTACK:InvalidRegressionBudget", ...
        "qualification.regression.total_budget_minutes must be positive.");
end
secondsValue = 60*minutesValue;
end

function secondsValue = localSuiteTimeout(ctx,totalSeconds,budgetTimer,~)
remaining = max(0,totalSeconds-toc(budgetTimer));
configured = 60*localRegressionNumber(ctx, ...
    "per_suite_timeout_minutes",90);
secondsValue = floor(min(remaining,configured));
end

function code = localTestAllCode(countPath,call)
path = localMATLABLiteral(countPath);
code = "setup6GRSimToolkit('Verbose',false);r=" + call + ";" + ...
    "writematrix([numel(r.results),nnz([r.results.ok])," + ...
    "nnz(~[r.results.ok]),0],'" + path + "');assert(r.ok);";
end

function code = localRuntestsCode(countPath,pattern)
path = localMATLABLiteral(countPath);
code = "setup6GRSimToolkit('Verbose',false);r=runtests(" + ...
    "fullfile(pwd,'tests'),'IncludeSubfolders',true,'Name','" + ...
    pattern + "');writematrix([numel(r),nnz([r.Passed])," + ...
    "nnz([r.Failed]),nnz([r.Incomplete])],'" + path + ...
    "');assertSuccess(r);";
end

function value = localMATLABLiteral(value)
value = replace(string(value),"'","''");
end

function value = localQuote(value)
value = string(value);
value = replace(value,'"','\"');
value = '"' + value + '"';
end

function T = localWrite(ctx,rows)
T = struct2table(rows,"AsArray",true);
sixgr.util.csvWriteTable(fullfile(ctx.CSVDir, ...
    "full_stack_regression_summary.csv"),T);
end

function row = localRow()
row = struct("Suite","","MandatoryTests",0,"ExecutedTests",0, ...
    "PassedTests",0,"FailedTests",0,"SkippedTests",0, ...
    "BlockedTests",0,"Status","FAIL","DurationSeconds",NaN, ...
    "ShardIndex",0,"ShardCount",10,"SuiteTimeoutSeconds",NaN, ...
    "PerTestTimeoutSeconds",NaN,"HeartbeatArtifact","", ...
    "LastTest","","Details","");
end

function value = localRegressionNumber(ctx,name,default)
raw = sixgr.util.structGet(ctx.Profile.Configuration, ...
    "regression."+string(name),default);
if isnumeric(raw)
    value = double(raw);
else
    value = str2double(string(raw));
end
if ~(isscalar(value)&&isfinite(value)&&value>0)
    value = default;
end
end

function value = localLastTest(logPath)
value = "";
if ~isfile(logPath),return;end
text = string(fileread(logPath));
tokens = regexp(char(text), ...
    '(?m)^(?:FULLSTACK_TEST_START|Running|Starting|Test)\s+([^\r\n]+)$', ...
    'tokens');
if ~isempty(tokens)
    value = strtrim(string(tokens{end}{1}));
end
end
