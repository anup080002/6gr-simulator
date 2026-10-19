function manifestPath=prepareLLSRepairNextRunManifest(label)
% Resolve configuration only. This does not authorize or execute a run.
root=fileparts(fileparts(mfilename('fullpath'))); cd(root);
setup6GRSimToolkit('Verbose',false);
if nargin<1, label=char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')); end
assert(~isempty(regexp(char(label),'^[A-Za-z0-9_-]+$','once')),'Invalid manifest label.');
out=fullfile(root,'logs','lls_repairs',['next_run_' char(label)]);
assert(~isfolder(out),'Preserve earlier manifests; use a new label.'); mkdir(out);
scenario='simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_adaptation.yaml';
s=sixgr.lls6g.config.loadScenarioConfig(scenario);
cfg=sixgr.lls6g.buildInternalConfig(s,fullfile(out,'not_executed'));
resolved=s.toStruct();
sixgr.util.jsonWrite(fullfile(out,'scenario_resolved.json'),resolved);
sixgr.util.jsonWrite(fullfile(out,'internal_config_resolved.json'),cfg);
[gitStatus,gitRevision]=system('git rev-parse HEAD'); assert(gitStatus==0);
manifest=struct('Contract','LLSNextRunManifest/v2','ExecutionAuthorized',false, ...
    'ReadyForEndToEndAcceptance',false,'MainCheckoutPatched',true, ...
    'BaseGitRevision',strtrim(gitRevision),'SourceState','main_working_tree_with_preserved_user_edits', ...
    'SourceRoot',root, ...
    'Scenario',scenario,'MATLABVersion',version,'Toolboxes',ver, ...
    'ScenarioConfigSHA256',sixgr.phy.waveform.WaveformHash.file(fullfile(out,'scenario_resolved.json')), ...
    'InternalConfigSHA256',sixgr.phy.waveform.WaveformHash.file(fullfile(out,'internal_config_resolved.json')), ...
    'AuditReferences',{{'TS38.212 v18.5.0','TS38.213 v18.5.0','TS38.214 v18.5.0', ...
    'TS38.215 v18.2.0','TS38.321 v18.10.0','TR38.901 v18.0.0'}}, ...
    'ReferenceVersionPolicy','audit versions do not override installed protocol/toolbox versions', ...
    'PhysicalInstrumentCapabilityVerified','UNKNOWN', ...
    'EnergyQualification','BLOCKED_WITH_EVIDENCE: hardware/event-time energy audit incomplete', ...
    'ExportContract',fullfile(root,'docs','repairs','export_contract_v2.md'));
% ScenarioConfig is an object: isfield(object,...) silently drops every
% group. Export its actual resolved Data through the public conversion.
manifest.ResolvedScenario=resolved;
manifest.ScenarioConfigHash=char(s.ConfigHash);
manifest.ConfigSources=repmat(struct('Path',"",'SHA256',""),numel(s.SourceFiles),1);
for k=1:numel(s.SourceFiles)
    manifest.ConfigSources(k)=struct('Path',s.SourceFiles(k), ...
        'SHA256',string(sixgr.util.sha256File(s.SourceFiles(k))));
end
for name=["phy","run","channel","antenna","energy","initial_access","outputs"]
    if isfield(cfg,name), manifest.ResolvedInternal.(name)=cfg.(name); end
end
manifest.CoreRuntimeSource=fullfile(root,'+sixgr','+truth','CoupledTruthRuntime.m');
manifest.CoreRuntimeSHA256=sixgr.util.sha256File(manifest.CoreRuntimeSource);
manifestPath=fullfile(out,'manifest.json');
sixgr.util.jsonWrite(manifestPath,manifest);
fprintf('NEXT_RUN_MANIFEST=%s\n',manifestPath);
end
