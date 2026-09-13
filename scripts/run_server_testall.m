function run_server_testall(logDir,preflightOnly,names)
% Persistent diagnostics around the normal testAll entry point; no test skips.
if nargin<2, preflightOnly=false; end
if nargin<3, names={}; end
assert(isfolder(logDir),'sixgr:tests:MissingLogFolder','Launcher must create a unique log folder.');
summary=struct('schema_version',1,'status','running','scope','testAll', ...
    'started_utc',localUTC(),'matlab_version',version,'matlab_release',version('-release'), ...
    'computer',computer,'selected_tests',{names},'baseline_12db_qualified',false);
if preflightOnly, summary.scope='preflight_only'; elseif ~isempty(names), summary.scope='focused_tests'; end
localJSON(fullfile(logDir,'summary.json'),summary);
try
    fprintf('SERVER_VALIDATION_START scope=%s MATLAB=%s release=%s\n',summary.scope,version,version('-release'));
    environment=struct('matlab_version',version,'matlab_release',version('-release'), ...
        'computer',computer,'toolboxes',ver,'mex_extension',mexext);
    localJSON(fullfile(logDir,'environment.json'),environment);
    for k=1:numel(environment.toolboxes)
        fprintf('TOOLBOX %s | %s | %s\n',environment.toolboxes(k).Name, ...
            environment.toolboxes(k).Version,environment.toolboxes(k).Release);
    end
    environment.setup=setup6GRSimToolkit('Verbose',true,'RunToolboxChecks',true);
    environment.yaml=sixgr.lls6g.config.ensureYAMLRuntime('RequireYAML',true,'Verbose',true);
    localJSON(fullfile(logDir,'environment.json'),environment);
    % Inventory unavailable symbols honestly. Full testAll still runs and
    % decides applicability; this launcher never removes tests by version.
    if ~strcmp(version('-release'),'2026a')
        fprintf('MATLAB_RELEASE_UNQUALIFIED: current local reference is R2026a; compatibility with this release must be established by these results.\n');
    end
    if ~preflightOnly
        if isempty(names), report=testAll; else, report=testAll('Names',names); end
        save(fullfile(logDir,'test_report.mat'),'report');
        localJSON(fullfile(logDir,'test_report.json'),report);
        if ~isempty(report.results)
            rows=struct2table(report.results);
            writetable(rows,fullfile(logDir,'tests.csv'));
            writetable(rows(~rows.ok,:),fullfile(logDir,'failures.csv'));
        end
        summary.test_count=numel(report.results);
        summary.failed_count=nnz(~[report.results.ok]);
        summary.duration_s=report.total_duration_s;
        assert(report.ok,'sixgr:tests:ServerRegressionFailed', ...
            '%d of %d tests failed. Share this run''s logs folder.',summary.failed_count,summary.test_count);
    end
    summary.status='passed'; summary.finished_utc=localUTC();
    localJSON(fullfile(logDir,'summary.json'),summary);
    fprintf('SERVER_VALIDATION_PASS scope=%s NOT_12DB_QUALIFICATION=1\n',summary.scope);
catch cause
    summary.status='failed'; summary.finished_utc=localUTC();
    summary.error_identifier=cause.identifier;
    summary.error_report=getReport(cause,'extended','hyperlinks','off');
    localJSON(fullfile(logDir,'summary.json'),summary);
    fprintf(2,'%s\n',summary.error_report);
    rethrow(cause);
end
end

function value=localUTC()
value=char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss.SSSXXX'));
end

function localJSON(path,value)
[fid,msg]=fopen(path,'w');
assert(fid>=0,'sixgr:tests:LogWriteFailed','Cannot open diagnostic file: %s',msg);
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(value));
end
