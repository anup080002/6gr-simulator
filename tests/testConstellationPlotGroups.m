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
% Measured values remain identical; newly explicit rejection counters change.
measurementNames=s.Properties.VariableNames(1:10);
assert(isequaln(s(:,measurementNames),after(:,measurementNames)));
assert(isequal(s.GroupIdentity,after.GroupIdentity));
assert(sum(after.RejectedSampleCount)==2 && sum(after.ExcludedAuthorityRowCount)==1 && ...
    sum(after.InvalidReceiverPairCount)==1 && after.PopulationStatus(1)=="partial_source_population_plotted");
zero=T(1,:); zero.equalized_i=zero.reference_symbol_i;
[~,exact]=sixgr.report.groupConstellationPlotSamples(zero);
assert(exact.CaptureEVM_pct==0 && exact.CaptureEVM_dB==-Inf);
localCohortAndPlaneChecks(T(1:3,:));
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
[rendered,plotted,~,layout]=sixgr.report.exportConstellationGroups(T,path);
assert(rendered && isequaln(s,plotted) && isfile(path));
localAssertTitleSeparation(layout,height(plotted));
info=imfinfo(path);
assert(info.Width>1200 && info.Height>2400, ...
    'All 17 groups need readable independent panels, not a four-panel crop.');
% Actual persisted producer-schema roundtrip, still declared numeric fixtures.
native=T(1:3,:);
native.RawEqualizedReal=native.reference_symbol_i; native.RawEqualizedImag=native.reference_symbol_q;
native.SymbolCoordinateDomain=repmat("pre_transform_qam_positions",3,1);
native.SymbolOrderLinearIndexDomain=repmat("native_pre_transform_allocation_position_key",3,1);
native.SymbolOrderLinearIndex=[7;8;9]; native.SubcarrierIndex=nan(3,1);
native.OFDMSymbolIndex=[2;2;2]; native.CaptureScope=repmat("full_allocation_paired_symbols",3,1);
native.SweepAggregateLabel=repmat("declared_point",3,1);
native.SweepAggregatePointStatus=repmat("passed",3,1);
native.TransmissionAttemptID=["attempt-a";"attempt-b";"attempt-c"];
csvPath=fullfile(root,'declared_dft_receiver_source.csv');
sixgr.util.csvWriteTable(csvPath,native,'PreserveSchema',true,'RoundTripNumericText',true);
readback=sixgr.util.csvReadTable(csvPath,'TextType','string');
[readGroups,readSummary]=sixgr.report.groupConstellationPlotSamples(readback);
assert(numel(readGroups)==1 && height(readGroups{1})==3 && readSummary.CaptureEVM_pct==0);
assert(isequaln(readGroups{1}.SubcarrierIndex,native.SubcarrierIndex));
assert(isequal(readGroups{1}.SymbolOrderLinearIndex,native.SymbolOrderLinearIndex));
assert(isequal(string(readGroups{1}.TransmissionAttemptID),native.TransmissionAttemptID));
assert(contains(readSummary.GroupLabel,"SweepAggregateLabel=declared_point") && ...
    contains(readSummary.GroupLabel,"SweepAggregatePointStatus=passed"));
nativeImage=fullfile(root,'declared_dft_raw_plane.png');
[rawRendered,rawPlotted,~,rawLayout]=sixgr.report.exportConstellationGroups(readback,nativeImage);
assert(rawRendered && rawPlotted.CaptureEVM_pct==0 && ...
    rawPlotted.PlottedRealColumn=="RawEqualizedReal" && isfile(nativeImage));
localAssertTitleSeparation(rawLayout,height(rawPlotted));
invalidRaw=readback; invalidRaw.RawEqualizedReal(:)=NaN;
unavailablePath=fullfile(root,'invalid_raw_must_not_be_fitted.png');
[renderedInvalid,summaryInvalid,diagnosticsInvalid]=sixgr.report.exportConstellationGroups(invalidRaw,unavailablePath);
assert(~renderedInvalid && isempty(summaryInvalid) && ~isfile(unavailablePath) && ...
    diagnosticsInvalid.InvalidReceiverPairCount==3 && diagnosticsInvalid.PlottedSampleCount==0);
