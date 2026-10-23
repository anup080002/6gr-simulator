function T=collectCSIReportDeliveryEvidence(reports)
%COLLECTCSIREPORTDELIVERYEVIDENCE Exact post-hoc serialized/decoded comparison.
% One audit row per actual received report, including unavailable evidence.
% NaN correctness is unscorable, not failure. No rank/PMI optimality, CQI
% calibration, false-alarm, or grant-application claim follows from equality.
% Never call this helper from a receiver or scheduler decision path.
arguments
    reports table
end
p=struct('ReportSourceRow',NaN,'ReportIdentity',"",'ObservationID',"", ...
    'UEIndex',NaN,'RNTI',NaN,'ServingCell',NaN,'CSIReportConfigID',"", ...
    'CSIConfigurationEpoch',NaN,'DueSlot',NaN,'DeliveredSlot',NaN, ...
    'UCITransport',"",'TransmissionID',"",'CodebookType',"", ...
    'SpecificationProfile',"",'SpecificationJSON',"",'TXSchemaSHA256',"",'RXSchemaSHA256',"", ...
    'EmissionVerified',false,'DecodeAccepted',false,'DeliveredToScheduler',false, ...
    'EmissionEvidence',"",'ReferenceAttributionQualified',false, ...
    'PopulationScopeComplete',false,'PopulationIdentityStatus',"unbound_component_lifecycle", ...
    'PopulationIdentityJSON',"", ...
    'BitComparisonAvailable',false,'ComparedBitCount',NaN,'BitErrorCount',NaN, ...
    'ReportBitsCorrect',NaN,'CQIDeliveryCorrect',NaN,'RIDeliveryCorrect',NaN, ...
    'PMIDeliveryCorrect',NaN,'CRIDeliveryCorrect',NaN, ...
    'TXCQIJSON',"",'RXCQIJSON',"",'TXRIJSON',"",'RXRIJSON',"", ...
    'TXPMIJSON',"",'RXPMIJSON',"",'TXCRIJSON',"",'RXCRIJSON',"", ...
    'TransmittedFieldCount',0,'CQITransmitted',false,'RITransmitted',false, ...
    'PMITransmitted',false,'CRITransmitted',false, ...
    'FieldComparisonCount',0,'CorrectFieldCount',0,'DeliveredFieldCount',0, ...
    'CorrectDeliveredFieldCount',0,'DecodedProjectionConsistent',NaN, ...
    'DecodedProjectionStatus',"not_evaluated", ...
    'EvidenceStatus',"missing_executed_TX_serialization_audit", ...
    'EvidenceScope',"posthoc_field_delivery_not_CSI_optimality", ...
    'ReportSourceArtifact',"air_interface/csv/received_csi_reports.csv");
T=struct2table(repmat(p,0,1));
for k=1:height(reports)
    r=table2struct(reports(k,:)); out=p; out.ReportSourceRow=k;
    for field=["ReportIdentity","ObservationID","UEIndex","RNTI","ServingCell", ...
            "CSIReportConfigID","CSIConfigurationEpoch","DueSlot","DeliveredSlot"]
        if isfield(r,field), out.(field)=r.(field); end
    end
    out.UCITransport=string(sixgr.util.structGet(r,'CSIUCIChannel',""));
    out.DecodeAccepted=flag(r,'CSIUCIDecodeOk');
    out.DeliveredToScheduler=out.DecodeAccepted && ...
        string(sixgr.util.structGet(r,'DeliveryStatus',""))=="delivered_to_runtime_scheduler";
    out=evaluate(out,r);
    T=[T;struct2table(out,'AsArray',true)]; %#ok<AGROW>
end
T=preservePopulationContext(T,reports);
end

function T=preservePopulationContext(T,reports)
% Row-local scoring does not authorize pooling identical report/observation
% IDs from different executions. Retain caller-supplied grouping, provenance
% and receiver-clock columns verbatim, including their original MATLAB types.
% No execution ID is invented. RunFolder is a valid explicitly supplied scope.
% Only metadata crosses this boundary, never arbitrary private TX payloads.
names=string(reports.Properties.VariableNames);
known=["ScenarioID","ConfigHash","RunTag","RunID","RunUUID","ExecutionID", ...
    "RunFolder","SourceConfigHash","SourceCodeHash","CodeVersion","GitHash", ...
    "Seed","SeedBase","RandomSeed","TrialSeed","DropSeed","ChannelSeed","NoiseSeed", ...
    "SweepPointIndex","ConfiguredSNR_dB","PointIndex","PointLabel","PointSNR_dB", ...
    "SourceCSV","SourceFile","SourceFolder","SourcePath","SourceArtifact","SourceRow", ...
    "ReportSourceArtifact","ReceiverContextDigest","ReceiverClockEpoch","ReceiverClockDomain", ...
    "ObservationStartSample","ObservationEndSampleExclusive","ObservationSampleRateHz", ...
    "AvailableAtSample"];
