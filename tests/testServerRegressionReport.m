function ok=testServerRegressionReport()
% Intentional probe failures must remain failed, with one real CSV row/test.
setup6GRSimToolkit('Verbose',false);
originalPath=path;
keys={'sixgrRegressionHarnessProbeMode','sixgrRegressionHarnessProbeExecuted'};
present=cellfun(@(key)isappdata(0,key),keys);
values=cell(size(keys));
for k=find(present), values{k}=getappdata(0,keys{k}); end
cleanup=onCleanup(@()localRestore(originalPath,keys,present,values)); %#ok<NASGU>
root=fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root,'scripts'));
for mode=["pass","fail"]
    setappdata(0,keys{1},char(mode));
    destination=tempname(fullfile(root,'logs')); mkdir(destination);
    caught="";
    try
        run_server_testall(destination,false,{'regressionHarnessProbeTest'});
    catch cause
        caught=string(cause.identifier);
    end
    summary=jsondecode(fileread(fullfile(destination,'summary.json')));
    retained=load(fullfile(destination,'test_report.mat'),'report');
    rows=readtable(fullfile(destination,'tests.csv'),'TextType','string');
    failures=readtable(fullfile(destination,'failures.csv'),'TextType','string');
    assert(summary.test_count==1 && numel(retained.report.results)==1 && height(rows)==1);
    assert(string(rows.name)=="regressionHarnessProbeTest");
    assert(~summary.baseline_12db_qualified);
    if mode=="pass"
        assert(caught=="" && string(summary.status)=="passed" && ...
            summary.failed_count==0 && height(failures)==0 && logical(rows.ok));
    else
        assert(caught=="sixgr:tests:ServerRegressionFailed" && ...
            string(summary.status)=="failed" && summary.failed_count==1 && ...
            height(failures)==1 && ~logical(rows.ok));
        original=retained.report.results;
        assert(string(failures.msg)==string(original.msg) && ...
            string(failures.identifier)==string(original.identifier));
        assert(string(summary.error_identifier)==caught);
    end
    fprintf('SERVER_SINGLE_TEST_REPORT_EVIDENCE: intentional_%s root=%s\n',mode,destination);
end
ok=true;
end

function localRestore(originalPath,keys,present,values)
path(originalPath);
for k=1:numel(keys)
    if present(k), setappdata(0,keys{k},values{k});
    elseif isappdata(0,keys{k}), rmappdata(0,keys{k}); end
end
end
