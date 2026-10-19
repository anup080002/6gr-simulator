function runLLSRepairChecks(label,testNames,sourceRoot)
% Small deterministic tests in a dedicated MATLAB process; no pool/scenario.
root=fileparts(fileparts(mfilename('fullpath')));
if nargin<3, sourceRoot=root; end
cd(sourceRoot); addpath(sourceRoot,fullfile(sourceRoot,'tests'));
setup6GRSimToolkit('Verbose',false);
assert(~isempty(regexp(char(label),'^[A-Za-z0-9_-]+$','once')), ...
    'sixgr:repair:InvalidLabel','Use a simple unique label, not a path.');
out=fullfile(root,'logs','lls_repairs',label);
assert(~isfolder(out),'sixgr:repair:ExistingReceipt','Preserve existing evidence; use a new label.');
mkdir(out);
environment=struct('MATLABVersion',version,'Release',version('-release'), ...
    'Toolboxes',ver,'ProjectRoot',sourceRoot,'ProcessID',feature('getpid'));
localJSON(fullfile(out,'environment.json'),environment);
rows=struct('Test',{},'Status',{},'ElapsedSeconds',{},'ErrorID',{},'Error',{}, ...
    'TestSource',{},'TestSHA256',{},'SourcePathsVerified',{});
for k=1:numel(testNames)
    timer=tic; row=struct('Test',string(testNames{k}),'Status',"PASS", ...
        'ElapsedSeconds',NaN,'ErrorID',"",'Error',"", ...
        'TestSource',"",'TestSHA256',"",'SourcePathsVerified',false);
    try
        row.TestSource=string(which(testNames{k}));
        assert(strcmpi(row.TestSource,fullfile(sourceRoot,'tests',testNames{k}+".m")), ...
            'sixgr:repair:WrongTestSource','Test resolves outside the selected tests directory.');
        row.TestSHA256=string(sixgr.util.sha256File(row.TestSource));
        verifySourcePaths(sourceRoot);
        assert(logical(feval(testNames{k})), 'Test did not return true.');
        verifySourcePaths(sourceRoot);
        assert(row.TestSHA256==string(sixgr.util.sha256File(row.TestSource)), ...
            'sixgr:repair:ChangedTestSource','Test source changed while executing.');
        row.SourcePathsVerified=true;
    catch ME
        row.Status="FAIL"; row.ErrorID=string(ME.identifier);
        row.Error=string(getReport(ME,'extended','hyperlinks','off'));
    end
    row.ElapsedSeconds=toc(timer); rows(end+1)=row; %#ok<AGROW>
    disp(row); localJSON(fullfile(out,'receipt.json'),rows);
end
assert(all(string({rows.Status})=="PASS"),'sixgr:repair:FailedTests','Some affected checks failed; inspect receipt.');
end
function verifySourcePaths(root)
symbols=["sixgr.truth.CoupledTruthRuntime","sixgr.link.deriveCodingTrialMetrics", ...
    "sixgr.link.deriveModulationTrackingMetrics","sixgr.phy.phycode.rateMatchLDPC"];
for symbol=symbols
    actual=string(which(symbol));
    assert(startsWith(lower(actual),lower(string(root)+filesep)) && ...
        ~contains(lower(actual),[filesep 'repair_outputs' filesep]), ...
        'sixgr:repair:WrongProductionSource','Wrong production source for %s: %s',symbol,actual);
end
end
function localJSON(path,value)
fid=fopen(path,'w'); assert(fid>=0); cleanup=onCleanup(@() fclose(fid));
fprintf(fid,'%s',jsonencode(value,'PrettyPrint',true));
end
