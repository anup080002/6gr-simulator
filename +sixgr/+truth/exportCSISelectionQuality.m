function row=exportCSISelectionQuality(root,row,reference,selection,request,disturbance,policy)
% Immutable private UE-selection engineering evidence, after reception only.
% This writer neither selects UCI nor proves delivery or grant application.
% The caller retains runtime receipts; an archive is not new PHY execution.
arguments
    root {mustBeTextScalar}
    row table
    reference (1,1) struct
    selection (1,1) struct
    request (1,1) struct
    disturbance (1,1) struct
    policy (1,1) struct
end
assert(isfolder(root) && height(row)==1,'sixgr:truth:CSISelectionArchiveScope', ...
    'Use one actual owner row and its existing run folder.');
validateOwner(row,reference.Identity,request);
if isfield(reference.Identity,'RunFolder')
    assert(string(java.io.File(char(root)).getCanonicalPath())== ...
        string(java.io.File(char(reference.Identity.RunFolder)).getCanonicalPath()), ...
        'sixgr:truth:CSISelectionArchiveScope','The archive must remain within its declared actual run folder.');
end
validateMapAndUnits(reference,disturbance,policy);
identitySHA=digestValue(reference.Identity);
stem="csi_selection_quality_"+identitySHA;
csvRelative=fullfile('beamforming','csv',stem+".csv");
matRelative=fullfile('beamforming','mat',stem+".mat");
csvPath=fullfile(root,csvRelative); matPath=fullfile(root,matRelative);
% Identity addressing, not content addressing: a changed result cannot
% silently create a second publication for the same frozen observation.
if isfile(csvPath) && ismember('CSISelectionQualityCandidatesCSVSHA256',row.Properties.VariableNames)
    assert(string(sixgr.util.sha256File(csvPath))==string(row.CSISelectionQualityCandidatesCSVSHA256), ...
        'sixgr:truth:CSISelectionArchiveChecksum','An already-published candidate archive is corrupt.');
end
if isfile(matPath) && ismember('CSISelectionQualityMATFileSHA256',row.Properties.VariableNames)
    assert(string(sixgr.util.sha256File(matPath))==string(row.CSISelectionQualityMATFileSHA256), ...
        'sixgr:truth:CSISelectionArchiveChecksum','An already-published operand archive is corrupt.');
end
assert(~isfile(csvPath) && ~isfile(matPath),'sixgr:truth:CSISelectionArchiveAlreadyExists', ...
    'Never overwrite or republish private selection evidence for this identity.');
inputs=struct('Reference',reference,'Selection',selection,'Request',request, ...
    'Disturbance',disturbance,'Policy',policy);
hashes=sourceHashes(inputs); operandSHA=digestValue(hashes);
[summary,candidates]=sixgr.truth.scoreCSISelectionQuality(reference,selection,request,disturbance,policy);
matrices=candidateMatrices(candidates,request);
published=candidateCSV(candidates,matrices,reference.Identity,summary,identitySHA,operandSHA,policy);
sixgr.util.csvWriteTable(csvPath,published,'PreserveSchema',true,'RoundTripNumericText',true);
csvSHA=string(sixgr.util.sha256File(csvPath));
payload=struct('Contract',"sixgr_private_UE_CSI_selection_quality_archive/v1", ...
    'Identity',reference.Identity,'IdentitySHA256',identitySHA,'Inputs',inputs, ...
    'SourceHashes',hashes,'OperandSetSHA256',operandSHA, ...
    'SourceHashContract',"sixgr_typed_plain_value_shape_and_exact_numeric_bytes/v1", ...
    'Summary',summary,'Candidates',candidates,'CandidateMatrices',{matrices}, ...
    'PublishedCandidates',published,'CandidatesCSV',string(csvRelative), ...
    'CandidatesCSVSHA256',csvSHA, ...
    'ArrayRepresentation',"sixgr_real_array_column_major/v1", ...
    'PhysicalPowerReferencePlane',string(policy.PhysicalPowerReferencePlane), ...
    'PhysicalPowerUnit',string(policy.PhysicalPowerUnit), ...
    'EvidenceScope',"private_UE_fixed_CRI_selection_quality_not_UCI_delivery_or_applied_grant", ...
    'InputProvenanceAuthority',"caller_retained_execution_receipts_not_reconstructed_by_archiver", ...
    'StatisticallyQualified',false);
