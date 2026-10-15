function ok = testLLSCoverageSINRProvenance()
% Declared table fixtures: verify production publication, not PHY accuracy.
root = tempname; mkdir(root);
cfg = sixgr.config.defaultConfig();
source = "canonical_decision_directed_post_equalization_residual_bounded_equalizer_sinr";
role = "measured_post_equalization_scheduling_input";
base = struct('UEID',1,'Slot',1,'Time_s',0,'Lat',0,'Lon',0, ...
    'ServingCell',1,'ServingSite',1,'ServingSector',1, ...
    'PostEqSINR_dB',23.4,'PostEqWidebandSINR_dB',23.4, ...
    'MeasuredTrialSINR_dB',23.4,'MeasuredWidebandSINR_dB',23.4, ...
    'EstimatedWidebandSINR_dB',23.4,'ReceiverHestSINR_dB',27.6, ...
    'PostEqSINRSource',source,'PostEqSINRValueRole',role, ...
    'PostEqSINRValueStatus',"OK_decision_residual_bounded", ...
    'PostEqSINRValueDefinition',"fixture_same_receiver_residual_bound", ...
    'PostEqSINRMeasurementDomain',"data_re_post_equalization", ...
    'WidebandSINRSource',"",'WidebandSINRValueRole',"",'WidebandSINRValueStatus',"");
rows = repmat(base,5,1);
for k=1:5, rows(k).Slot=k; rows(k).UEID=k; end
rows(2).WidebandSINRSource=source;
rows(2).WidebandSINRValueRole=role;
rows(2).WidebandSINRValueStatus="FAILED_reference_population";
rows(3).PostEqSINRSource="";
rows(3).PostEqSINRValueRole="";
rows(3).PostEqSINRValueStatus="";
rows(4).PostEqSINRValueStatus="FAILED_receiver_measurement";
rows(5).EstimatedWidebandSINR_dB=10;
rows(5).WidebandSINRSource="fixture_received_CSI_objective";
rows(5).WidebandSINRValueRole="fixture_CSI_objective";
rows(5).WidebandSINRValueStatus="OK_objective";
for mode=["CoverageLayerTable","CoverageSnapshotTable"]
    st=struct(); st.(mode)=struct2table(rows);
    out=sixgr.truth.exportLLSLiveDerivedTables(cfg,fullfile(root,mode), ...
        struct(),struct(),struct(),st);
    T=sixgr.util.csvReadTable(out.CoverageLayerPath,'TextType','string');
    assert(height(T)==5 && isequal(T.PostEqSINR_dB,repmat(23.4,5,1)));
    assert(T.WidebandSINRSource(1)==source && T.WidebandSINRValueRole(1)==role);
    assert(T.WidebandSINRValueStatus(1)=="OK_decision_residual_bounded");
    assert(T.WidebandSINRValueDefinition(1)==base.PostEqSINRValueDefinition);
    assert(T.WidebandSINRMeasurementDomain(1)==base.PostEqSINRMeasurementDomain);
    assert(T.WidebandSINRValueStatus(2)=="FAILED_reference_population");
    assert(ismissing(T.WidebandSINRSource(3)) || strlength(T.WidebandSINRSource(3))==0);
    assert(contains(T.WidebandSINRValueStatus(3),"unavailable"));
    assert(T.WidebandSINRValueStatus(4)=="FAILED_receiver_measurement");
    assert(T.WidebandSINRSource(5)==rows(5).WidebandSINRSource && ...
        T.WidebandSINRValueStatus(5)=="OK_objective");
    assert(ismissing(T.WidebandSINRMeasurementDomain(5)) || ...
        strlength(T.WidebandSINRMeasurementDomain(5))==0, ...
        'Do not attach a different numeric plane''s domain to a CSI objective.');
end

% Actual public live-link-input exporter must use measurement status, not
% the generic trial PASS flag; it must not fill a guessed source.
d=struct('Direction',"DL",'UEIndex',1,'RNTI',101,'Frame',1,'Slot',1, ...
    'BaseStationID',1,'SNR_dB',40,'ConfiguredSNR_dB',40,'AppliedAWGNSNR_dB',40, ...
    'PostEqSINR_dB',23.4,'PostEqSINRSource',source, ...
    'PostEqSINRValueRole',role,'PostEqSINRValueStatus',"OK_decision_residual_bounded", ...
    'ReceiverHestSINR_dB',27.6,'WidebandCQI',5,'MCSIndex',1,'PMI',0,'CRI',0, ...
    'RankIndicator',1,'Modulation',"QPSK",'TargetCodeRate',.25, ...
    'CRCPass',1,'Crash',0,'Status',"PASS",'BitErrors',0,'BitsCompared',1000);
dl=repmat(d,2,1); dl(2).Slot=2; dl(2).PostEqSINRValueStatus="FAILED_receiver_measurement";
out=sixgr.truth.exportLLSLiveDerivedTables(cfg,fullfile(root,'link_inputs'), ...
    struct('DL',struct2table(dl)),struct(),struct(),struct());
T=out.LinkAdaptationInput;
assert(height(T)==2 && T.ValueSource(1)==source && T.ValueRole(1)==role);
assert(T.ValueStatus(1)=="OK_decision_residual_bounded");
assert(strlength(T.ValueSource(2))==0 && strlength(T.ValueStatus(2))==0, ...
    'A failed SINR cannot become an accepted input because its TB passed.');

% The dictionary defines a field, not the executed receiver's estimator.
main=fileparts(which('setup6GRSimToolkit'));
scfg=sixgr.lls6g.config.loadScenarioConfig(fullfile(main,'simulator','configs', ...
    'scenarios','h4_100_cdlc100_connected_impaired_40db_short.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(scfg,fullfile(root,'ownership'));
out=sixgr.truth.exportLLSConfigOwnershipArtifacts(fullfile(root,'ownership'),scfg,cfg);
T=sixgr.util.csvReadTable(out.RuntimeValueSourceDictionary,'TextType','string');
for field=["PostEqSINR_dB","MeasuredTrialSINR_dB"]
    r=T(T.FieldName==field,:);
    assert(height(r)==1 && r.ValueSource=="row_specific_receiver_measurement_see_companion_fields");
    assert(r.ValueStatus=="ROW_SPECIFIC" && ~logical(r.FinalizedFlag));
end
fprintf('LLS_COVERAGE_SINR_PROVENANCE_PASS fixtures=%s\n',root);
ok=true;
end
