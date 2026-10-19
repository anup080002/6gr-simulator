function ok = testBrowserContractCSVPublicationOwnership()
% Browser chart datasets and their hashes belong to the plotting producer.
setup6GRSimToolkit('Verbose',false);
root = string(tempname);
mkdir(fullfile(root,'reports','csv'));
mkdir(fullfile(root,'reports','image'));
cleanup = onCleanup(@() rmdir(root,'s')); %#ok<NASGU>
mkdir(fullfile(root,'analytics','csv'));
mkdir(fullfile(root,'analytics','image'));
stem="contract__error-reliability-analytics__bler-vs-snr";
source = fullfile(root,'analytics','csv',stem+'.csv');
png = fullfile(root,'analytics','image',stem+'.png');
lineage = fullfile(root,'reports','csv','contract_plot_lineage.csv');
% The browser producer declares z fields even for a two-dimensional chart.
% They are absent measurements, not columns for a later sanitizer to drop.
T = table([1;2],[20;30],[0.125;0],strings(2,1),nan(2,1), ...
    repmat("exact",2,1),'VariableNames', ...
    {'point_index','x_value','y_value','z_label','z_value','source_mapping_status'});
sixgr.util.csvWriteTable(source,T,'PreserveSchema',true,'RoundTripNumericText',true);
imwrite(uint8(repmat((0:31),32,1)),png);
sixgr.visual.writeComponentPlotLineage(root,lineage, ...
    "contract__test__measured-curve",png,source,"numerical_publication_fixture", ...
    'SourcesAlreadyFinalized',true);
originalSource = sixgr.phy.waveform.WaveformHash.file(source);
originalLineage = sixgr.phy.waveform.WaveformHash.file(lineage);
originalImage = sixgr.phy.waveform.WaveformHash.file(png);
% The live producer also owns content-addressed CSV/PNG snapshots, including
% retained source operands. Final annotation must not rewrite these bytes or
% bless different source hashes into their already sealed lineage.
liveRoot=fullfile(root,'reports','live_measurements',repmat('a',1,64));
mkdir(fullfile(liveRoot,'csv')); mkdir(fullfile(liveRoot,'image'));
mkdir(fullfile(liveRoot,'sources','air_interface','csv'));
liveCSV=fullfile(liveRoot,'csv','measured.csv');
liveSource=fullfile(liveRoot,'sources','air_interface','csv','paired.csv');
livePNG=fullfile(liveRoot,'image','measured.png');
liveLineage=fullfile(liveRoot,'checkpoint_plot_lineage.csv');
sixgr.util.csvWriteTable(liveCSV,T,'PreserveSchema',true,'RoundTripNumericText',true);
copyfile(liveCSV,liveSource); copyfile(png,livePNG);
sixgr.visual.writeComponentPlotLineage(liveRoot,liveLineage, ...
    'live_fixture',char(livePNG),char(liveCSV),'live_publication_fixture','SourcesAlreadyFinalized',true);
charLineageHash=sixgr.phy.waveform.WaveformHash.file(liveLineage);
sixgr.visual.writeComponentPlotLineage(liveRoot,liveLineage, ...
    "live_fixture",string(livePNG),string(liveCSV),"live_publication_fixture",'SourcesAlreadyFinalized',true);
assert(sixgr.phy.waveform.WaveformHash.file(liveLineage)==charLineageHash, ...
    'Char and string scalar input must describe the same plot and byte-exact lineage.');
livePaths=[liveCSV;liveSource;livePNG;liveLineage];
liveHashes=arrayfun(@sixgr.phy.waveform.WaveformHash.file,livePaths);
for pass = 1:2
    sixgr.truth.sanitizeLLSArtifactCSVs(root);
    sixgr.truth.sanitizeLLSArtifactCSVs(root,'OnlyPaths',[source;lineage]);
    sixgr.truth.sanitizeLLSArtifactCSVs(root,'OnlyPaths',[liveCSV;liveSource;liveLineage]);
    assert(isequal(arrayfun(@sixgr.phy.waveform.WaveformHash.file,livePaths),liveHashes), ...
        'sixgr:test:LiveSnapshotSanitizerMutation','Live snapshot bytes are immutable.');
    assert(sixgr.phy.waveform.WaveformHash.file(source)==originalSource, ...
        'sixgr:test:BrowserChartSourceMutated', ...
        'Finalization changed the exact dataset already used to render the browser chart.');
    assert(sixgr.phy.waveform.WaveformHash.file(lineage)==originalLineage, ...
        'sixgr:test:BrowserChartLineageMutated', ...
        'A generic sanitizer must not rewrite browser-owned plot lineage.');
    sixgr.report.annotateScenarioCSVArtifacts(root,'scenario','config','waveform_bundle');
    assert(isequal(arrayfun(@sixgr.phy.waveform.WaveformHash.file,livePaths),liveHashes), ...
        'sixgr:test:LiveSnapshotAnnotationMutation', ...
        'Final annotation must not invalidate live input, plotted-CSV or lineage hashes.');
    assert(sixgr.phy.waveform.WaveformHash.file(source)==originalSource && ...
        sixgr.phy.waveform.WaveformHash.file(lineage)==originalLineage, ...
        'sixgr:test:BrowserChartAnnotationMutation', ...
        'Scenario annotation must not rewrite a sealed browser dataset or its manifest.');
end
assert(sixgr.phy.waveform.WaveformHash.file(png)==originalImage);
sixgr.analytics.generateMeasuredSINRCurves(root,'chart_owner_guard', ...
    'TrialData',struct('dl',table(),'ul',table()), ...
    'UpdateAnchorKPIs',false);
assert(sixgr.phy.waveform.WaveformHash.file(source)==originalSource && ...
    sixgr.phy.waveform.WaveformHash.file(png)==originalImage, ...
    'sixgr:test:MeasuredAnalyticsMutatedBrowserChart', ...
    'Measured-SINR analytics must not rename axes or rewrite a browser-owned dataset.');
assert(~isfile(fullfile(root,'analytics','image', ...
    'contract__error-reliability-analytics__bler-vs-measured-sinr.png')), ...
    'sixgr:test:RelabelledRasterAlias', ...
    'Copying an SNR image is not production of a measured-SINR plot.');
% This protection is not a hash-repair shortcut: corrupted measurements
% remain rejected against the original manifest.
T.y_value(1)=0.25;
sixgr.util.csvWriteTable(source,T,'PreserveSchema',true,'RoundTripNumericText',true);
sixgr.truth.sanitizeLLSArtifactCSVs(root);
sixgr.report.annotateScenarioCSVArtifacts(root,'scenario','config','waveform_bundle');
assert(sixgr.phy.waveform.WaveformHash.file(lineage)==originalLineage);
audit=sixgr.visual.verifyVisualArtifacts(root,table());
row=string(audit.PlotId)=="contract__test__measured-curve";
assert(nnz(row)==1 && ~audit.IntegrityOk(row) && ...
    contains(string(audit.FailureCode(row)),"component_plot_source_hash_mismatch"), ...
    'Unrelated source changes must remain a scientific integrity failure.');
ok=true;
end
