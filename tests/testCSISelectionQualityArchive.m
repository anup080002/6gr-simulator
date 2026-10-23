function [ok,folder]=testCSISelectionQualityArchive()
% Component archive/operand contract, NOT production waveform qualification.
% Reuse the validated scorer fixture without weakening any scorer assertions.
[passed,f]=testCSISelectionQuality(); assert(passed);
folder=fullfile(pwd,'results','validation','csi_selection_quality_archive', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(folder);
f=archiveFixture(f,folder); row=ownerRow(f.Reference.Identity);

% Reject wrong owner, endpoint, clock, source digest, map and noise units.
bad=row; bad.ResourceID=12;
mustFail(@()publish(folder,bad,f),'sixgr:truth:CSISelectionArchiveIdentity');
bad=row; bad.ReceiverID="different_UE";
mustFail(@()publish(folder,bad,f),'sixgr:truth:CSISelectionArchiveIdentity');
bad=row; bad.ReceiverClockEpoch=9;
mustFail(@()publish(folder,bad,f),'sixgr:truth:CSISelectionArchiveIdentity');
bad=row; bad.CSIMeasurementDigest="transplanted_measurement";
mustFail(@()publish(folder,bad,f),'sixgr:truth:CSISelectionArchiveIdentity');
bad=row; bad.RandomSeed=2;
mustFail(@()publish(folder,bad,f),'sixgr:truth:CSISelectionArchiveIdentity');
bad=row; bad=removevars(bad,'ReceiverClockDomain');
mustFail(@()publish(folder,bad,f),'sixgr:truth:CSISelectionArchiveIdentity');
g=f; g.Reference.RawPortToPhysicalMatrixSHA256=string(repmat('0',1,64));
mustFail(@()publish(folder,row,g),'sixgr:truth:CSISelectionArchiveSpatialProvenance');
g=f; g.Reference.PortToPhysicalMatrix=2*g.Reference.PortToPhysicalMatrix;
mustFail(@()publish(folder,row,g),'sixgr:truth:CSISelectionArchiveSpatialProvenance');
g=f; g.Policy.PhysicalPowerReferencePlane="time_average_TX_power";
mustFail(@()publish(folder,row,g),'sixgr:truth:CSISelectionArchivePowerPlane');
g=f; g.Policy.PhysicalPowerUnit="mW_scaled_grid_coefficient_squared_units";
mustFail(@()publish(folder,row,g),'sixgr:truth:CSISelectionArchivePowerPlane');
g=f; g.Disturbance.Identity.ReceiverID="different_UE";
mustFail(@()publish(folder,row,g),'sixgr:truth:CSISelectionIdentity');
g=f; g.Disturbance.NoiseReceiptSHA256=string(repmat('0',1,64));
mustFail(@()publish(folder,row,g),'sixgr:truth:CSISelectionArchiveChecksum');
g=f; g.Disturbance=rmfield(g.Disturbance,'NoiseReceipt');
mustFail(@()publish(folder,row,g),'sixgr:truth:CSISelectionArchiveNoiseProvenance');
g=f; g.Disturbance.NoiseReceipt.ReceiverID="different_UE";
g.Disturbance.NoiseReceiptSHA256=sixgr.util.sha256Hex(jsonencode(g.Disturbance.NoiseReceipt));
mustFail(@()publish(folder,row,g),'sixgr:truth:CSISelectionArchiveIdentity');
g=f; g.Disturbance.NoiseReceipt.ReceiverWindowID="different_window_same_clock";
g.Disturbance.NoiseReceiptSHA256=sixgr.util.sha256Hex(jsonencode(g.Disturbance.NoiseReceipt));
mustFail(@()publish(folder,row,g),'sixgr:truth:CSISelectionArchiveIdentity');
g=f; g.Disturbance.NoiseReceipt=rmfield(g.Disturbance.NoiseReceipt,'ReceiverWindowID');
g.Disturbance.NoiseReceiptSHA256=sixgr.util.sha256Hex(jsonencode(g.Disturbance.NoiseReceipt));
mustFail(@()publish(folder,row,g),'sixgr:truth:CSISelectionArchiveIdentity');

before=f; out=publish(folder,row,f);
assert(isequaln(before,f) && out.CSISelectionQualityAvailable && ...
    ~out.CSISelectionQualityStatisticallyQualified && ...
    ~out.CSISelectionQualityActualPDSCHPerformanceQualified && ...
    ~out.CSISelectionQualityCQIBLERQualified && ~out.CSISelectionQualityCRISelectionQualified);
assert(out.CSISelectionQualitySupportCount==3 && out.CSISelectionQualityCandidateCount==6 && ...
    out.CSISelectionQualityPhysicalPowerReferencePlane=="raw_native_grid_physical_chain_coefficient_power");
matPath=fullfile(folder,out.CSISelectionQualityMATFile);
csvPath=fullfile(folder,out.CSISelectionQualityCandidatesCSV);
assert(sixgr.util.sha256File(matPath)==out.CSISelectionQualityMATFileSHA256 && ...
    sixgr.util.sha256File(csvPath)==out.CSISelectionQualityCandidatesCSVSHA256);
p=load(matPath); T=sixgr.util.csvReadTable(csvPath,'TextType','string');
assert(isequaln(p.Inputs.Reference,f.Reference) && isequaln(p.Inputs.Selection,f.Selection) && ...
    isequaln(p.Inputs.Request,f.Request) && isequaln(p.Inputs.Disturbance,f.Disturbance) && ...
    isequaln(p.Inputs.Policy,f.Policy) && any(imag(p.Inputs.Reference.H)~=0,'all'));
assert(all(T.CSISelectionQualityObservationID==f.Reference.Identity.ObservationID) && ...
    all(T.RandomSeed==f.Reference.Identity.RandomSeed) && ...
    all(T.ResourceID=="CSI-RS-11") && all(T.ReceiverID==f.Reference.Identity.ReceiverID) && ...
    all(T.OperandSetSHA256==out.CSISelectionQualityOperandSetSHA256));
assert(max(T.UnscaledPhysicalFrobeniusPower)-min(T.UnscaledPhysicalFrobeniusPower)>1 && ...
    all(abs(T.ScoredPhysicalFrobeniusPower-1)<1e-12));
for k=1:height(T)
    sinr=decodeArray(T.LayerSINRJSON(k)); objective=decodeArray(T.SupportObjectiveJSON(k));
    assert(isequaln(sinr,p.Candidates.LayerSINR{k}) && isequal(size(sinr),[3 T.Rank(k)]) && ...
        isequaln(objective,p.Candidates.SupportObjective_bpsHz{k}) && numel(objective)==3 && ...
        isequaln(sixgr.phy.mimo.MatrixContract.deserialize(T.CandidateMatrixJSON(k)),p.CandidateMatrices{k}));
end
% Independent public scorer readback confirms the archived frozen inputs.
[s,recomputed]=sixgr.truth.scoreCSISelectionQuality(p.Inputs.Reference,p.Inputs.Selection, ...
    p.Inputs.Request,p.Inputs.Disturbance,p.Inputs.Policy);
assert(isequaln(s,p.Summary) && isequaln(recomputed,p.Candidates));
mustFail(@()publish(folder,out,f),'sixgr:truth:CSISelectionArchiveAlreadyExists');
assert(sixgr.util.sha256File(matPath)==out.CSISelectionQualityMATFileSHA256 && ...
    sixgr.util.sha256File(csvPath)==out.CSISelectionQualityCandidatesCSVSHA256);

% Repeated local observation IDs in separately sealed point/seed populations
% remain separate archives/candidate metadata, never hidden pooling.
g=f; id=g.Reference.Identity; id.RandomSeed=2; id.SweepPointIndex=2;
g=bindIdentity(g,id); another=publish(folder,ownerRow(id),g);
assert(another.CSISelectionQualityMATFile~=out.CSISelectionQualityMATFile && ...
    another.CSISelectionQualityObservationID==out.CSISelectionQualityObservationID);
U=sixgr.util.csvReadTable(fullfile(folder,another.CSISelectionQualityCandidatesCSV),'TextType','string');
assert(all(U.RandomSeed==2 & U.SweepPointIndex==2));

% Deliberate corruption is confined to a separate negative-fixture archive;
% the writer detects changed bytes and never repairs/overwrites them.
corruptRoot=fullfile(folder,'deliberately_corrupt_fixture'); mkdir(corruptRoot);
g=f; id=g.Reference.Identity; id.RunFolder=string(corruptRoot); g=bindIdentity(g,id);
corrupt=publish(corruptRoot,ownerRow(id),g);
path=fullfile(corruptRoot,corrupt.CSISelectionQualityCandidatesCSV);
C=sixgr.util.csvReadTable(path,'TextType','string'); C.Objective_bpsHz(1)=C.Objective_bpsHz(1)+1;
sixgr.util.csvWriteTable(path,C,'PreserveSchema',true,'RoundTripNumericText',true);
changed=sixgr.util.sha256File(path);
assert(changed~=corrupt.CSISelectionQualityCandidatesCSVSHA256);
mustFail(@()publish(corruptRoot,corrupt,g),'sixgr:truth:CSISelectionArchiveChecksum');
assert(sixgr.util.sha256File(path)==changed);
fprintf('CSI_SELECTION_QUALITY_ARCHIVE_PASS component_only=1 complex_operands=1 per_support_layers=1 no_overwrite=1 folder=%s\n',folder);
ok=true;
end

function f=archiveFixture(f,folder)
id=f.Reference.Identity;
id.ResourceID="CSI-RS-11"; id.RunFolder=string(folder);
id.ReceiverWindowID="declared_component_receiver_window";
id.RunID=string(folder); id.ExecutionID="explicit_component_archive_fixture_not_runtime";
id.ConfigHash=sixgr.util.sha256Hex("explicit_component_archive_configuration");
id.SweepPointIndex=1;
f=bindIdentity(f,id);
f.Selection.MeasurementResourceID=id.ResourceID;
raw=[1 .6;0 .8]; amplitude=2.5;
f.Reference.RawPortToPhysicalMatrix=raw;
f.Reference.RawPortToPhysicalMatrixSHA256=sixgr.phy.mimo.MatrixContract.digest(raw);
f.Reference.TXAmplitudeScale=amplitude;
f.Reference.PortToPhysicalMatrix=amplitude*raw;
f.Reference.PortToPhysicalMatrixSHA256=sixgr.phy.mimo.MatrixContract.digest(f.Reference.PortToPhysicalMatrix);
original=f.Reference.H;
f.Reference.H=cat(3,original*f.Reference.PortToPhysicalMatrix, ...
    -1i*original*f.Reference.PortToPhysicalMatrix,.3*original*f.Reference.PortToPhysicalMatrix);
f.Reference.Support=[0 3;1 3;4 5];
f.Reference.ArchiveFixtureScope="declared_component_operands_not_executed_runtime_evidence";
f.Policy.PhysicalPowerReferencePlane="raw_native_grid_physical_chain_coefficient_power";
f.Policy.PhysicalPowerUnit="normalized_grid_coefficient_squared_units";
f.Disturbance.WaveformAmplitudeUnit="normalized_complex_baseband";
% This is a declared component receipt for archive/hash testing only. The
% production noise helper separately owns validation of executed segments.
receipt=struct('ContractVersion',"declared_component_noise_receipt_not_runtime", ...
    'ReceiverWindowID',id.ReceiverWindowID, ...
    'ReceiverID',id.ReceiverID,'ReceiverClockDomain',id.ReceiverClockDomain, ...
    'ReceiverClockEpoch',id.ReceiverClockEpoch,'ObservationStartSample',id.ObservationStartSample, ...
    'ObservationEndSampleExclusive',id.ObservationEndSampleExclusive,'SampleRateHz',id.SampleRateHz);
f.Disturbance.NoiseReceipt=receipt;
f.Disturbance.NoiseReceiptSHA256=sixgr.util.sha256Hex(jsonencode(receipt));
end

function f=bindIdentity(f,id)
f.Reference.Identity=id; f.Selection.Identity=id; f.Disturbance.Identity=id;
end

function row=ownerRow(id)
row=table();
for name=string(fieldnames(id)).'
    alias=name;
    switch name
        case "ObservationID", alias="CSISelectionQualityObservationID";
        case "MeasurementID", alias="CSIMeasurementID";
        case "MeasurementDigest", alias="CSIMeasurementDigest";
        case "ConfigurationEpoch", alias="CSIConfigurationEpoch";
        case "ReportConfigID", alias="CSIReportConfigID";
        case "SampleRateHz", alias="ObservationSampleRateHz";
        case "MeasurementSlot", alias="Slot";
        case "ResourceOrdinal0", alias="CRI";
        case "RequestSHA256", continue;
    end
    if name=="ResourceID", row.ResourceID=11; else, row.(alias)=id.(name); end
end
row.CSISelectionQualityIdentityJSON=string(jsonencode(id));
end

function row=publish(folder,row,f)
row=sixgr.truth.exportCSISelectionQuality(folder,row,f.Reference,f.Selection,f.Request,f.Disturbance,f.Policy);
end

function value=decodeArray(token)
p=jsondecode(token); assert(string(p.Contract)=="sixgr_real_array_column_major/v1");
value=reshape(cast(p.ColumnMajorValues,char(p.Class)),double(p.Shape(:).'));
end

function mustFail(action,expected)
try, action();
catch ex
    assert(strcmp(ex.identifier,expected),'Expected %s, received %s: %s',expected,ex.identifier,ex.message);
    return;
end
error('sixgr:test:ExpectedFailure','Expected %s.',expected);
end
