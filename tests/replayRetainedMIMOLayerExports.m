function folder=replayRetainedMIMOLayerExports(runFolder,sourceFolder)
% Report-only verification from retained PHY evidence. Never a new PHY run
% or scenario pass, and never overwrite the source run's failed artifacts.
setup6GRSimToolkit('Verbose',false);
sixgr.db.deactivateArtifactStore();
folder=fullfile(pwd,'results','lls','adaptive_layer_export_replay', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(folder);
sourceHashes=strings(2,1); names=["dl_pdsch_trials.csv";"ul_pusch_trials.csv"];
for i=1:2
    source=fullfile(sourceFolder,'air_interface','csv',names(i));
    assert(isfile(source),'Retained DL and UL source tables are required.');
    sourceHashes(i)=sixgr.phy.waveform.WaveformHash.file(source);
    target=fullfile(folder,'air_interface','csv',names(i));
    sixgr.util.ensureDir(target); copyfile(source,target);
end
configPath=fullfile(runFolder,'meta','scenario_config_resolved.yaml');
s=sixgr.lls6g.config.loadScenarioConfig(configPath);
cfg=sixgr.lls6g.buildInternalConfig(s,folder);
raw=sixgr.kpi.loadDirectionRawTables(struct(),'RunFolder',folder,'PreferPersistedPrimary',true);
% Beam candidate arrays were also lost when initial rows contained NaN.
beamFields=["BeamScoreVector_dB","TopBeamIndexSet","TopBeamGainSet_dB"];
dlSource=fullfile(sourceFolder,'air_interface','csv','dl_pdsch_trials.csv');
options=detectImportOptions(dlSource,'Delimiter',',','VariableNamingRule','preserve');
options.VariableNamesLine=1; options.DataLines=[2 Inf];
options=setvartype(options,cellstr(beamFields),'string');
expectedDL=readtable(dlSource,options);
for name=beamFields
    assert(isequaln(raw.DL.(name),expectedDL.(name)), ...
        'Retained beam candidate measurements must survive the same publication reader.');
end
[~,originalRunId]=fileparts(runFolder);
artifacts=sixgr.mimo.exportMIMOEvidenceArtifacts(folder,cfg,raw, ...
    'RunId',originalRunId,'ScenarioName',s.get('meta.scenario_id'),'StrictMode',true);
rank=sixgr.util.csvReadTable(fullfile(folder,'beamforming','csv','rank_layer_trials.csv'),'TextType','string');
layers=sixgr.util.csvReadTable(fullfile(folder,'beamforming','csv','mimo_layer_metrics.csv'),'TextType','string');
checked=0;
for direction=["DL","UL"]
    T=raw.(direction);
    for n=find(double(T.Layers)>1).'
        expectedSINR=str2double(split(string(T.PostEqSINRPerLayer_dB(n)),'|'));
        expectedEVM=str2double(split(string(T.EVMPerLayer_rms(n)),'|'));
        rankRow=rank(rank.Direction==direction & rank.TrialId==n,:);
        perLayer=sortrows(layers(layers.Direction==direction & layers.TrialId==n,:),'LayerIndex');
        assert(height(rankRow)==1 && height(perLayer)==T.Layers(n) && ...
            numel(expectedSINR)==T.Layers(n) && numel(expectedEVM)==T.Layers(n));
        assert(all(isfinite(perLayer.PostEqSINRdB)) && ...
            max(abs(perLayer.PostEqSINRdB-expectedSINR))<1e-8 && ...
            max(abs(perLayer.EVMrms-expectedEVM))<1e-12 && ...
            all(perLayer.EVMStatus=="measured_per_layer"));
        assert(all(perLayer.DecodeCrcPass==T.CRCPass(n)) && ...
            rankRow.DecodeCrcPass==T.CRCPass(n), ...
            'Restoring measurements must not turn failed decoding into a pass.');
        assert(~contains(string(rankRow.FailureReason),"receiver_per_layer_evidence_missing"));
        checked=checked+1;
    end
end
assert(checked>0,'The retained execution must include real multilayer trials.');
for i=1:2
    assert(sixgr.phy.waveform.WaveformHash.file(fullfile(sourceFolder, ...
        'air_interface','csv',names(i)))==sourceHashes(i));
end
sixgr.util.jsonWrite(fullfile(folder,'retained_source_manifest.json'),struct( ...
    'Scope',"report_only_replay_of_retained_PHY_rows_not_a_scenario_rerun", ...
    'SourceRunFolder',string(runFolder),'SourceFolder',string(sourceFolder), ...
    'SourceFiles',names,'SourceSHA256',sourceHashes, ...
    'NewPHYExecutions',0,'OriginalSourceFilesChanged',false, ...
    'VerifiedMultilayerTrials',checked,'MIMOStrictOk',artifacts.StrictOk, ...
    'MIMOFailureReason',string(artifacts.FailureReason)));
fprintf('RETAINED_MIMO_LAYER_EXPORT_PASS trials=%d original_sources_unchanged=1 full_MIMO_gate=%d folder=%s\n', ...
    checked,artifacts.StrictOk,folder);
end