% Generic joint-sweep wrappers and future explicitly named population keys
% are metadata. Do not broaden this to every input field or private JSON.
keep=ismember(names,known) | startsWith(names,["Sweep","Population","Point"]) | endsWith(names,"Seed");
for name=names(keep)
    if ~ismember(name,known) && ismember(name,string(T.Properties.VariableNames))
        assert(isequaln(T.(name),reports.(name)), ...
            'sixgr:report:CSIDeliveryMetadataCollision', ...
            'Supplied population metadata cannot overwrite derived evidence: %s.',name);
    end
    T.(name)=reports.(name);
end
% Preserve an upstream local ordinal without overwriting this input table's
% freshly assigned ReportSourceRow or silently discarding the upstream one.
if ismember("ReportSourceRow",names)
    if ismember("InputReportSourceRow",names)
        assert(isequaln(reports.ReportSourceRow,reports.InputReportSourceRow), ...
            'sixgr:report:CSIDeliverySourceRowCollision', ...
            'Conflicting source-row metadata needs an explicit caller namespace.');
    end
    T.InputReportSourceRow=reports.ReportSourceRow;
end
end

function out=evaluate(out,r)
token=string(sixgr.util.structGet(r,'CSIDeliveryAuditJSON',""));
if ~isscalar(token) || ismissing(token) || strlength(token)==0, return; end
try
    a=jsondecode(token);
    assert(isstruct(a) && isscalar(a) && isfield(a,'AuditSHA256'));
    digest=string(a.AuditSHA256); payload=rmfield(a,'AuditSHA256');
    assert(digest==sixgr.l2.mac.MACHash.of(orderfields(payload)));
    assert(string(a.Schema)=="sixgr.csi_delivery_audit/v1" && ...
        string(a.Source)=="executed_PUCCH_serialization_posthoc_not_receiver_input" && ...
        string(a.Scope)=="single_configured_CSI_report_per_PUCCH");
catch
    out.EvidenceStatus="invalid_or_corrupt_TX_serialization_audit"; return;
end
identity=["Direction","UEIndex","RNTI","ServingCell","ReportIdentity", ...
    "CSIReportConfigID","CSIConfigurationEpoch","CSIReferenceSlot","DueSlot", ...
    "ObservationID","ReceiverClockEpoch","ObservationSampleRateHz", ...
    "ObservationStartSample","ObservationEndSampleExclusive","AvailableAtSample"];
out.EvidenceStatus="mismatched_report_observation_or_configuration_identity";
if ~isfield(a,'Identity') || ~all(isfield(r,cellstr(identity))) || ...
        ~all(isfield(a.Identity,cellstr(identity))), return; end
for field=identity
    if ~sameScalar(r.(field),a.Identity.(field)), return; end
end
[populationMatches,out.PopulationScopeComplete,out.PopulationIdentityJSON]=populationIdentity(a,r);
if ~populationMatches
    out.PopulationIdentityStatus="mismatched_supplied_population_context";
    out.EvidenceStatus="mismatched_supplied_population_context"; return;
end
if out.PopulationScopeComplete
    out.PopulationIdentityStatus="matched_supplied_receiver_completion_population";
end
try
    ti=a.TransmissionIdentity;
    assert(string(ti.TransmissionID)==sixgr.l2.mac.MACHash.of(orderfields(rmfield(ti,'TransmissionID'))));
    assert(string(ti.ObservationID)==string(r.ObservationID) && ti.UEIndex==r.UEIndex && ...
        ti.RNTI==r.RNTI && ti.RFConfigurationEpoch==r.ReceiverClockEpoch && ...
        ti.SampleRateHz==r.ObservationSampleRateHz && ...
        a.FirstActiveSample>=ti.StartSample && a.FirstActiveSample<ti.EndSampleExclusive && ...
        a.CommittedAtSample==a.FirstActiveSample+1 && a.CommittedAtSample<=r.AvailableAtSample && ...
        ti.EndSampleExclusive<=r.AvailableAtSample && ...
        r.ObservationStartSample<r.ObservationEndSampleExclusive && ...
        r.ObservationEndSampleExclusive<=r.AvailableAtSample && ...
        string(r.ReceiverClockDomain)=="shared_receiver_sample_clock/v1" && out.UCITransport=="PUCCH");
