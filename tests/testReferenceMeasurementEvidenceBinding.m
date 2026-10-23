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
% Preserve an actual zero-error diagnostic and its original reference/RF
% scope. Availability and qualification remain independent of the number.
for representation = ["numeric","text"]
    zero = struct('NMSE_dB',-Inf,'TrueChannelNMSE_dB',-10, ...
        'NMSEScoringAvailable',true,'ChannelNMSEReferenceIncludesRFImpairments',false, ...
        'ChannelNMSEReferenceAvailable',true, ...
        'ChannelNMSEReferenceStatus',"declared_reference_fixture", ...
        'ChannelNMSEReferenceEvidenceJSON',"declared_fixture_not_PHY", ...
        'ChannelNMSEReferenceEvidenceSHA256',"declared_fixture_not_SHA", ...
        'ChannelNMSEReferenceErrorIdentifier',"");
    if representation=="text", zero.NMSE_dB="-Inf"; end
    state=sixgr.truth.CoupledTruthRuntime.publishReferenceSignalMeasurementRuntime( ...
        state,'TRS','Cell',1,zero,'ProducerSlot',47,'AvailableSlot',49,'Valid',true);
    observed=state.ReferenceSignalMeasurementTable(end,:);
    assert(observed.NMSE_dB==-Inf && observed.NMSEScoringAvailable && ...
        ~observed.ChannelNMSEReferenceIncludesRFImpairments);
    for field=["ChannelNMSEReferenceAvailable","ChannelNMSEReferenceStatus", ...
            "ChannelNMSEReferenceEvidenceJSON","ChannelNMSEReferenceEvidenceSHA256", ...
            "ChannelNMSEReferenceErrorIdentifier"]
        assert(isequaln(observed.(field),zero.(field)),'Lost original reference field %s.',field);
    end
end
zero.NMSE_dB=-Inf; zero.NMSEScoringAvailable=false;
zero.ChannelNMSEReferenceAvailable=false;
zero.ChannelNMSEReferenceIncludesRFImpairments=NaN;
state=sixgr.truth.CoupledTruthRuntime.publishReferenceSignalMeasurementRuntime( ...
    state,'TRS','Cell',1,zero,'ProducerSlot',47,'AvailableSlot',49,'Valid',false);
observed=state.ReferenceSignalMeasurementTable(end,:);
assert(observed.NMSE_dB==-Inf && ~observed.NMSEScoringAvailable && ...
    ~observed.ChannelNMSEReferenceAvailable && ~observed.Valid && ...
    isnan(observed.ChannelNMSEReferenceIncludesRFImpairments), ...
    'A zero error must not manufacture authority, validity or RF scope.');
bad=zero; bad.NMSE_dB=[-Inf -10];
try
    sixgr.truth.CoupledTruthRuntime.publishReferenceSignalMeasurementRuntime( ...
        state,'TRS','Cell',1,bad,'ProducerSlot',47,'AvailableSlot',49,'Valid',true);
    error('test:GuardBypassed','A vector must not be reduced to its first NMSE value.');
catch cause
    assert(strcmp(cause.identifier,'sixgr:truth:InvalidReferenceNMSEScalar'));
end
bad=zero; bad.ChannelNMSEReferenceIncludesRFImpairments=2;
try
    sixgr.truth.CoupledTruthRuntime.publishReferenceSignalMeasurementRuntime( ...
        state,'TRS','Cell',1,bad,'ProducerSlot',47,'AvailableSlot',49,'Valid',true);
    error('test:GuardBypassed','A nonboolean RF extent must not enter reference metadata.');
catch cause
    assert(strcmp(cause.identifier,'sixgr:truth:InvalidReferenceRFExtent'));
end
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