rendererSource=fileread(which('sixgr.report.exportConstellationGroups'));
assert(contains(rendererSource,'Plotted-pair EVM') && ...
    contains(rendererSource,'Legacy canonical equalized (not verified raw)') && ...
    contains(rendererSource,'Capture scope: ') && contains(rendererSource,'coordinate domain: '));
fprintf('NUMERICAL_CONSTELLATION_REPORT_FIXTURE=%s groups=%d samples=%d\n', ...
    path,height(plotted),sum(plotted.CapturedSampleCount));
ok=true;
end

function localAssertTitleSeparation(layout,count)
% Inspect actual renderer text extents, not only raster dimensions. All
% complete labels must remain present without overlapping adjacent panels.
assert(height(layout)==count && all(layout.TitleRightPixels>layout.TitleLeftPixels) && ...
    all(layout.TitleTopPixels>layout.TitleBottomPixels));
for row=unique(layout.PanelRow).'
    panels=sortrows(layout(layout.PanelRow==row,:),'TitleLeftPixels');
    assert(all(panels.TitleRightPixels(1:end-1)<panels.TitleLeftPixels(2:end)), ...
        'test:ConstellationTitleOverlap','Adjacent cohort labels must not overlap.');
end
for row=2:max(layout.PanelRow)
    above=layout(layout.PanelRow==row-1,:); below=layout(layout.PanelRow==row,:);
    assert(max(below.TitleTopPixels)<min(above.TitleBottomPixels), ...
        'test:ConstellationTitleOverlap','Titles in consecutive panel rows must not overlap.');
end
end

function localCohortAndPlaneChecks(base)
% Retained raw and fitted/canonical clouds deliberately differ numerically.
raw=base; raw.RawEqualizedReal=base.reference_symbol_i;
raw.RawEqualizedImag=base.reference_symbol_q;
[g,s]=sixgr.report.groupConstellationPlotSamples(raw);
assert(s.CaptureEVM_pct==0 && s.ErrorEnergy==0 && ...
    s.PlottedIQSource=="retained_raw_equalized_receiver_symbols_no_fitted_substitution");
assert(isequaln(g{1},raw),'Native columns, including the differing canonical cloud, must remain unchanged.');
[~,legacy]=sixgr.report.groupConstellationPlotSamples(base);
assert(legacy.CaptureEVM_pct>0 && ...
    legacy.PlottedIQSource=="legacy_canonical_equalized_symbols_source_declared_plane_not_verified_raw");
raw.RawEqualizedReal(2)=NaN;
[g,s,d]=sixgr.report.groupConstellationPlotSamples(raw);
assert(height(g{1})==2 && s.SourceRowCount==3 && s.RejectedSampleCount==1 && ...
    s.InvalidReceiverPairCount==1 && s.CaptureEVM_pct==0 && ...
    s.PopulationStatus=="partial_source_population_plotted" && ...
    contains(d.RejectionReason,"no_fitted_substitution"));
raw.RawEqualizedReal(:)=NaN;
[g,s,d]=sixgr.report.groupConstellationPlotSamples(raw);
assert(isempty(g) && isempty(s) && d.InvalidReceiverPairCount==3 && ...
    d.PopulationStatus=="unavailable_no_finite_authorized_pairs");