catch
    out.EvidenceStatus="invalid_execution_receipt_or_clock"; return;
end

out.EmissionVerified=true; out.TransmissionID=string(ti.TransmissionID);
out.EmissionEvidence="committed_TX_start_and_completed_receiver_clock_after_TX_end";
out.SpecificationProfile=string(a.SpecificationProfile);
out.SpecificationJSON=string(sixgr.util.structGet(a,'SpecificationJSON',""));
out.TXSchemaSHA256=string(a.TXSchemaSHA256); out.RXSchemaSHA256=string(a.RXSchemaSHA256);
try
    assert(out.TXSchemaSHA256==sixgr.l2.mac.MACHash.of(string(a.TXSchemaJSON)) && ...
        out.RXSchemaSHA256==sixgr.l2.mac.MACHash.of(string(a.RXSchemaJSON)) && ...
        out.TXSchemaSHA256==out.RXSchemaSHA256);
    txRequest=readSchema(a.TXSchemaJSON); rxRequest=readSchema(a.RXSchemaJSON);
    txSchema=sixgr.phy.mimo.CSIReportConfiguration(txRequest,r.CSIConfigurationEpoch);
    rxSchema=sixgr.phy.mimo.CSIReportConfiguration(rxRequest,r.CSIConfigurationEpoch);
    assert(txSchema.ReportConfigID==string(r.CSIReportConfigID) && ...
        rxSchema.ReportConfigID==string(r.CSIReportConfigID) && ...
        txSchema.SpecificationProfile==out.SpecificationProfile && ...
        rxSchema.SpecificationProfile==out.SpecificationProfile && ...
        txSchema.UCIChannel==out.UCITransport && rxSchema.UCIChannel==out.UCITransport);
    assert(out.SpecificationJSON==string(jsonencode(sixgr.phy.mimo.MIMOSpecificationProfile().asStruct())));
    out.CodebookType=txSchema.CodebookType;
catch
    out.EvidenceStatus="missing_mismatched_or_unsupported_codebook_schema"; return;
end
try
    t1=readBits(a.TXPart1BitsToken,a.TXPart1BitCount);
    t2=readBits(a.TXPart2BitsToken,a.TXPart2BitCount);
    tx=txSchema.decode(t1,t2);
    [~,resolvedTX]=txSchema.decodePart1(t1);
catch
    out.EvidenceStatus="invalid_transmitted_serialization"; return;
end
names=[resolvedTX.Part1Fields resolvedTX.Part2Fields];
widths=[resolvedTX.Part1Widths resolvedTX.Part2Widths];
for field=["CQI","RI","PMI","CRI"]
    owned=names==field;
    if field=="CQI", owned=startsWith(names,"CQI_"); end
    if field=="PMI", owned=startsWith(names,"PMI"); end
    out.(field+"Transmitted")=any(owned & widths>0);
    out.TransmittedFieldCount=out.TransmittedFieldCount+double(out.(field+"Transmitted"));
end
if ~out.DecodeAccepted
    out.EvidenceStatus="transmitted_but_receiver_did_not_accept_CSI"; return;
end
try
    r1=readBits(r.CSIPart1BitsToken,r.CSIPart1BitCount);
    r2=readBits(r.CSIPart2BitsToken,r.CSIPart2BitCount);
    decoded=readBits(r.CSIUCIDecodedBitsToken,r.CSIUCIDecodedBitCount);
    assert(isequal(decoded,[r1;r2]) && r.CSIUCIBitCount==numel(decoded));
    rx=rxSchema.decode(r1,r2);
catch
    out.EvidenceStatus="invalid_or_missing_receiver_decoded_serialization"; return;
end
if numel(t1)==numel(r1) && numel(t2)==numel(r2)
    out.BitComparisonAvailable=true; out.ComparedBitCount=numel(t1)+numel(t2);
    out.BitErrorCount=nnz([t1;t2]~=[r1;r2]);
    out.ReportBitsCorrect=double(out.BitErrorCount==0);
