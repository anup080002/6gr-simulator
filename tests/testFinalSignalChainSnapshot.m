function ok=testFinalSignalChainSnapshot()
% Declared publication fixture, not PHY samples or performance evidence.
% Final snapshots preserve every point; normal live polling remains bounded.
folder=tempname(fullfile(pwd,'logs'));
count=5000;
wave=table((1:count).',repelem([40;30;20;10;0;-10;-20;-30],625), ...
    repmat("declared_publication_unit_fixture",count,1), ...
    'VariableNames',{'SampleIndex','SNR_dB','Source'});
live=sixgr.truth.exportLLSLiveSignalChainTables(fullfile(folder,'live'), ...
    table(),table(),struct('WaveformPreviewTable',wave));
assert(height(live.WaveformPreview)==4096 && live.WaveformPreview.SampleIndex(1)==905);
final=sixgr.truth.exportLLSLiveSignalChainTables(fullfile(folder,'final'), ...
    table(),table(),struct('WaveformPreviewTable',wave,'FinalSnapshot',true));
saved=sixgr.util.csvReadTable(final.WaveformPreviewPath,'TextType','string');
assert(isequaln(final.WaveformPreview,wave) && isequaln(saved,wave), ...
    'test:FinalPreviewTruncated','Final publication must retain all eight points exactly.');
assert(isempty(final.ModulationTrace) && isempty(final.ChannelEstimationTrace), ...
    'No primary PHY trial evidence may be manufactured from a preview.');
fprintf('FINAL_SIGNAL_SNAPSHOT_PASS final_rows=%d live_rows=4096 folder=%s\n',count,folder);
ok=true;
end