sixgr.util.matSave(matPath,payload,'UseArtifactStore',false);
matSHA=string(sixgr.util.sha256File(matPath));
saved=load(char(matPath));
assert(isequaln(saved,payload),'sixgr:truth:CSISelectionArchiveMATClosure', ...
    'Every original complex operand, receipt, frozen selection and policy must roundtrip exactly.');
assert(isequaln(sourceHashes(saved.Inputs),saved.SourceHashes) && ...
    digestValue(saved.SourceHashes)==saved.OperandSetSHA256 && ...
    digestValue(saved.Identity)==saved.IdentitySHA256, ...
    'sixgr:truth:CSISelectionArchiveChecksum','Readback source hashes changed.');
csv=sixgr.util.csvReadTable(csvPath,'TextType','string');
validateCSV(csv,saved.PublishedCandidates,saved.Candidates,saved.CandidateMatrices);
sixgr.truth.validateCSISelectionQualityArithmetic(saved); % Same direct readback arithmetic.
assert(string(sixgr.util.sha256File(csvPath))==csvSHA && ...
    string(sixgr.util.sha256File(matPath))==matSHA, ...
    'sixgr:truth:CSISelectionArchiveChecksum','Published files changed during readback.');
row.CSISelectionQualityAvailable=true;
row.CSISelectionQualityStatus="archived_private_UE_selection_quality_not_delivery_or_grant";
row.CSISelectionQualityObservationID=string(reference.Identity.ObservationID);
row.CSISelectionQualityIdentitySHA256=identitySHA;
row.CSISelectionQualityOperandSetSHA256=operandSHA;
row.CSISelectionQualityMATFile=string(matRelative);
row.CSISelectionQualityMATFileSHA256=matSHA;
row.CSISelectionQualityCandidatesCSV=string(csvRelative);
row.CSISelectionQualityCandidatesCSVSHA256=csvSHA;
for name=["SelectedRank","SelectedPMI","SelectedPMIComponentsJSON","SelectedMatrixSHA256", ...
        "SelectedObjective_bpsHz","BestReportedRankObjective_bpsHz","BestJointObjective_bpsHz", ...
        "ConditionalPMIRegret_bpsHz","RankRegret_bpsHz","JointRegret_bpsHz", ...
        "SupportCount","CandidateCount","CandidateDomainSHA256","ChannelSHA256", ...
        "PortToPhysicalMatrixSHA256","SelectedWithinJointTie","SelectedWithinReportedRankTie", ...
        "JointTieCount","ReportedRankTieCount","ReferencePlane","Scope","ObjectiveClassification"]
    row.("CSISelectionQuality"+name)=summary.(name);
end
row.CSISelectionQualityLegalRankDomainJSON=arrayJSON(summary.LegalRankDomain);
row.CSISelectionQualityPhysicalPowerUnit=string(policy.PhysicalPowerUnit);
row.CSISelectionQualityPhysicalPowerReferencePlane=string(policy.PhysicalPowerReferencePlane);
row.CSISelectionQualityPowerNormalization=string(policy.PowerNormalization);
row.CSISelectionQualityStatisticallyQualified=false;
row.CSISelectionQualityActualPDSCHPerformanceQualified=false;
row.CSISelectionQualityCQIBLERQualified=false;
row.CSISelectionQualityCRISelectionQualified=false;
end

function validateOwner(row,id,request)
required=["CSISelectionQualityIdentityJSON","CSISelectionQualityObservationID"];
assert(all(ismember(required,string(row.Properties.VariableNames))), ...
    'sixgr:truth:CSISelectionArchiveIdentity','Retain explicit private selection identity on the owning row.');
try
    token=jsondecode(string(row.CSISelectionQualityIdentityJSON));
    match=isequaln(jsonencode(orderfields(token)),jsonencode(orderfields(id)));
catch
    match=false;
