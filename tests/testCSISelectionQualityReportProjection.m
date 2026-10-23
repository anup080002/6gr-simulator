function [ok,folder]=testCSISelectionQualityReportProjection(sourceRoot)
% Retained actual v13 CSI-only evidence -> diagnostic report publication.
% No PHY is executed and no new measurement/accuracy population is authored.
% Negative mutations exist ONLY in separately named copies, never originals.
setup6GRSimToolkit('Verbose',false);
if nargin==0
    sourceRoot=fullfile(pwd,'results','validation','n40_shared_csi_selection','20261023_004402_239');
end
sourceCSV=fullfile(sourceRoot,'csi_rs_trials.csv');
assert(isfile(sourceCSV),'test:MissingRetainedCSISelection','Retained actual v13 source is required, not a fabricated replacement.');
originalRow=sixgr.util.csvReadTable(sourceCSV,'TextType','string');
assert(height(originalRow)==1 && originalRow.CSISelectionQualityAvailable==1);
matRelative=string(originalRow.CSISelectionQualityMATFile);
csvRelative=string(originalRow.CSISelectionQualityCandidatesCSV);
originalPaths=[string(sourceCSV),string(fullfile(sourceRoot,matRelative)),string(fullfile(sourceRoot,csvRelative))];
before=hashes(originalPaths);
assert(before(2)==string(originalRow.CSISelectionQualityMATFileSHA256) && ...
    before(3)==string(originalRow.CSISelectionQualityCandidatesCSVSHA256));
p=load(char(originalPaths(2)));
row=projection(originalRow,p);
observed=sixgr.report.collectCSISelectionQualityEvidence(sourceRoot,row);
assert(height(observed)==1 && observed.DiagnosticAvailable && observed.SourceRowIndex==1 && ...
    observed.SelectedRank==originalRow.RI && observed.SelectedPMI==originalRow.PMI && ...
    observed.ConditionalPMIRegret_bpsHz==p.Summary.ConditionalPMIRegret_bpsHz && ...
    observed.RankRegret_bpsHz==p.Summary.RankRegret_bpsHz && ...
    observed.JointRegret_bpsHz==p.Summary.JointRegret_bpsHz && ...
    observed.CandidateCount==80 && observed.SupportCount==204 && ...
    observed.PhysicalPowerUnit=="mW_scaled_grid_coefficient_squared_units");
assert(observed.RunFolder==string(p.Identity.RunFolder) && ...
    observed.RandomSeed==p.Identity.RandomSeed && observed.ChannelSeed==p.Identity.ChannelSeed && ...
    observed.SweepPointIndex==p.Identity.SweepPointIndex && ...
    observed.ConfiguredSNR_dB==p.Identity.ConfiguredSNR_dB && ...
    observed.IdentityJSON==row.CSISelectionQualityIdentityJSON && ...
    ~observed.PopulationScopeComplete, ...
    'test:CSISelectionHistoricalPopulation','Do not invent lifecycle fields absent from this actual older capture.');
unqualified(observed);
empty=sixgr.report.collectCSISelectionQualityEvidence(sourceRoot,row([],:));
assert(isempty(empty) && islogical(empty.DiagnosticAvailable) && isstring(empty.ObservationID));
absent=removevars(row,row.Properties.VariableNames(startsWith(string(row.Properties.VariableNames),'CSISelectionQuality')));
assert(isempty(sixgr.report.collectCSISelectionQualityEvidence(sourceRoot,absent)));
bad=row; bad.CSISelectionQualityMATFile="";
reject(@()sixgr.report.collectCSISelectionQualityEvidence(sourceRoot,bad),'sixgr:report:CSISelectionArchiveMissing');
for name=["CSIMeasurementID","ReceiverWindowID","ReceiverObservationSHA256","CSIReportConfigID"]
    bad=row; bad.(name)="different_original_owner";
    reject(@()sixgr.report.collectCSISelectionQualityEvidence(sourceRoot,bad),'sixgr:report:CSISelectionArchiveIdentity');
end
for name=["SweepPointIndex","RandomSeed","ChannelSeed","CSIConfigurationEpoch","ObservationStartSample"]
    bad=row; bad.(name)=bad.(name)+1;
    reject(@()sixgr.report.collectCSISelectionQualityEvidence(sourceRoot,bad),'sixgr:report:CSISelectionArchiveIdentity');