end
% Decode only actual bit operands. Field width zero means configured/implied
% semantics (e.g. RI=1 on one port), not a transmitted field trial.
for field=["CQI","RI","PMI","CRI"]
    if ~out.(field+"Transmitted"), continue; end
    txValue=fieldValue(tx,field); rxValue=fieldValue(rx,field);
    if isempty(fieldnames(txValue)) || isempty(fieldnames(rxValue)), continue; end
    out.("TX"+field+"JSON")=string(jsonencode(orderfields(txValue)));
    out.("RX"+field+"JSON")=string(jsonencode(orderfields(rxValue)));
    out.(field+"DeliveryCorrect")=double(isequaln(txValue,rxValue));
    out.FieldComparisonCount=out.FieldComparisonCount+1;
    out.CorrectFieldCount=out.CorrectFieldCount+out.(field+"DeliveryCorrect");
end
[projectionOK,out.DecodedProjectionStatus]=projectionMatches(r,rx);
out.DecodedProjectionConsistent=double(projectionOK);
if out.DeliveredToScheduler
    out.DeliveredFieldCount=out.FieldComparisonCount;
    out.CorrectDeliveredFieldCount=out.CorrectFieldCount;
end
out.EvidenceStatus="exact_transmitted_vs_decoded_field_comparison";
if out.DecodedProjectionConsistent~=1
    % A poisoned exported projection cannot qualify delivered-field metrics.
    out.DeliveredFieldCount=0; out.CorrectDeliveredFieldCount=0;
    out.EvidenceStatus="decoded_projection_not_verified";
end
end

function [matches,complete,token]=populationIdentity(a,r)
population=sixgr.util.structGet(a,'PopulationIdentity',struct());
matches=isstruct(population) && isscalar(population); complete=false; token="";
if ~matches, return; end
token=string(jsonencode(population));
fields=["RunID","RunTag","RunFolder","ExecutionID","ConfigHash","ScenarioID", ...
    "RandomSeed","ChannelSeed","SweepPointIndex","ConfiguredSNR_dB","PopulationIdentitySource"];
for field=fields
    supplied=isfield(r,field) && populated(r.(field));
    sealed=isfield(population,field) && populated(population.(field));
    if supplied~=sealed || (supplied && ~sameScalar(r.(field),population.(field)))
        matches=false; return;
    end
end
% A distinct supplied run folder can scope an execution without manufacturing
% a global ID. A local observation/epoch alone is not a complete lifecycle.
required=["RunID","ConfigHash","ScenarioID","RandomSeed","ChannelSeed", ...
    "SweepPointIndex","ConfiguredSNR_dB"];
complete=all(isfield(population,cellstr(required))) && ...
    ((isfield(population,'ExecutionID') && populated(population.ExecutionID)) || ...
    (isfield(population,'RunFolder') && populated(population.RunFolder)));
if complete
    for field=required, complete=complete && populated(population.(field)); end
    complete=complete && ~isempty(regexp(char(string(population.ConfigHash)),'^[0-9a-fA-F]{64}$','once'));
end
end

function yes=populated(value)
if isnumeric(value)||islogical(value)
    yes=isscalar(value) && isfinite(value);
elseif ischar(value)||isstring(value)
    value=string(value);
    yes=isscalar(value) && ~ismissing(value) && strlength(strtrim(value))>0;
else
    yes=false;
end
end

function request=readSchema(token)
request=jsondecode(string(token));
% JSON arrays have no orientation; these codec fields are specified rows.
for name=["AllowedRanks","NonzeroCoefficientCount"]
    if isfield(request,name), request.(name)=reshape(request.(name),1,[]); end
end
end

function bits=readBits(token,count)
bits=sixgr.runtime.RawCSVArrayCodec.decode(string(token));
assert((isnumeric(bits)||islogical(bits)) && isreal(bits) && ...
    (isvector(bits)||isempty(bits)) && all(bits(:)==0 | bits(:)==1) && ...
    isnumeric(count) && isscalar(count) && isfinite(count) && count==numel(bits));
bits=int8(bits(:));
end

function values=fieldValue(decoded,field)
values=struct(); names=string(fieldnames(decoded));
switch field
    case "CQI", keep=names(startsWith(names,"CQI_"));
    case "PMI"
        keep=names(startsWith(names,"PMI"));
        if ~isempty(keep) && isfield(decoded,'RI'), keep=["RI";keep(:)]; end
    otherwise, keep=names(names==field);
end
for name=reshape(keep,1,[]), values.(name)=decoded.(name); end
values=orderfields(values);
end

function [matches,status]=projectionMatches(r,decoded)
matches=true;
status="scalar_projection_matches_decoded_wire_fields";
for field=["CQI","RI","PMI","CRI","LI","PMI_I11","PMI_I12","PMI_I13","PMI_I2"]
    source=field; if field=="CQI", source="CQI_CW0"; end
    if isfield(decoded,source)
        matches=matches && isfield(r,field) && sameScalar(r.(field),decoded.(source));
    end
