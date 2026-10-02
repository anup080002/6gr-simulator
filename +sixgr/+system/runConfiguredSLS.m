function out = runConfiguredSLS(request, outputDir, runTag)
%RUNCONFIGUREDSLS One native, mode-labelled SLS execution and durable receipt.
assert(request.Mode == "SLS",'sixgr:simulation:ModeMismatch','Expected SLS request.');
if strlength(string(runTag)) == 0, runTag = char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')); end
assert(~isempty(regexp(char(runTag),'^[A-Za-z0-9][A-Za-z0-9_.-]*$','once')), ...
    'sixgr:simulation:RunTag','runTag must be a safe folder identifier.');
cfg = request.Config;
folder = fullfile(sixgr.report.resolveResultsRoot(outputDir),'sls', ...
    cfg.meta.scenarioID,char(runTag));
folder=char(folder);
assert(~isfolder(folder),'sixgr:simulation:ExistingRun','Run folder already exists; use a fresh tag: %s',folder);
mkdir(folder); mkdir(fullfile(folder,'meta')); mkdir(fullfile(folder,'meta','input_configs'));
cfg.run.runTag=char(runTag); cfg.run.runFolder=folder; cfg.outputs.runFolder=folder;
% Do not keep a previously imported LLS folder as the heartbeat destination.
if isfield(cfg,'lls6g'), cfg.lls6g.outputRunFolder=folder; end
cfg.run.executionMode='SLS'; cfg.run.module='sixgr.system.SystemLevelRunner';
receipt=struct('Schema','sixgr.simulation_run/v1','ExecutionMode','SLS', ...
    'ScenarioID',cfg.meta.scenarioID,'RunTag',char(runTag),'RunFolder',folder, ...
    'ExecutionBackend',cfg.system.phyBackend,'Status','initializing', ...
    'ExecutionOk',false,'PrimaryStudyAccepted',false,'MatlabPID',feature('getpid'), ...
    'UpdatedUTC',localUTC(),'ErrorIdentifier','','ErrorMessage','');
receipt.CreatedUTC=receipt.UpdatedUTC;
localReceipt(folder,receipt);
try
    sixgr.util.jsonWrite(fullfile(folder,'meta','scenario_config_resolved.json'),request.Data);
    sixgr.util.jsonWrite(fullfile(folder,'meta','internal_config_resolved.json'),sixgr.util.jsonSafeValue(cfg));
    sourceRows=struct('Path',{},'SHA256',{},'RetainedPath',{});
    for k=1:numel(request.SourceFiles)
        source=request.SourceFiles(k); [~,name,ext]=fileparts(source);
        retained=fullfile('meta','input_configs',sprintf('%03d_%s%s',k,name,ext));
        copyfile(source,fullfile(folder,retained));
        fid=fopen(source,'rb'); cleanup=onCleanup(@()fclose(fid)); bytes=fread(fid,Inf,'*uint8'); clear cleanup
        sourceRows(end+1)=struct('Path',source,'SHA256',sixgr.util.sha256Hex(bytes),'RetainedPath',retained); %#ok<AGROW>
    end
    sixgr.util.jsonWrite(fullfile(folder,'meta','input_sources.json'),sourceRows);
    [gitStatus,revision]=system('git rev-parse HEAD');
    [dirtyStatus,dirty]=system('git status --porcelain');
    sixgr.util.jsonWrite(fullfile(folder,'meta','environment.json'),struct( ...
        'MATLABVersion',version,'Toolboxes',ver,'GitExitCode',gitStatus, ...
        'GitRevision',strtrim(revision),'DirtyCheckExitCode',dirtyStatus, ...
        'DirtyWorktree',~isempty(strtrim(dirty)),'Seed',cfg.run.seed));
    receipt.Status='running'; receipt.UpdatedUTC=localUTC(); localReceipt(folder,receipt);
    ctx=sixgr.core.SimContext(cfg,'RunFolder',folder,'RootDir',pwd);
    loggerCleanup=onCleanup(@()ctx.Logger.close()); %#ok<NASGU>
    result=sixgr.system.SystemLevelRunner.run(ctx,struct());
    receipt.ExecutionOk=logical(result.Ok);
    if receipt.ExecutionOk, receipt.Status='completed'; else, receipt.Status='failed'; end
    % Execution success is not acceptance of an RF/calibration/statistical study.
    if isfield(result,'Errors'), receipt.Errors=string(result.Errors); end
    receipt.UpdatedUTC=localUTC(); localReceipt(folder,receipt);
    out=struct('Ok',receipt.ExecutionOk,'Mode',"SLS",'RunFolder',string(folder), ...
        'PrimaryStudyAccepted',false,'Result',result,'Receipt',receipt);
catch ME
    receipt.Status='failed'; receipt.ErrorIdentifier=ME.identifier;
    receipt.ErrorMessage=ME.message; receipt.UpdatedUTC=localUTC(); localReceipt(folder,receipt);
    rethrow(ME)
end
end

function localReceipt(folder,receipt)
path=fullfile(folder,'meta','simulation_run.json');
temporary=char(string(path)+".tmp"); sixgr.util.jsonWrite(temporary,receipt); movefile(temporary,path,'f');
end
function stamp=localUTC()
stamp=char(datetime('now','TimeZone','UTC','Format',"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"));
end