end
bad=row; bad.NoiseStreamSeed=bad.NoiseStreamSeed+1;
reject(@()sixgr.report.collectCSISelectionQualityEvidence(sourceRoot,bad),'sixgr:report:CSISelectionArchiveNoise');
bad=row; bad.CSISelectionQualityMATFile="../foreign/operand.mat";
reject(@()sixgr.report.collectCSISelectionQualityEvidence(sourceRoot,bad),'sixgr:report:CSISelectionArchivePath');
reject(@()sixgr.report.collectCSISelectionQualityEvidence(sourceRoot,[row;row]), ...
    'sixgr:report:CSISelectionDuplicateObservation');

folder=fullfile(pwd,'results','validation','csi_nominal_selection_projection', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(folder); fprintf('CSI_NOMINAL_SELECTION_PROJECTION_ROOT=%s\n',folder);
% Re-sealed operand corruption must still fail against the ORIGINAL row.
q=p; q.Inputs.Selection.Identity.MeasurementID="resealed_other_measurement";
rejectCopy(q,"resealed_selection_identity",'sixgr:report:CSISelectionArchiveIdentity');
q=p; q.Inputs.Disturbance.NoiseStreamSeed=q.Inputs.Disturbance.NoiseStreamSeed+1;
q.Inputs.Disturbance.NoiseReceipt.ValidatedNoiseRecord.NoiseStreamSeed=q.Inputs.Disturbance.NoiseStreamSeed;
q.Inputs.Disturbance.NoiseReceiptSHA256=sixgr.util.sha256Hex(jsonencode(q.Inputs.Disturbance.NoiseReceipt));
rejectCopy(q,"resealed_noise_receipt",'sixgr:report:CSISelectionArchiveNoise');
q=p; q.Inputs.Request.Epoch=q.Inputs.Request.Epoch+1;
rejectCopy(q,"resealed_request",'sixgr:report:CSISelectionArchiveIdentity');
q=p; q.Candidates.Objective_bpsHz(1)=q.Candidates.Objective_bpsHz(1)+1;
rejectCopy(q,"changed_candidate_arithmetic",'sixgr:report:CSISelectionArchiveRecompute');
q=p; q.CandidateMatrices{1}=2*q.CandidateMatrices{1};
rejectCopy(q,"changed_candidate_matrix",'sixgr:truth:CSISelectionArchiveRecompute');
q=p; q.Inputs.Reference.Support(1,1)=q.Inputs.Reference.Support(1,1)+100000;
rejectCopy(q,"resealed_support",'sixgr:report:CSISelectionArchiveRecompute');
corrupt=fullfile(folder,'changed_candidate_csv'); copyOriginal(corrupt);
C=sixgr.util.csvReadTable(fullfile(corrupt,csvRelative),'TextType','string');
C.Objective_bpsHz(1)=C.Objective_bpsHz(1)+1;
sixgr.util.csvWriteTable(fullfile(corrupt,csvRelative),C,'PreserveSchema',true,'RoundTripNumericText',true);
bad=row; bad.CSISelectionQualityCandidatesCSVSHA256=sixgr.util.sha256File(fullfile(corrupt,csvRelative));
q=p; q.CandidatesCSVSHA256=bad.CSISelectionQualityCandidatesCSVSHA256;
sixgr.util.matSave(fullfile(corrupt,matRelative),q,'UseArtifactStore',false);
bad.CSISelectionQualityMATFileSHA256=sixgr.util.sha256File(fullfile(corrupt,matRelative));
reject(@()sixgr.report.collectCSISelectionQualityEvidence(corrupt,bad),'sixgr:report:CSISelectionArchiveCSV');

% Invoke the actual production report writer on a relocated, unchanged
% source projection. Retained RunFolder stays the original execution root.
reportRoot=fullfile(folder,'report_readback'); copyOriginal(reportRoot);
layout=sixgr.report.resultLayout(reportRoot); sixgr.util.ensureFolder(layout.AirInterfaceCSVDir);
sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir,'csi_rs_trials.csv'),row, ...
    'PreserveSchema',true,'RoundTripNumericText',true);
scfg=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml');
retained=load(fullfile(sourceRoot,'configuration.mat'),'cfg'); cfg=retained.cfg;
manifest=struct('CodeVersion',"test",'CodeDetail',"retained_actual_v13_CSI_only_readback_no_new_PHY", ...
    'RandomSeed',p.Identity.RandomSeed,'GeneratedUTC',"test",'RunnerProfile',"test", ...
    'RunCompletion',"partial",'DeterministicMode',"test");
report=sixgr.truth.exportLLSReportingBundle(reportRoot,scfg,cfg,struct('Ok',false), ...
    manifest,struct('StartedUTC',"test",'ElapsedSeconds',0),struct());
published=sixgr.util.csvReadTable(fullfile(layout.ReportCSVDir, ...
    'csi_nominal_selection_quality_observations.csv'),'TextType','string');
