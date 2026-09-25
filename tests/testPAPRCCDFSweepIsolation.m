function ok=testPAPRCCDFSweepIsolation()
% Constructed population/plot regression; no waveform qualification claim.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
T=table([-10;-10;-10;20;20;20;20],[1;2;2;8;9;9;NaN], ...
    repmat("QPSK",7,1),ones(7,1), ...
    'VariableNames',{'ConfiguredSNR_dB','PAPR_dB','Modulation','Layers'});
out=sixgr.report.buildPAPRCCDFTable(struct('DL',T,'UL',table()));
a=out(out.ConfiguredSNR_dB==-10,:); b=out(out.ConfiguredSNR_dB==20,:);
assert(isequal(a.PAPR_dB,[1;2]) && isequal(a.Exceedances,[2;0]) && ...
    all(a.SampleCount==3) && isequal(a.CCDF,[2/3;0]));
assert(isequal(b.PAPR_dB,[8;9]) && isequal(b.Exceedances,[2;0]) && ...
    all(b.SampleCount==3) && all(b.UnavailableSampleCount==1));
assert(all(a.ThresholdComparator==">") && numel(unique(out.PopulationID))==2);
children=[sixgr.report.buildPAPRCCDFTable(struct('DL',T(T.ConfiguredSNR_dB==-10,:))); ...
    sixgr.report.buildPAPRCCDFTable(struct('DL',T(T.ConfiguredSNR_dB==20,:)))];
assert(numel(unique(children.PopulationID))==2 && isequal(children.PopulationID,out.PopulationID), ...
    'Independently exported sweep children must not reuse ordinal population IDs.');
T.Layers(2)=2;
separate=sixgr.report.buildPAPRCCDFTable(struct('DL',T));
assert(numel(unique(separate.PopulationID))==3,'Adaptive ranks must not be silently pooled.');
T.MCS=zeros(height(T),1); T.MCS(3)=1;
separateMCS=sixgr.report.buildPAPRCCDFTable(struct('DL',T));
assert(numel(unique(separateMCS.PopulationID))==4,'Runtime MCS alias must retain adaptive populations.');
assert(isempty(sixgr.report.buildPAPRCCDFTable(struct('DL',T([],:)))));
context=struct('ContractVersion','tx_papr/v1','Source','actual_supplied_transmitter_waveform', ...
    'MeasurementPoint','pre_rf','ReferenceDomain','CP_excluded', ...
    'InputWaveformSampleCount',128,'AggregateRule','maximum_finite_per_port_PAPR', ...
    'PerPort',struct('PortIndex',1,'OversamplingFactor',1,'MeasuredSampleCount',120, ...
    'InputSampleCount',120,'OversamplingDefinition','additional_periodic_fft_interpolation_of_input_block'));
windows=T([1 1 1],:); windows.PAPRMeasurementJSON=repmat(string(jsonencode(context)),3,1);
context.MeasurementPoint='post_rf'; windows.PAPRMeasurementJSON(2)=string(jsonencode(context));
context.ReferenceDomain='CP_included'; windows.PAPRMeasurementJSON(3)=string(jsonencode(context));
windowPopulations=sixgr.report.buildPAPRCCDFTable(struct('DL',windows));
assert(numel(unique(windowPopulations.PopulationID))==3, ...
    'PAPR windows and measurement planes must never be pooled.');
windows.PAPRMeasurementJSON(1)="{}";
try
    sixgr.report.buildPAPRCCDFTable(struct('DL',windows));
    error('test:ExpectedPAPRContextRejection','Incomplete measurement context was accepted.');
catch err
    assert(strcmp(err.identifier,'sixgr:report:PAPRMeasurementContext'));
end
fig=figure('Visible','off'); cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
ax=axes(fig); h=sixgr.report.plotPAPRCCDF(ax,children);
assert(numel(h)==2 && string(ax.YScale)=="linear");
assert(isequal(h(1).XData(:),a.PAPR_dB) && isequal(h(1).YData(:),a.CCDF));
assert(isequal(h(2).XData(:),b.PAPR_dB) && isequal(h(2).YData(:),b.CCDF));
bad=T; bad.Direction=repmat("UL",height(T),1);
try
    sixgr.report.buildPAPRCCDFTable(struct('DL',bad));
    error('test:ExpectedPAPRDirectionRejection','Contradictory direction was accepted.');
catch err
    assert(strcmp(err.identifier,'sixgr:report:PAPRDirectionMismatch'));
end
fprintf('PAPR_CCDF_SWEEP_ISOLATION_PASS points=2 ties_correct=1 plotted_csv_equal=1 zero_retained=1\n');
ok=true;
end
