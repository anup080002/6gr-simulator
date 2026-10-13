function ok=testConstellationPlotGroups()
% Numerical/report fixture only; these samples are not waveform evidence.
points=[40 30 20 10 0 -10 -20 -30];
T=table();
for direction=["DL","UL"]
    for snr=points
        n=3;
        r=table(repmat(direction,n,1),repmat("QPSK",n,1),ones(n,1), ...
            repmat(snr,n,1),ones(n,1),repmat(snr,n,1), ...
            [1;2;3],zeros(n,1),[1;2;4],zeros(n,1), ...
            repmat("runtime_measured",n,1), ...
            'VariableNames',{'direction','modulation','layer','snr_db', ...
            'mcs_index','posteq_sinr_db','reference_symbol_i','reference_symbol_q', ...
            'equalized_i','equalized_q','truth_status'});
        T=[T;r]; %#ok<AGROW>
    end
end
% Same modulation with a different MCS must not inherit the first label.
other=T(1:3,:); other.mcs_index(:)=2; T=[T;other];
[groups,s]=sixgr.report.groupConstellationPlotSamples(T);
assert(numel(groups)==17 && sum(s.CapturedSampleCount)==height(T));
assert(isequal(s.ConfiguredSNR_dB(1:8).',points));
assert(all(abs(s.CaptureEVM_pct-100/sqrt(14))<1e-12));
assert(all(abs(s.CaptureEVM_dB-10*log10(1/14))<1e-12));
% Independent SINR estimator availability must not erase valid captures.
noSINR=T; noSINR.posteq_sinr_db(:)=NaN;
[withoutSINR,sNoSINR]=sixgr.report.groupConstellationPlotSamples(noSINR);
assert(numel(withoutSINR)==17 && isequaln(s,sNoSINR));
noSINR.posteq_sinr_db=[];
[~,sNoColumn]=sixgr.report.groupConstellationPlotSamples(noSINR);
assert(isequaln(s,sNoColumn));
% All captured rows remain plotted even when one group exceeds 2,000.
many=repmat(T(1:3,:),1001,1);
[g,counts]=sixgr.report.groupConstellationPlotSamples(many);
assert(numel(g)==1 && height(g{1})==3003 && counts.CapturedSampleCount==3003);
% No synthetic/proxy rows or missing measurements enter a primary plot.
bad=T(1,:); bad.truth_status="synthetic";
missing=T(1,:); missing.equalized_i=NaN;
[~,after]=sixgr.report.groupConstellationPlotSamples([T;bad;missing]);
assert(isequaln(s,after));
zero=T(1,:); zero.equalized_i=zero.reference_symbol_i;
[~,exact]=sixgr.report.groupConstellationPlotSamples(zero);
assert(exact.CaptureEVM_pct==0 && exact.CaptureEVM_dB==-Inf);
% Both production publication paths must use this same all-group renderer.
waveformSource=fileread(which('sixgr.truth.runWaveformLinkBundle'));
reportSource=fileread(which('sixgr.truth.exportLLSReportingBundle'));
trialSource=fileread(which('sixgr.report.exportTrialDiagnosticPlots'));
recoverySource=fileread(which('sixgr.truth.refinalizePersistedLLSRuntimeEvidence'));
assert(contains(waveformSource,'sixgr.report.exportTrialDiagnosticPlots') && ...
    contains(recoverySource,'sixgr.report.exportTrialDiagnosticPlots') && ...
    contains(trialSource,'sixgr.report.exportConstellationGroups') && ...
    contains(reportSource,'sixgr.report.exportConstellationGroups'));
assert(~contains(waveformSource,'localSelectConstellationPlotSlice') && ...
    ~contains(waveformSource,'localIdealConstellationPoints'), ...
    'The discarded largest-slice/guessed-alphabet renderer must not remain active.');
root=fullfile(pwd,'results','lls','constellation_plot_groups', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(root);
path=fullfile(root,'numerical_report_fixture.png');
[rendered,plotted]=sixgr.report.exportConstellationGroups(T,path);
assert(rendered && isequaln(s,plotted) && isfile(path));
info=imfinfo(path);
assert(info.Width>1200 && info.Height>2400, ...
    'All 17 groups need readable independent panels, not a four-panel crop.');
fprintf('NUMERICAL_CONSTELLATION_REPORT_FIXTURE=%s groups=%d samples=%d\n', ...
    path,height(plotted),sum(plotted.CapturedSampleCount));
ok=true;
end