assert(isequal(published.Properties.VariableNames,observed.Properties.VariableNames) && height(published)==1);
for name=string(observed.Properties.VariableNames)
    if isnumeric(observed.(name))||islogical(observed.(name))
        assert(isequaln(sixgr.truth.numericMeasurementColumn(published.(name),name),double(observed.(name))));
    else
        assert(isequaln(string(published.(name)),string(observed.(name))));
    end
end
unqualified(published);
for key=["pmi_accuracy","ri_accuracy"]
    R=report.CategoryRows(report.CategoryRows.MetricKey==key,:);
    assert(~isempty(R) && all(R.Availability=="not_available") && ...
        ~any(R.CountsTowardCoverage) && ~any(isfinite(R.ValueNumeric)), ...
        'test:CSISelectionDiagnosticPromoted','Nominal diagnostic must not fill %s.',key);
end
assert(isequal(before,hashes(originalPaths)) && ...
    sixgr.util.sha256File(fullfile(reportRoot,matRelative))==before(2) && ...
    sixgr.util.sha256File(fullfile(reportRoot,csvRelative))==before(3), ...
    'test:CSISelectionOriginalChanged','Retained source bytes must remain immutable.');
save(fullfile(folder,'readback.mat'),'observed','published','originalPaths','before');
fprintf('CSI_NOMINAL_SELECTION_PROJECTION_PASS retained_actual_v13=1 new_PHY=0 accuracy_qualification=0 folder=%s\n',folder);
ok=true;

    function copyOriginal(target)
        mkdir(fullfile(target,'beamforming','mat')); mkdir(fullfile(target,'beamforming','csv'));
        copyfile(char(originalPaths(2)),fullfile(target,matRelative));
        copyfile(char(originalPaths(3)),fullfile(target,csvRelative));
    end

    function rejectCopy(q,label,identifier)
        target=fullfile(folder,label); copyOriginal(target);
        for input=["Reference","Selection","Request","Disturbance","Policy"]
            q.SourceHashes.(input+"SHA256")=sixgr.truth.csiSelectionArchiveDigest(q.Inputs.(input));
        end
        q.OperandSetSHA256=sixgr.truth.csiSelectionArchiveDigest(q.SourceHashes);
        sixgr.util.matSave(fullfile(target,matRelative),q,'UseArtifactStore',false);
        changed=row; changed.CSISelectionQualityMATFileSHA256=sixgr.util.sha256File(fullfile(target,matRelative));
        changed.CSISelectionQualityOperandSetSHA256=q.OperandSetSHA256;
        reject(@()sixgr.report.collectCSISelectionQualityEvidence(target,changed),identifier);
    end
end

function row=projection(original,p)
names=string(original.Properties.VariableNames);
keep=startsWith(names,'CSISelectionQuality');
% All owner fields remain verbatim; omit unrelated artifact pointers rather
% than copying gigabytes of IQ or relabelling a complete campaign.
aliases=["RI","PMI","CSIMeasurementID","CSIMeasurementDigest","CSIConfigurationEpoch", ...
    "CSIReportConfigID","ObservationSampleRateHz","ReceiverObservationSHA256","Slot","CRI", ...
    "CSIObservationPopulationJSON","CSIObservationPopulationBindingJSON"];
aliases=[aliases,string(fieldnames(p.Identity)).',string(fieldnames(p.Inputs.Disturbance.NoiseReceipt.ValidatedNoiseRecord)).'];
row=original(:,keep|ismember(names,aliases));
end

function unqualified(T)
for name=["StandardizedPMIAccuracyQualified","StandardizedRIAccuracyQualified", ...
        "ActualPDSCHPerformanceQualified","CodedRankPerformanceQualified","StatisticallyQualified","CountsTowardCoverage"]
    assert(all(sixgr.truth.numericMeasurementColumn(T.(name),name)==0));
end
assert(all(contains(T.EvidenceRole,'not_practical_MaxSE')) && ...
    all(T.Scope=="hypothetical_equal_raw_grid_chain_coefficient_power_nominal_linear_noise_only_fixed_CRI"));
end

function value=hashes(paths)
value=strings(size(paths));
for k=1:numel(paths), value(k)=string(sixgr.util.sha256File(paths(k))); end
end

function reject(f,identifier)
try
    f();
catch cause
    assert(string(cause.identifier)==string(identifier),'test:WrongCSISelectionRejection', ...
        'Expected %s, got %s: %s',identifier,cause.identifier,cause.message);
    return;
end
error('test:MissingCSISelectionRejection','Expected %s.',identifier);
end
