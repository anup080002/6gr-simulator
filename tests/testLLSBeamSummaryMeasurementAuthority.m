function ok = testLLSBeamSummaryMeasurementAuthority()
% Reporting fixtures only: never export these as runtime PHY observations.
% A source/configured SNR must not become a measured beam-quality value.
root = tempname;
mkdir(root);
cfg = sixgr.config.defaultConfig();
pbch = table([1;1], [1;1], [1;2], [0;1], [-70;-80], ...
    [35.7766108843276;35.7766108843276], [12;12], [51;38], ...
    'VariableNames', {'UEIndex','Slot','BeamIndex','SSBIndex','SS_RSRP_dBm', ...
    'SNR_dB','ConfiguredSNR_dB','PostEqSINR_dB'});
pbch.PostEqSINRSource = repmat("fixture_receiver_estimate",2,1);
pbch.PostEqSINRValueRole = repmat("estimated_post_equalization",2,1);
artifacts = sixgr.truth.exportLLSLiveDerivedTables(cfg,fullfile(root,'configured'), ...
    struct('PBCH',pbch),struct(),struct(),struct());
T = readtable(artifacts.BeamP1AcquisitionStatsPath,'TextType','string');
power = T(string(T.Metric)=="P1SS_RSRP_dBm",:);
assert(height(power)==1 && power.SNR_dB==12, ...
    'Use the explicit configured operating point without substituting source SNR.');
assert(power.QualityAxis=="PostEqSINR_dB" && ...
    abs(power.QualityMean_dB-44.5)<1e-12 && power.QualitySampleCount==2, ...
    'Beam quality must retain the actual receiver-value distribution.');
assert(power.QualitySource=="fixture_receiver_estimate" && ...
    power.QualityValueRole=="estimated_post_equalization", ...
    'Do not upgrade an estimated receiver axis or discard its producer source.');
selected = T(string(T.Metric)=="P1SelectedSSBBeamIndex",:);
assert(height(selected)==1 && selected.MeanValue==0, ...
    'An SSB-index metric must use the physical zero-based SSBIndex, not BeamIndex.');

% Without configured SNR or measured quality, retain exact source metadata,
% but do not manufacture a measured-quality value from that metadata.
noQuality = removevars(pbch,{'ConfiguredSNR_dB','PostEqSINR_dB', ...
    'PostEqSINRSource','PostEqSINRValueRole'});
artifacts = sixgr.truth.exportLLSLiveDerivedTables(cfg,fullfile(root,'source_only'), ...
    struct('PBCH',noQuality),struct(),struct(),struct());
T = readtable(artifacts.BeamP1AcquisitionStatsPath,'TextType','string');
power = T(string(T.Metric)=="P1SS_RSRP_dBm",:);
assert(height(power)==1 && abs(power.SNR_dB-pbch.SNR_dB(1))<1e-12, ...
    'Do not silently round source metadata into a different operating point.');
assert(power.SNR_dBValueRole=="source_defined_snr_axis" && ...
    isnan(power.QualityMean_dB) && power.QualitySampleCount==0 && ...
    contains(power.QualityValueRole,"unavailable"), ...
    'Unavailable receiver quality must remain unavailable even with source SNR.');

% Different UE/burst identities cannot share one selected-beam winner.
other = pbch;
other.UEIndex(:)=2;
other.SS_RSRP_dBm=[-90;-60];
later = pbch;
later.Slot(:)=21;
later.SS_RSRP_dBm=[-90;-65];
artifacts = sixgr.truth.exportLLSLiveDerivedTables(cfg,fullfile(root,'scoped'), ...
    struct('PBCH',[pbch;other;later]),struct(),struct(),struct());
T = readtable(artifacts.BeamP1AcquisitionStatsPath,'TextType','string');
selected = T(string(T.Metric)=="P1SelectedSSBBeamIndex",:);
assert(height(selected)==3 && ...
    all(ismember({'UEIndex','Slot'},selected.Properties.VariableNames)), ...
    'Selected-beam evidence must retain separate UE and authored-burst identities.');