end
if ~matches
    status="scalar_projection_disagrees_with_decoded_wire_fields"; return;
end
typeII=isfield(decoded,'PMIComponents') || isfield(decoded,'Precoder_W');
if typeII
    % Type-II has no scalar or Type-I tuple projection. A fabricated scalar
    % must not qualify merely because the real wire representation omits it.
    for field=["PMI","PMI_I11","PMI_I12","PMI_I13","PMI_I2"]
        if ~isfield(r,field) || ~isnumeric(r.(field)) || ...
                ~isscalar(r.(field)) || ~isnan(r.(field))
            matches=false; status="typeII_has_invalid_scalar_PMI_projection"; return;
        end
    end
end
rawToken=sixgr.util.structGet(r,'DecodedCSIFieldsJSON',"");
if ~((isstring(rawToken) && isscalar(rawToken)) || ...
        (ischar(rawToken) && (isrow(rawToken) || isempty(rawToken))))
    matches=false; status="invalid_or_mismatched_complete_decoded_projection"; return;
end
token=string(rawToken);
present=~ismissing(token) && strlength(strtrim(token))>0;
if ~present
    if typeII || isfield(decoded,'CQI_CW1')
        matches=false; status="missing_complete_decoded_field_projection";
    end
    return; % Preserve supported scalar-only Type-I projection evidence.
end
try
    actual=jsondecode(token);
    expected=jsondecode(sixgr.phy.mimo.encodeCSIReportAudit(decoded));
    assert(isstruct(actual) && isscalar(actual));
    if isfield(decoded,'Precoder_W')
        % Compare the complex matrix, not JSON spelling or lossy real-only
        % serialization. This audit is not the scheduler's matrix authority:
        % the scheduler reconstructs Type-II from received Part-1/Part-2 bits.
        assert(all(isfield(actual,{'PrecoderMatrixToken','PrecoderMatrixSHA256'})));
        W=sixgr.phy.mimo.MatrixContract.deserialize(string(actual.PrecoderMatrixToken), ...
            ExpectedDigest=string(actual.PrecoderMatrixSHA256));
        assert(isequal(W,double(decoded.Precoder_W)) && ...
            string(actual.PrecoderMatrixSHA256)==string(expected.PrecoderMatrixSHA256));
        actual=rmfield(actual,{'PrecoderMatrixToken','PrecoderMatrixSHA256'});
        expected=rmfield(expected,{'PrecoderMatrixToken','PrecoderMatrixSHA256'});
    end
    % Both operands pass through the same JSON representation, preserving
    % semantic array shape while ignoring object-key order and whitespace.
    % This checks all components, counts, LI/CQI codewords and schema identity.
    assert(sameDecodedProjection(actual,expected));
catch
    matches=false; status="invalid_or_mismatched_complete_decoded_projection"; return;
end
status="complete_projection_matches_decoded_wire_fields";
end

function yes=sameDecodedProjection(a,b)
if isstruct(a) && isstruct(b)
    yes=isequal(size(a),size(b)) && isequal(sort(fieldnames(a)),sort(fieldnames(b)));
    if ~yes, return; end
    names=fieldnames(a);
    for k=1:numel(a)
        for j=1:numel(names)
            if ~sameDecodedProjection(a(k).(names{j}),b(k).(names{j}))
                yes=false; return;
            end
        end
    end
elseif iscell(a) && iscell(b)
    yes=isequal(size(a),size(b));
    if ~yes, return; end
    for k=1:numel(a)
        if ~sameDecodedProjection(a{k},b{k}), yes=false; return; end
    end
else
    yes=isequaln(a,b);
end
end

function yes=sameScalar(a,b)
if (isnumeric(a)||islogical(a)) && (isnumeric(b)||islogical(b))
    yes=isscalar(a) && isscalar(b) && isfinite(a) && isfinite(b) && a==b;
elseif (ischar(a)||isstring(a)) && (ischar(b)||isstring(b))
    a=string(a); b=string(b);
    yes=isscalar(a) && isscalar(b) && ~ismissing(a) && ~ismissing(b) && strlength(a)>0 && a==b;
else
    yes=false;
end
end

function yes=flag(r,name)
value=sixgr.util.structGet(r,name,false);
yes=(isnumeric(value)||islogical(value)) && isscalar(value) && value==1;
end