end
assert(match,'sixgr:truth:CSISelectionArchiveIdentity','Row identity token differs from the exact scorer identity.');
assert(string(id.RequestSHA256)==sixgr.util.sha256Hex(jsonencode(orderfields(request))), ...
    'sixgr:truth:CSISelectionArchiveIdentity','Frozen request differs from its identity.');
names=string(row.Properties.VariableNames);
for name=string(fieldnames(id)).'
    alias=name;
    switch name
        case "ObservationID", alias="CSISelectionQualityObservationID";
        case "MeasurementID", alias="CSIMeasurementID";
        case "MeasurementDigest", alias="CSIMeasurementDigest";
        case "ConfigurationEpoch", alias="CSIConfigurationEpoch";
        case "ReportConfigID", alias="CSIReportConfigID";
        case "SampleRateHz", alias="ObservationSampleRateHz";
        case "ObservationSHA256", alias="ReceiverObservationSHA256";
        case "MeasurementSlot", alias="Slot";
        case "ResourceOrdinal0", alias="CRI";
        case "RequestSHA256", continue;
    end
    assert(ismember(alias,names),'sixgr:truth:CSISelectionArchiveIdentity', ...
        'The owning row must retain the actual %s identity (%s).',name,alias);
    actual=row.(alias);
    if name=="ResourceID"
        assert(isnumeric(actual) && isscalar(actual) && isfinite(actual) && actual>=0 && actual==fix(actual), ...
            'sixgr:truth:CSISelectionArchiveIdentity','ResourceID must be the actual numeric CSI-RS resource.');
        actual="CSI-RS-"+string(actual);
    end
    if isnumeric(id.(name)) || islogical(id.(name))
        equal=isequaln(actual,id.(name));
    else
        equal=isequaln(string(actual),string(id.(name)));
    end
    assert(equal,'sixgr:truth:CSISelectionArchiveIdentity','Wrong owning %s.',name);
end
% Supplied population fields cannot disappear from the sealed identity.
for name=["RunID","RunTag","RunFolder","ExecutionID","ConfigHash","ScenarioID", ...
        "Seed","RandomSeed","ChannelSeed","NoiseSeed","SweepPointIndex","ConfiguredSNR_dB"]
    if ismember(name,names)
        value=row.(name);
        if (isstring(value) || ischar(value)) && (ismissing(string(value)) || strlength(string(value))==0), continue; end
        if isnumeric(value) && isscalar(value) && isnan(value), continue; end
        assert(isfield(id,name),'sixgr:truth:CSISelectionArchiveIdentity', ...
            'Supplied population %s must be included in all scorer operand identities.',name);
    end
end
end

function validateMapAndUnits(ref,noise,policy)
assert(all(isfield(noise,{'NoiseReceipt','NoiseReceiptSHA256','WaveformAmplitudeUnit'})), ...
    'sixgr:truth:CSISelectionArchiveNoiseProvenance', ...
    'An enabled archive must retain the source noise receipt and explicit waveform units.');
assert(all(isfield(ref,{'RawPortToPhysicalMatrix','RawPortToPhysicalMatrixSHA256','TXAmplitudeScale'})), ...
    'sixgr:truth:CSISelectionArchiveSpatialProvenance','Retain raw mapper, its digest and actual TX amplitude.');
B=ref.RawPortToPhysicalMatrix; a=ref.TXAmplitudeScale;
assert(isnumeric(B) && ismatrix(B) && ~isempty(B) && all(isfinite(B),'all') && ...
    string(ref.RawPortToPhysicalMatrixSHA256)==sixgr.phy.mimo.MatrixContract.digest(B) && ...
    isnumeric(a) && isscalar(a) && isfinite(a) && abs(a)>0 && ...
    isequaln(a*B,ref.PortToPhysicalMatrix), ...
    'sixgr:truth:CSISelectionArchiveSpatialProvenance','Effective map must be the exact applied amplitude times raw map.');
assert(isfield(policy,'PhysicalPowerReferencePlane') && ...
    string(policy.PhysicalPowerReferencePlane)=="raw_native_grid_physical_chain_coefficient_power" && ...
    isfield(policy,'PhysicalPowerUnit') && any(string(policy.PhysicalPowerUnit)== ...
    ["mW_scaled_grid_coefficient_squared_units","normalized_grid_coefficient_squared_units"]), ...
    'sixgr:truth:CSISelectionArchivePowerPlane','Declare raw-grid coefficient power, not waveform-average power or TRP.');
