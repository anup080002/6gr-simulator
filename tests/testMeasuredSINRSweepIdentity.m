function ok=testMeasuredSINRSweepIdentity()
% Declared export/plot fixtures, not an eight-point physical campaign.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
root=tempname; mkdir(root);
cleanup=onCleanup(@()rmdir(root,'s')); %#ok<NASGU>
points=[-30 -20 -10 0 10 20 30 40].';
base=table(repmat(35,8,1),(1:8).',points,ones(8,1),ones(8,1), ...
    ones(8,1),ones(8,1),repmat(4,8,1),repmat("QPSK",8,1),points+1, ...
    repmat("receiver_post_equalization_data",8,1), ...
    repmat("measured_post_equalization_scheduling_input",8,1),repmat("OK",8,1), ...
    'VariableNames',{'Slot','SweepPointIndex','ConfiguredSNR_dB','UEID','CellID', ...
    'Rank','Layers','MCS','Modulation','PostEqSINR_dB','PostEqSINRSource', ...
    'PostEqSINRValueRole','PostEqSINRValueStatus'});
for direction=["dl" "ul"]
    if direction=="dl", channel="pdsch"; else, channel="pusch"; end
    sixgr.util.csvWriteTable(fullfile(root,'air_interface','csv',direction+"_"+channel+"_trials.csv"),base);
end
sixgr.analytics.buildPhase7ReadinessArtifacts(struct('frame_timing',struct('slot_duration_ms',1)),root);
actual=readtable(fullfile(root,'reports','csv','measured_sinr_timeseries.csv'),'TextType','string');
assert(height(actual)==16);
for direction=["DL" "UL"]
    selected=actual(actual.Direction==direction,:);
    assert(isequal(selected.SweepPointIndex,(1:8).') && isequal(selected.ConfiguredSNR_dB,points));
    assert(all(selected.CanonicalSlot==35) && all(abs(selected.Time_s-.034)<1e-12));
    assert(isequal(selected.MeasuredSINR_dB,points+1));
    assert(all(selected.ConfiguredSNRValueRole=="configured_operating_point_metadata"));
end
% Repeated slot clocks and two different UEs must create independent series.
other=actual; other.UeId(:)=2;
combined=[actual;other];
groups=sixgr.visual.groupReceiverTimeSeries(combined);
assert(numel(groups)==32 && all(arrayfun(@(g)numel(g.Rows)==1,groups)));
assert(isequal(sort(vertcat(groups.Rows)),(1:32).'));
% Legacy one-point tables without sweep columns remain usable; absent
% identity is not replaced by an invented point or configured SNR value.
legacy=removevars(actual(1:2,:),{'SweepPointIndex','ConfiguredSNR_dB'});
assert(numel(sixgr.visual.groupReceiverTimeSeries(legacy))==2);
plots=sixgr.visual.plotGeometryScenarioEvidence(root);
assert(any(endsWith(plots.GeneratedPlots,'measured_sinr_vs_slot.png')));
assert(any(endsWith(plots.GeneratedPlots,'mcs_rank_vs_slot.png')));
fprintf('MEASURED_SINR_SWEEP_IDENTITY_PASS rows=16 independent_receiver_series=32 plots=2\n');
ok=true;
end