raw.RawEqualizedImag=[];
[g,s,d]=sixgr.report.groupConstellationPlotSamples(raw);
assert(isempty(g) && isempty(s) && d.RejectionReason=="missing_raw_receiver_component_no_fitted_substitution");
% Unknown metadata is not a reason to discard finite measured pairs.
unknown=base; unknown.layer(:)=NaN; unknown.snr_db(:)=NaN; unknown.mcs_index(:)=NaN;
[g,s]=sixgr.report.groupConstellationPlotSamples(unknown);
assert(numel(g)==1 && height(g{1})==3 && isnan(s.Layer) && isnan(s.ConfiguredSNR_dB));
assert(s.CaptureScope=="not_retained" && s.SymbolCoordinateDomain=="not_retained");
% Exactly adjacent doubles, integers beyond flintmax, and delimiter-bearing
% strings cannot collapse under display formatting or delimiter concatenation.
adjacent=repmat(base(1,:),2,1); adjacent.snr_db=[1;1+eps(1)];
[g,s]=sixgr.report.groupConstellationPlotSamples(adjacent);
assert(numel(g)==2 && numel(unique(s.GroupIdentity))==2);
wide=repmat(base(1,:),2,1);
wide.Seed=bitshift(uint64(1),53)+uint64([0;1]);
[g,s]=sixgr.report.groupConstellationPlotSamples(wide);
assert(numel(g)==2 && isa(s.Cohort_Seed,'uint64') && isequal(s.Cohort_Seed,wide.Seed));
collision=repmat(base(1,:),2,1);
collision.ue_id=["a|normalization=b";"a"]; collision.normalization=["c";"b|normalization=c"];
[g,s]=sixgr.report.groupConstellationPlotSamples(collision);
assert(numel(g)==2 && numel(unique(s.GroupIdentity))==2);
% Independently vary actual producer population/domain/scope columns.
fields=["SourceRunID","RunID","RunUUID","ExecutionID","ConfigHash","Seed", ...
    "RandomSeed","ChannelSeed","ServingCell","SweepPointIndex", ...
    "SweepAggregatePointIndex","SweepAggregateLabel","SweepAggregateConfiguredSNR_dB", ...
    "SweepAggregateSourceCSV","SweepAggregatePointStatus","EqualizationSource", ...
    "SymbolCoordinateDomain","SymbolOrderLinearIndexDomain","CaptureScope","CodewordIndex"];
numeric=["Seed","RandomSeed","ChannelSeed","ServingCell","SweepPointIndex", ...
    "SweepAggregatePointIndex","SweepAggregateConfiguredSNR_dB","CodewordIndex"];
for field=fields
    changed=repmat(base(1,:),2,1);
    if ismember(field,numeric), changed.(field)=[1;2];
    else, changed.(field)=["declared-a";"declared-b"]; end
    [g,s]=sixgr.report.groupConstellationPlotSamples(changed);
    assert(numel(g)==2 && sum(s.CapturedSampleCount)==2 && ...
        isequal(s.("Cohort_"+field),changed.(field)));
end
% Coordinate positions and attempts are retained, not one-panel-per-symbol.
positions=base; positions.SymbolOrderLinearIndex=[1;2;3];
positions.OFDMSymbolIndex=[1;2;3]; positions.SubcarrierIndex=nan(3,1);
positions.TransmissionAttemptID=["a";"b";"c"]; positions.Slot=[1;2;3];
positions.SymbolCoordinateDomain=repmat("pre_transform_qam_positions",3,1);
positions.SymbolOrderLinearIndexDomain=repmat("native_pre_transform_allocation_position_key",3,1);
[g,s]=sixgr.report.groupConstellationPlotSamples(positions);
assert(numel(g)==1 && isequaln(g{1},positions) && s.CapturedSampleCount==3);
% Invalid metadata shape cannot be coerced to a first-column population.
invalid=base; invalid.Seed=ones(3,2);
try
    sixgr.report.groupConstellationPlotSamples(invalid);
    error('test:ExpectedRejection','Expected nonscalar cohort rejection.');
catch exception
    assert(strcmp(exception.identifier,'sixgr:report:ConstellationCohortShape'));
end
end