expected="normalized_grid_coefficient_squared_units";
if string(noise.WaveformAmplitudeUnit)=="sqrt_mW", expected="mW_scaled_grid_coefficient_squared_units"; end
assert(any(string(noise.WaveformAmplitudeUnit)==["sqrt_mW","normalized_complex_baseband"]) && ...
    string(policy.PhysicalPowerUnit)==expected, ...
    'sixgr:truth:CSISelectionArchivePowerPlane','Power units disagree with executed waveform/noise units.');
assert(string(noise.NoiseReceiptSHA256)==sixgr.util.sha256Hex(jsonencode(noise.NoiseReceipt)), ...
    'sixgr:truth:CSISelectionArchiveChecksum','Retained noise receipt digest is invalid.');
receiptIdentityFields=["ReceiverID","ReceiverClockDomain","ReceiverClockEpoch", ...
    "ObservationStartSample","ObservationEndSampleExclusive","SampleRateHz"];
if isfield(ref.Identity,'ReceiverWindowID')
    receiptIdentityFields=[receiptIdentityFields,"ReceiverWindowID"];
end
for name=receiptIdentityFields
    assert(isfield(noise.NoiseReceipt,name) && ...
        sameIdentityValue(noise.NoiseReceipt.(name),ref.Identity.(name)), ...
        'sixgr:truth:CSISelectionArchiveIdentity','Noise receipt differs from actual %s.',name);
end
if isfield(noise.NoiseReceipt,'ValidatedNoiseRecord')
    r=noise.NoiseReceipt.ValidatedNoiseRecord;
    assert(isequal(r.InjectedSampleNoiseVariance,noise.SampleNoiseVariance) && ...
        isequal(r.NoiseStreamSeed,noise.NoiseStreamSeed) && ...
        isequal(noise.NoiseReceipt.NativeOFDM.SampleToGridNoiseVarianceGain,noise.SampleToGridNoiseVarianceGain), ...
        'sixgr:truth:CSISelectionArchiveNoiseClosure','Scored noise must equal the retained execution/FFT receipt.');
end
end

function equal=sameIdentityValue(a,b)
if isnumeric(b) || islogical(b), equal=isequaln(a,b);
else, equal=isequaln(string(a),string(b)); end
end

function matrices=candidateMatrices(T,request)
matrices=cell(height(T),1);
for rank=unique(T.Rank).'
    r=request; r.Rank=rank; domain=sixgr.phy.mimo.CodebookEngine.enumerate(r);
    for k=find(T.Rank==rank).'
        at=find(domain.CandidateIndices==T.PMI(k));
        assert(isscalar(at),'sixgr:truth:CSISelectionArchiveCandidate','Each candidate must identify one legal matrix.');
        W=domain.Matrices(:,:,at);
        assert(sixgr.phy.mimo.MatrixContract.digest(W)==T.MatrixSHA256(k), ...
            'sixgr:truth:CSISelectionArchiveCandidate','Candidate matrix identity disagrees.');
        matrices{k}=W;
    end
end
end

function T=candidateCSV(candidates,matrices,id,summary,identitySHA,operandSHA,policy)
T=removevars(candidates,{'SupportObjective_bpsHz','LayerSINR'}); n=height(T);
T.SupportObjectiveJSON=strings(n,1); T.LayerSINRJSON=strings(n,1); T.CandidateMatrixJSON=strings(n,1);
for k=1:n
    T.SupportObjectiveJSON(k)=arrayJSON(candidates.SupportObjective_bpsHz{k});
    T.LayerSINRJSON(k)=arrayJSON(candidates.LayerSINR{k});
    T.CandidateMatrixJSON(k)=sixgr.phy.mimo.MatrixContract.serialize(matrices{k});
end
for name=string(fieldnames(id)).'
    assert(~ismember(name,string(T.Properties.VariableNames)),'sixgr:truth:CSISelectionArchiveMetadataCollision', ...
        'Identity must not overwrite candidate data: %s.',name);
    value=id.(name); if ischar(value), value=string(value); end
    assert(isscalar(value),'sixgr:truth:CSISelectionArchiveIdentity','Identity metadata must be scalar.');
    T.(name)=repmat(value,n,1);
