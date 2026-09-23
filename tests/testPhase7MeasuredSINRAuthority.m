function ok=testPhase7MeasuredSINRAuthority()
% Declared export fixtures only: do not treat these values as PHY evidence.
setup6GRSimToolkit('Verbose',false);
root=tempname; mkdir(root);
cleanup=onCleanup(@()rmdir(root,'s')); %#ok<NASGU>
cfg=struct('frame_timing',struct('slot_duration_ms',1));
base=struct('Slot',1,'UEID',1,'CellID',1,'MCS',20,'Modulation',"64QAM", ...
    'CQIDerivedMCS',28,'CQIDerivedModulation',"256QAM", ...
    'Rank',1,'EffectiveRank',1,'RankEstimate',4,'Layers',1,'Status',"PASS", ...
    'PostEqSINR_dB',21,'PostEqSINRSource',"measured_post_equalization_data", ...
    'PostEqSINRValueRole',"measured_post_equalization_scheduling_input", ...
    'PostEqSINRValueStatus',"OK_decision_residual_bounded", ...
    'MeasuredTrialSINR_dB',8,'MeasuredTrialSINRSource',"measured_post_equalization_legacy", ...
    'MeasuredTrialSINRValueRole',"measured_post_equalization_scheduling_input", ...
    'MeasuredTrialSINRValueStatus',"OK", ...
    'ReceiverHestSINR_dB',50,'LargeScaleSINR_dB',60);
rows=repmat(base,6,1);
for k=1:6, rows(k).Slot=k; end
rows(2).PostEqSINR_dB=NaN; rows(2).MeasuredTrialSINR_dB=22;
rows(2).Rank=2; rows(2).EffectiveRank=2; rows(2).Layers=2;
rows(3).PostEqSINR_dB=NaN; rows(3).MeasuredTrialSINR_dB=NaN;
rows(4).PostEqSINRSource="configured_sweep_proxy";
rows(4).MeasuredTrialSINRSource="configured_sweep_proxy";
rows(5).PostEqSINR_dB=25;
rows(5).Rank=NaN; rows(5).EffectiveRank=NaN; rows(5).Layers=NaN;
rows(5).MCS=NaN; rows(5).Modulation="";
rows(6).PostEqSINRValueStatus="FAILED"; rows(6).MeasuredTrialSINR_dB=NaN;
for direction=["dl" "ul"]
    T=struct2table(rows);
    sixgr.util.csvWriteTable(fullfile(root,'air_interface','csv',direction+"_"+ ...
        localDataChannel(direction)+"_trials.csv"),T);
end
sixgr.analytics.buildPhase7ReadinessArtifacts(cfg,root);
T=readtable(fullfile(root,'reports','csv','measured_sinr_timeseries.csv'), ...
    'TextType','string','VariableNamingRule','preserve');
assert(height(T)==6,'Pilot, link-budget, proxy and failed rows must not become measured data SINR.');
for direction=["DL" "UL"]
    selected=T(T.Direction==direction,:);
    assert(isequal(selected.CanonicalSlot,[1;2;5]));
    assert(isequal(selected.MeasuredSINR_dB,[21;22;25]));
    assert(isequaln(selected.Rank,[1;2;NaN]) && isequaln(selected.Layers,[1;2;NaN]), ...
        'Executed rank must not be replaced by a channel rank estimate.');
    assert(isequal(selected.Time_s,[0;.001;.004]));
    assert(isequaln(selected.MCS,[20;20;NaN]) && ...
        all(selected.Modulation(1:2)=="64QAM") && ...
        (ismissing(selected.Modulation(3)) || strlength(selected.Modulation(3))==0), ...
        'A CQI recommendation must not replace an unknown transmitted MCS/modulation.');
    assert(selected.SINRSource(1)==base.PostEqSINRSource && ...
        selected.SINRSource(2)==base.MeasuredTrialSINRSource);
    assert(selected.SINRValueStatus(1)==base.PostEqSINRValueStatus && ...
        all(selected.SINRValueRole==base.PostEqSINRValueRole));
end
fprintf('PHASE7_MEASURED_SINR_AUTHORITY_PASS input_rows=12 published_rows=6 executed_rank_and_exact_data_plane=1\n');
ok=true;
end

function channel=localDataChannel(direction)
if direction=="dl", channel="pdsch"; else, channel="pusch"; end
end
