function receipt=run_focused_lls_repairs(names,logFolder)
%RUN_FOCUSED_LLS_REPAIRS Explicit affected-test list; never invokes testAll.
arguments
    names (1,:) string
    logFolder (1,1) string
end
assert(~isempty(names)&&all(strlength(names)>0)&&~any(names=="testAll"), ...
    'sixgr:tests:ExplicitFocusedTestsRequired','Supply affected tests explicitly; testAll is not allowed.');
repoRoot=fileparts(fileparts(mfilename('fullpath')));
addpath(repoRoot); cd(repoRoot);
setup6GRSimToolkit('Verbose',false);
if ~isfolder(logFolder), mkdir(logFolder); end
diary(fullfile(logFolder,'matlab.log'));
cleanup=onCleanup(@()diary('off')); %#ok<NASGU>
receipt=struct('Scope',"focused_LLS_core_repairs_not_full_suite", ...
    'PID',feature('getpid'),'StartedUTC',string(datetime('now','TimeZone','UTC')), ...
    'Completed',false,'Ok',false,'Tests',names,'CompletedCount',0, ...
    'Passed',false(size(names)),'Seconds',NaN(size(names)), ...
    'Errors',strings(size(names)),'CurrentTest',"");
publish();
for n=1:numel(names)
    receipt.CurrentTest=names(n); publish();
    fprintf('\nFOCUSED_START %d/%d %s\n',n,numel(names),names(n));
    started=tic;
    try
        executeRegressionTest(str2func(names(n)));
        receipt.Passed(n)=true;
        fprintf('FOCUSED_PASS %s\n',names(n));
    catch failure
        receipt.Errors(n)=string(getReport(failure,'extended','hyperlinks','off'));
        fprintf(2,'FOCUSED_FAIL %s\n%s\n',names(n),receipt.Errors(n));
    end
    receipt.Seconds(n)=toc(started); receipt.CompletedCount=n; publish();
end
receipt.CurrentTest=""; receipt.Completed=true; receipt.Ok=all(receipt.Passed);
receipt.CompletedUTC=string(datetime('now','TimeZone','UTC')); publish();
fprintf('FOCUSED_COMPLETE passed=%d failed=%d total=%d\n', ...
    nnz(receipt.Passed),nnz(~receipt.Passed),numel(names));
    function publish()
        save(fullfile(logFolder,'receipt.mat'),'receipt');
        sixgr.util.jsonWrite(fullfile(logFolder,'receipt.json'),receipt);
    end
end
