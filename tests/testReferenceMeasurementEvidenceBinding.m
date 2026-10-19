function ok=testReferenceMeasurementEvidenceBinding()
% Declared scoring/publication boundary rows, not physical qualification.
setup6GRSimToolkit('Verbose',false);
state=struct('CurrentSlot',46);
row=table(45,30.415,-26.39,true,417792,6528,"independent_SRS", ...
    "receiver_clock_SRS_reference",true,false,-14, ...
    'VariableNames',{'Slot','MeasuredTrialSINR_dB','NMSE_dB','NMSEScoringAvailable', ...
    'ChannelNMSEComparedComplexValues','ChannelNMSEPilotResourceCount', ...
    'NMSEReferenceSource','ChannelNMSEReferencePlane','ChannelNMSEPhaseAligned', ...
    'ChannelNMSEGainFitted','SRS_RSRP_dB_re_UnitOccupiedRE_Es'});
state=sixgr.truth.CoupledTruthRuntime.publishReferenceSignalMeasurementRuntime( ...
    state,'SRS','UE',1,row,'ProducerSlot',45,'AvailableSlot',46,'Valid',true);
T=state.ReferenceSignalMeasurementTable;
assert(T.SINR_dB==row.MeasuredTrialSINR_dB && T.SINRSourceField=="MeasuredTrialSINR_dB");
assert(T.NMSEScoringAvailable && T.ChannelNMSEComparedComplexValues==417792 && ...
    T.ChannelNMSEPilotResourceCount==6528 && T.ChannelNMSEPhaseAligned && ~T.ChannelNMSEGainFitted);
assert(T.RSRP_dB_re_UnitOccupiedRE_Es==-14 && isnan(T.RSRP_dBm));
% Match the actual CSI producer's selected-resource power alias. Absolute
% dBm is deliberately absent from this normalized experiment.
csi=table(6,-11.031863829463,"normalized_fixed_esn0_unit_occupied_re_es",2, ...
    'VariableNames',{'Slot','MeasurementRSRP_dB_re_UnitOccupiedRE_Es','PowerReferencePlane','ResourceID'});
state=sixgr.truth.CoupledTruthRuntime.publishReferenceSignalMeasurementRuntime( ...
    state,'CSI-RS','UE',1,csi,'ProducerSlot',6,'AvailableSlot',7,'Valid',true);
T=state.ReferenceSignalMeasurementTable;
assert(T.RSRP_dB_re_UnitOccupiedRE_Es(end)==csi.MeasurementRSRP_dB_re_UnitOccupiedRE_Es && ...
    isnan(T.RSRP_dBm(end)) && string(T.PowerReferencePlane(end))==csi.PowerReferencePlane && ...
    T.ResourceId(end)==2,'The selected CSI resource power must retain its value, units and identity.');
pilotScore=sixgr.phy.trs.scoreTRSPilotDisturbance();
pilotScore.IndependentPilotSNDRAvailable=true; pilotScore.IndependentPilotSNDR_dB=20;
pilotScore.IndependentPilotValueRole="declared_scoring_fixture_not_scheduler_input";
trs=struct2table(pilotScore);
state=sixgr.truth.CoupledTruthRuntime.publishReferenceSignalMeasurementRuntime( ...
    state,'TRS','Cell',1,trs,'ProducerSlot',47,'AvailableSlot',49,'Valid',true);
T=state.ReferenceSignalMeasurementTable;
assert(T.IndependentPilotSNDR_dB(end)==20 && isnan(T.SINR_dB(end)), ...
    'Scoring-only SNDR must not silently become the receiver SINR authority.');
% Export an unavailable set and a known empty set through the real writer.
% Neither is a synthetic missed/successful preamble or false-alarm trial.
folder=tempname; mkdir(folder);
raw=table([0;0],[0;NaN],[true;false],["";""],[false;true], ...
    'VariableNames',{'PreambleIndexTx','PreambleIndexDetected','PreambleDetected', ...
    'DetectedPreambleSet','DetectedPreambleSetAvailable'});
pruned=sixgr.util.pruneStructurallyBlankTableColumns(raw);
assert(ismember('DetectedPreambleSet',pruned.Properties.VariableNames));
path=fullfile(folder,'prach_trials.csv');
sixgr.truth.writeOptionalRuntimeFeatureTable(struct(),'prach',string(path),raw);
saved=sixgr.util.csvReadTable(path);
assert(all(ismember({'DetectedPreambleSet','DetectedPreambleSetAvailable'},saved.Properties.VariableNames)));
assert(isstring(saved.DetectedPreambleSet),'Received-set vectors must not be inferred as scalars.');
[missed,wrong]=sixgr.report.prachTargetDetectionEvidence(saved);
assert(isequal(missed,[0;1]) && wrong(1)==0 && isnan(wrong(2)));
bad=removevars(raw,'DetectedPreambleSet');
try
    sixgr.report.prachTargetDetectionEvidence(bad);
    error('test:GuardBypassed','An incomplete declared set must fail.');
catch cause
    assert(strcmp(cause.identifier,'sixgr:report:IncompletePRACHDetectionSet'));
end
ok=true; fprintf('PASS testReferenceMeasurementEvidenceBinding\n');
end