end
T.CSISelectionQualityObservationID=repmat(string(id.ObservationID),n,1);
T.IdentitySHA256=repmat(identitySHA,n,1); T.OperandSetSHA256=repmat(operandSHA,n,1);
T.ReferencePlane=repmat(summary.ReferencePlane,n,1);
T.Scope=repmat(summary.Scope,n,1);
T.ObjectiveClassification=repmat(summary.ObjectiveClassification,n,1);
T.CandidateDomainSHA256=repmat(summary.CandidateDomainSHA256,n,1);
T.ChannelSHA256=repmat(summary.ChannelSHA256,n,1);
T.PortToPhysicalMatrixSHA256=repmat(summary.PortToPhysicalMatrixSHA256,n,1);
T.SupportJSON=repmat(arrayJSON(summary.Support),n,1);
T.PhysicalPowerReferencePlane=repmat(string(policy.PhysicalPowerReferencePlane),n,1);
T.PhysicalPowerUnit=repmat(string(policy.PhysicalPowerUnit),n,1);
T.PowerNormalization=repmat(string(policy.PowerNormalization),n,1);
T.StatisticallyQualified=false(n,1);
T.EvidenceRole=repmat("private_UE_selection_quality_not_UCI_delivery_or_applied_grant",n,1);
end

function token=arrayJSON(value)
assert(isnumeric(value) && isreal(value) && all(isfinite(value),'all'), ...
    'sixgr:truth:CSISelectionArchiveArray','Only complete finite real candidate arrays are serializable.');
token=string(jsonencode(struct('Contract',"sixgr_real_array_column_major/v1", ...
    'Class',string(class(value)),'Shape',size(value),'ColumnMajorValues',value(:).', ...
    'SHA256',digestValue(value))));
decoded=decodeArray(token);
assert(isequaln(decoded,value),'sixgr:truth:CSISelectionArchiveArray','JSON must preserve every value and dimension exactly.');
end

function value=decodeArray(token)
p=jsondecode(token);
assert(string(p.Contract)=="sixgr_real_array_column_major/v1" && ...
    any(string(p.Class)==["double","single"]), ...
    'sixgr:truth:CSISelectionArchiveArray','Unknown candidate array representation.');
value=reshape(cast(p.ColumnMajorValues,char(p.Class)),double(p.Shape(:).'));
assert(digestValue(value)==string(p.SHA256),'sixgr:truth:CSISelectionArchiveChecksum','Candidate array hash differs.');
end

function validateCSV(actual,expected,candidates,matrices)
assert(isequal(actual.Properties.VariableNames,expected.Properties.VariableNames) && height(actual)==height(expected), ...
    'sixgr:truth:CSISelectionArchiveCSVClosure','Preserve complete candidate rows and columns.');
for name=string(expected.Properties.VariableNames)
    a=actual.(name); b=expected.(name);
    if isnumeric(b) || islogical(b)
        equal=isequaln(sixgr.truth.numericMeasurementColumn(a,name),double(b));
    else
        equal=isequaln(string(a),string(b));
    end
    assert(equal,'sixgr:truth:CSISelectionArchiveCSVClosure','Candidate CSV differs at %s.',name);
end
for k=1:height(actual)
    assert(isequaln(decodeArray(actual.SupportObjectiveJSON(k)),candidates.SupportObjective_bpsHz{k}) && ...
        isequaln(decodeArray(actual.LayerSINRJSON(k)),candidates.LayerSINR{k}) && ...
        isequaln(sixgr.phy.mimo.MatrixContract.deserialize(actual.CandidateMatrixJSON(k)),matrices{k}), ...
        'sixgr:truth:CSISelectionArchiveCSVClosure','Preserve per-support/per-layer operands, never their mean alone.');
end
end


function hashes=sourceHashes(inputs)
hashes=struct();
for name=string(fieldnames(inputs)).', hashes.(name+"SHA256")=digestValue(inputs.(name)); end
end

function hash=digestValue(value)
hash=sixgr.truth.csiSelectionArchiveDigest(value);
end
