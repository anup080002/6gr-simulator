function refreshGuideSnapshots()
%REFRESHGUIDESNAPSHOTS Documentation data only; does not execute a scenario.
guideDir = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(fileparts(guideDir)));
assert(strcmpi(pwd,root), 'Run this helper from the repository root.');
setup6GRSimToolkit('Verbose',false);
scenario = 'simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_adaptation.yaml';
scfg = sixgr.lls6g.config.loadScenarioConfig(scenario);
cfg = sixgr.lls6g.buildInternalConfig(scfg,guideDir);
carrier = sixgr.phy.grid.makeCarrier(cfg);
ofdm = nrOFDMInfo(carrier,'Nfft',4096,'SampleRate',122.88e6,'Windowing',0);
reference = struct('scope','configuration_snapshot_not_simulation_result', ...
    'scenario',scenario,'created',char(datetime('now','Format','yyyy-MM-dd HH:mm:ss')), ...
    'matlab',version,'sources',localSources(root,scfg.SourceFiles), ...
    'resolved',scfg.toStruct(),'ofdm',ofdm,'source_root',root, ...
    'scenario_hash',char(scfg.ConfigHash));
localJSON(fullfile(guideDir,'reference.json'),reference);
localJSON(fullfile(guideDir,'parameter-catalog.json'),sixgr.lls6g.config.loadParameterCatalog('scenario'));
localJSON(fullfile(guideDir,'matrix-catalog.json'),sixgr.lls6g.config.loadParameterCatalog('matrix'));
% Hash the loader itself and every filename it explicitly references. Do not
% treat unreferenced schema overlays as installed configuration options.
loader = fullfile(root,'+sixgr','+lls6g','+config','loadParameterCatalog.m');
tokens = regexp(fileread(loader),'"([^"\r\n]*parameter_catalog[^"\r\n]*\.yaml)"','tokens');
paths = string(loader);
for k=1:numel(tokens)
    paths(end+1,1) = string(fullfile(root,'simulator','configs','schema',tokens{k}{1})); %#ok<AGROW>
end
paths = unique(paths,'stable');
paths = paths(isfile(paths));
metadata = struct('scope','effective_catalog_declared_options_not_runtime_qualification', ...
    'created',reference.created,'matlab',version,'sources',localSources(root,paths));
localJSON(fullfile(guideDir,'catalog-provenance.json'),metadata);
fprintf('Guide snapshots refreshed. No simulation, tests or campaign executed.\n');
end

function rows = localSources(root,paths)
rows = repmat(struct('path','','sha256',''),numel(paths),1);
for k=1:numel(paths)
    rows(k).path = char(replace(extractAfter(string(paths(k)),strlength(string(root))+1),'\','/'));
    rows(k).sha256 = char(sixgr.util.sha256File(paths(k)));
end
end

function localJSON(path,value)
fid = fopen(path,'w','n','UTF-8');
assert(fid>=0,'Unable to write documentation snapshot.');
cleanup = onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true));
end