assert(selected.MeanValue(selected.UEIndex==1 & selected.Slot==1)==0);
assert(selected.MeanValue(selected.UEIndex==2 & selected.Slot==1)==1);
assert(selected.MeanValue(selected.UEIndex==1 & selected.Slot==21)==1);
assert(all(selected.SelectionEvidenceRole=="posthoc_measured_candidate_comparison_not_receiver_decision"));
% Direct reducer checks: duplicate observations do not invent extra beams,
% and missing power does not erase an observed candidate from sweep coverage.
partial=pbch([1 2 2],:); partial.SS_RSRP_dBm(2:3)=NaN;
got=sixgr.truth.buildBeamMeasurementSummary(partial,"SSB_DL","fixture",struct([]),true);
assert(got.MeanValue(got.Metric=="P1SSBSweptBeamCount")==2);
assert(all(got.UnscoredCandidateCount==2));
unknownIndex=removevars(pbch,'SSBIndex');
assert(isempty(sixgr.truth.buildBeamMeasurementSummary(unknownIndex,"SSB_DL","fixture",struct([]),true)), ...
    'Internal BeamIndex alone cannot establish the physical SSB index.');
bad=pbch; bad.SSBIndex(1)=-1;
rejected=false;
try
    sixgr.truth.buildBeamMeasurementSummary(bad,"SSB_DL","fixture",struct([]),true);
catch err
    if ~strcmp(err.identifier,'sixgr:truth:InvalidPhysicalSSBIndex'), rethrow(err); end
    rejected=true;
end
assert(rejected);
bad=pbch; bad.ProxyUsed=[true;false]; rejected=false;
try
    sixgr.truth.buildBeamMeasurementSummary(bad,"SSB_DL","fixture",struct([]),true);
catch err
    if ~strcmp(err.identifier,'sixgr:truth:ProxyBeamSummaryInput'), rethrow(err); end
    rejected=true;
end
assert(rejected);
% Normalized-power experiments have no absolute-dBm authority. Retain
% their actual normalized measurements and select in that same domain.
relative=pbch;
relative.PowerReferencePlane=repmat("normalized_fixed_esn0_unit_occupied_re_es",2,1);
relative.SS_RSRP_dBm(:)=NaN;
relative.SS_RSRP_dB_re_UnitOccupiedRE_Es=[-9;-5];
artifacts=sixgr.truth.exportLLSLiveDerivedTables(cfg,fullfile(root,'normalized'), ...
    struct('PBCH',relative),struct(),struct(),struct());
T=readtable(artifacts.BeamP1AcquisitionStatsPath,'TextType','string');
power=T(string(T.Metric)=="P1SS_RSRP_dB_re_UnitOccupiedRE_Es",:);
selected=T(string(T.Metric)=="P1SelectedSSBBeamIndex",:);
assert(height(power)==1 && power.MeanValue==-7 && power.SampleCount==2);
assert(height(selected)==1 && selected.MeanValue==1 && ...
    selected.ScoreAxis=="SS_RSRP_dB_re_UnitOccupiedRE_Es");
assert(~any(string(T.Metric)=="P1SS_RSRP_dBm"));
% Even identical UE/burst identities cannot make unlike power units
% comparable. Separate the groups by the declared physical reference plane.
absolute=pbch;
absolute.PowerReferencePlane=repmat("ue_antenna_connector_received_ssb_grid",2,1);
absolute.SS_RSRP_dB_re_UnitOccupiedRE_Es=nan(2,1);
mixed=sixgr.truth.buildBeamMeasurementSummary([absolute;relative],"SSB_DL", ...
    "mixed_domain_fixture",struct([]),true);
winners=mixed(mixed.Metric=="P1SelectedSSBBeamIndex",:);
assert(height(winners)==2 && numel(unique(winners.PowerReferencePlane))==2);
assert(winners.MeanValue(winners.ScoreAxis=="SS_RSRP_dBm")==0 && ...
    winners.MeanValue(winners.ScoreAxis=="SS_RSRP_dB_re_UnitOccupiedRE_Es")==1);
fprintf('PASS testLLSBeamSummaryMeasurementAuthority; fixture artifacts: %s\n',root);
ok = true;
end
