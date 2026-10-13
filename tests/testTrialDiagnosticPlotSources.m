function ok=testTrialDiagnosticPlotSources()
% Numerical report fixtures; never received PHY evidence.
root=fullfile(pwd,'results','lls','trial_plot_sources', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
folder=fullfile(root,'air_interface','csv'); mkdir(folder);
raw=struct();
for direction=["DL","UL"]
    raw.(direction)=table([18;30],[1;2],[1/sqrt(2);pi],strings(2,1), ...
        'VariableNames',{'SNR_dB','TrialIndex','PostEqSINR_dB','UnobservedContext'});
    samples=table([1;2],[0.2;0.3],[-0.1;0.5], ...
        'VariableNames',{'SampleIndex','EqualizedI','EqualizedQ'});
    path=fullfile(folder,lower(direction)+'_constellation_preview.csv');
    sixgr.util.csvWriteTable(path,samples,'PreserveSchema',true);
    raw.(direction+'ConstellationPath')=string(path);
    % Only the persisted two samples may be plotted, not this wider buffer.
    raw.(direction+'Constellation')=[samples;samples];
end
sources=sixgr.report.writeTrialDiagnosticPlotSources(root,raw);
for direction=["DL","UL"]
    assert(isequaln(sources.(direction),raw.(direction)) && ...
        height(sources.(direction+'Constellation'))==2 && ...
        endsWith(sources.(direction+'ConstellationPath'),'_preview.csv'));
    path=sources.(direction+'Path'); before=fileread(path);
    previewPath=sources.(direction+'ConstellationPath'); previewBefore=fileread(previewPath);
    for pass=1:2
        sixgr.truth.sanitizeLLSArtifactCSVs(root);
        sixgr.report.annotateScenarioCSVArtifacts(root,'test','hash','numerical');
        assert(strcmp(before,fileread(path)));
        assert(strcmp(previewBefore,fileread(previewPath)));
    end
    T=sixgr.util.csvReadTable(path);
    assert(isequal(T.PostEqSINR_dB,raw.(direction).PostEqSINR_dB));
end
bad=raw; bad.DLConstellationPath="";
try
    sixgr.report.writeTrialDiagnosticPlotSources(root,bad);
    error('test:ExpectedFailure','Nonempty samples without a persisted source were accepted.');
catch err
    assert(strcmp(err.identifier,'sixgr:report:TrialConstellationSourceMissing'));
end
empty=sixgr.report.writeTrialDiagnosticPlotSources(root,struct());
assert(isempty(empty.DL) && isempty(empty.DLConstellation) && ...
    empty.DLPath=="" && empty.DLConstellationPath=="");

% Normal completion and recovery share one actual renderer. Eight sweep
% points occupy one CSV/PNG per metric, never a pooled distribution/summary.
plotRaw=struct();
snr=[40;30;20;10;0;-10;-20;-30];
for direction=["DL","UL"]
    plotRaw.(direction)=table(snr,(1:8).',snr-1,(-8:-1).',ones(8,1), ...
        repmat([1;2],4,1),'VariableNames', ...
        {'SNR_dB','TrialIndex','PostEqSINR_dB','ChannelGain_dB','UEIndex','NumLayers'});
end
images=sixgr.report.exportTrialDiagnosticPlots(root,plotRaw,true);
assert(numel(images)==4 && all(cellfun(@isfile,images)));
for direction=["DL","UL"]
    summary=sixgr.util.csvReadTable(fullfile(folder, ...
        lower(direction)+'_channel_gain_distribution_summary.csv'));
    assert(height(summary)==8 && isequal(summary.ConfiguredSNR_dB,snr) && ...
        all(summary.n_samples==1) && isequal(summary.mean,(-8:-1).'));
end
lineagePath=fullfile(folder,'runtime_trial_plot_lineage.csv');
lineage=sixgr.util.csvReadTable(lineagePath,'TextType','string');
assert(height(lineage)==4 && all(lineage.Status=="pass") && ...
    all(lineage.ProducerModule=="sixgr.report.exportTrialDiagnosticPlots"));
before=fileread(lineagePath);
assert(isempty(sixgr.report.exportTrialDiagnosticPlots(root,struct(),false)) && ...
    strcmp(before,fileread(lineagePath)),'Disabled plotting must not rewrite artifacts.');
% Empty recovery must not bless an existing image as new evidence.
assert(isempty(sixgr.report.exportTrialDiagnosticPlots(root,struct(),true)) && ...
    ~isfile(lineagePath) && ~any(cellfun(@isfile,images)));
fprintf('TRIAL_PLOT_SOURCE_NUMERICAL_FIXTURE=%s\n',root);
ok=true;
end
