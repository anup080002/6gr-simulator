function [ok,declaredExportFixtures]=testCSIReportDeliveryEvidence()
% Arithmetic/schema contract tests, not statistical CSI or full-run evidence.
% Declared receiver bits/ledger fixtures below never enter runtime decisions.
setup6GRSimToolkit('Verbose',false);
[row,a,request,values]=fixture();
before=row; T=score(row);
assert(isequaln(row,before) && T.EmissionVerified && T.DecodeAccepted && ...
    T.BitComparisonAvailable && T.BitErrorCount==0 && T.ReportBitsCorrect==1 && ...
    T.FieldComparisonCount==4 && T.CorrectFieldCount==4 && ...
    T.DeliveredFieldCount==4 && T.CorrectDeliveredFieldCount==4 && ...
    T.DecodedProjectionConsistent==1 && ~T.PopulationScopeComplete);
% Private producer recommendation and beam/rank metadata have no authority.
poison=row; poison.UEReferenceRecordJSON=string(jsonencode(struct( ...
    'CQI',0,'RI',4,'PMI',99,'CRI',7)));
poison.BestBeamIndex=99; poison.Layers=4; poison.RankEstimate=4;
assert(isequaln(T,score(poison)));
% Complete decoded projection, when supplied, must agree with the independently
% decoded wire fields and installed schema. This JSON is not scheduler input.
codec=sixgr.phy.mimo.CSIReportConfiguration(request,request.Epoch);
decoded=codec.decode(sixgr.runtime.RawCSVArrayCodec.decode(row.CSIPart1BitsToken), ...
    sixgr.runtime.RawCSVArrayCodec.decode(row.CSIPart2BitsToken));
full=row; full.DecodedCSIFieldsJSON=sixgr.phy.mimo.encodeCSIReportAudit(decoded);
F=score(full);
assert(F.DecodedProjectionConsistent==1 && F.CorrectDeliveredFieldCount==4 && ...
    F.DecodedProjectionStatus=="complete_projection_matches_decoded_wire_fields");
reordered=full; reordered.DecodedCSIFieldsJSON=string(jsonencode(orderfields(decoded),'PrettyPrint',true));
assert(score(reordered).DecodedProjectionConsistent==1);
for name=["CQI_CW0","RI","PMI","CRI","PMI_I11","ConfigurationEpoch"]
    changed=decoded; changed.(name)=changed.(name)+1;
    bad=full; bad.DecodedCSIFieldsJSON=sixgr.phy.mimo.encodeCSIReportAudit(changed);
    F=score(bad);
    assert(F.ReportBitsCorrect==1 && F.CorrectFieldCount==4 && ...
        F.DecodedProjectionConsistent==0 && F.CorrectDeliveredFieldCount==0);
end
for name=["ReportConfigID","UCIChannel"]
    changed=decoded; changed.(name)="unrelated";
    bad=full; bad.DecodedCSIFieldsJSON=sixgr.phy.mimo.encodeCSIReportAudit(changed);
    assert(score(bad).DecodedProjectionConsistent==0);
end
changed=rmfield(decoded,'RI'); bad=full;
bad.DecodedCSIFieldsJSON=sixgr.phy.mimo.encodeCSIReportAudit(changed);
assert(score(bad).DecodedProjectionConsistent==0);
changed=decoded; changed.ExtraUnboundValue=1;
bad.DecodedCSIFieldsJSON=sixgr.phy.mimo.encodeCSIReportAudit(changed);
assert(score(bad).DecodedProjectionConsistent==0);
bad.DecodedCSIFieldsJSON="malformed"; assert(score(bad).DecodedProjectionConsistent==0);
bad.DecodedCSIFieldsJSON=["first","second"]; assert(score(bad).DecodedProjectionConsistent==0);
bad.DecodedCSIFieldsJSON=17; assert(score(bad).DecodedProjectionConsistent==0);
% CQI error is observable even though its length and semantic domain pass.
wrong=values; wrong.CQI_CW0=values.CQI_CW0-1;
bad=withReceived(row,request,wrong); W=score(bad);
assert(W.CQIDeliveryCorrect==0 && W.RIDeliveryCorrect==1 && ...
    W.PMIDeliveryCorrect==1 && W.CRIDeliveryCorrect==1 && W.BitErrorCount>0 && ...
    W.CorrectDeliveredFieldCount==3);
% Full Type-I components, not scalar PMI versus CRI/beam, define the operand.
[~,wrong]=sixgr.phy.mimo.TypeISinglePanelCodebook.matrix(request,5);
wrong.RI=values.RI; wrong.CQI_CW0=values.CQI_CW0; wrong.CRI=values.CRI;
bad=withReceived(row,request,wrong); W=score(bad);
assert(W.PMIDeliveryCorrect==0 && W.CRIDeliveryCorrect==1 && ...
    contains(W.TXPMIJSON,'PMI_I11') && contains(W.TXPMIJSON,'PMI_I2'));
wrong=values; wrong.CRI=values.CRI-1;
W=score(withReceived(row,request,wrong));
assert(W.CRIDeliveryCorrect==0 && W.PMIDeliveryCorrect==1);
% Same valid integer PMI in a different rank namespace is not PMI agreement.
rankRequest=request; rankRequest.Rank=2;
[~,wrong]=sixgr.phy.mimo.TypeISinglePanelCodebook.matrix(rankRequest,3);
wrong.RI=2; wrong.CQI_CW0=values.CQI_CW0; wrong.CRI=values.CRI;
W=score(withReceived(row,rankRequest,wrong));
assert(W.RIDeliveryCorrect==0 && W.PMIDeliveryCorrect==0);
% Scalar decoded projection can be corrupted independently of the real bits.
bad=row; bad.PMI=99; W=score(bad);
assert(W.PMIDeliveryCorrect==1 && W.DecodedProjectionConsistent==0 && ...
    W.DeliveredFieldCount==0 && W.CorrectDeliveredFieldCount==0);
% Correctly decoded stale CSI is not a scheduler-delivery observation.
bad=row; bad.DeliveryStatus="stale_received_csi_ignored"; W=score(bad);
assert(W.CorrectFieldCount==4 && W.DeliveredFieldCount==0 && ~W.DeliveredToScheduler);
bad=row; bad.CSIUCIDecodeOk=false; bad.CSIUCICRCPass=NaN; W=score(bad);
assert(W.EmissionVerified && ~W.DecodeAccepted && W.TransmittedFieldCount==4 && ...
    W.FieldComparisonCount==0 && isnan(W.CQIDeliveryCorrect));
% Seven-bit CSI has no CRC. Its fixed CRI has zero on-air width and cannot
% count as a correctly delivered field just because the codec infers zero.
shortRequest=request; shortRequest.Ports=2; shortRequest.MaxRank=2;
shortRequest.AllowedRanks=[1 2]; shortRequest.NumCSIResources=1;
shortValues=struct('RI',1,'PMI',1,'CRI',0,'CQI_CW0',7);
bad=withReceived(row,shortRequest,shortValues); shortAudit=a;
shortAudit.TXSchemaJSON=string(jsonencode(orderfields(shortRequest)));
shortAudit.RXSchemaJSON=shortAudit.TXSchemaJSON;
shortAudit.TXSchemaSHA256=sixgr.l2.mac.MACHash.of(shortAudit.TXSchemaJSON);
shortAudit.RXSchemaSHA256=shortAudit.TXSchemaSHA256;
shortAudit.TXPart1BitsToken=bad.CSIPart1BitsToken;
shortAudit.TXPart1BitCount=bad.CSIPart1BitCount;
bad.CSIDeliveryAuditJSON=seal(shortAudit); bad.CSIUCICRCPass=NaN;
W=score(bad);
assert(bad.CSIUCIBitCount==7 && W.FieldComparisonCount==3 && isnan(W.CRIDeliveryCorrect));
for field=["ReportIdentity","ObservationID","CSIReportConfigID"]
    bad=row; bad.(field)="other"; W=score(bad);
    assert(~W.EmissionVerified && W.FieldComparisonCount==0);
end
for field=["UEIndex","RNTI","ServingCell","CSIConfigurationEpoch","DueSlot","ReceiverClockEpoch"]
    bad=row; bad.(field)=bad.(field)+1; assert(~score(bad).EmissionVerified);
end
bad=row; bad.CSIDeliveryAuditJSON=""; assert(score(bad).FieldComparisonCount==0);
bad=row; bad.CSIDeliveryAuditJSON="malformed"; assert(~score(bad).EmissionVerified);
bad=row; damaged=a; damaged.TXPart1BitCount=damaged.TXPart1BitCount+1;
bad.CSIDeliveryAuditJSON=string(jsonencode(damaged)); assert(~score(bad).EmissionVerified);
% Re-sealed contradictory content still fails the underlying count/schema checks.
bad.CSIDeliveryAuditJSON=seal(damaged); assert(score(bad).FieldComparisonCount==0);
damaged=a; changed=request; changed.CodebookMode=2;
damaged.RXSchemaJSON=string(jsonencode(orderfields(changed)));
damaged.RXSchemaSHA256=sixgr.l2.mac.MACHash.of(damaged.RXSchemaJSON);
bad.CSIDeliveryAuditJSON=seal(damaged); W=score(bad);
assert(W.EmissionVerified && W.FieldComparisonCount==0 && ...
    W.EvidenceStatus=="missing_mismatched_or_unsupported_codebook_schema");
% Never substitute producer tokens for absent independently decoded bits.
bad=row; bad.CSIPart1BitsToken=""; assert(score(bad).FieldComparisonCount==0);
bad=row; bad.CSIUCIDecodedBitCount=bad.CSIUCIDecodedBitCount+1;
assert(score(bad).FieldComparisonCount==0);
emptyRows=struct2table(row,'AsArray',true);
assert(isempty(sixgr.report.collectCSIReportDeliveryEvidence(emptyRows([],:))));
% Identical local report/observation/TX identities from two supplied point
% and seed contexts stay as two exact rows, never one pooled observation.
populations=[emptyRows;emptyRows];
populations.ScenarioID=["case-a";"case-b"];
populations.RunFolder=["declared_run_a";"declared_run_b"];
populations.RunID=["run-a";"run-b"]; populations.RunTag=populations.RunID;
populations.ConfigHash=[string(repmat('a',1,64));string(repmat('b',1,64))];
populations.RandomSeed=uint32([101;202]); populations.ChannelSeed=uint32([11;22]);
populations.SweepPointIndex=[1;2]; populations.ConfiguredSNR_dB=[-5;5];
populations.SweepAggregatePointIndex=[7;8];
populations.SweepAggregateLabel=["low";"high"];
populations.SweepAggregateConfiguredSNR_dB=[-5;5];
populations.SweepAggregateSourceCSV=["a/received_csi_reports.csv";"b/received_csi_reports.csv"];
populations.SweepAggregatePointStatus=["completed";"completed"];
populations.PopulationStudyID=["independent-a";"independent-b"];
populations.PopulationIdentitySource=repmat( ...
    "receiver_completion_runtime_context_not_transmission_point_claim",2,1);
populations.ReportSourceRow=[19;29];
populations=sealPopulationRows(populations);
original=populations; preserved=sixgr.report.collectCSIReportDeliveryEvidence(populations);
assert(isequaln(original,populations) && height(preserved)==2 && ...
    all(preserved.EmissionVerified) && all(preserved.PopulationScopeComplete) && ...
    all(preserved.FieldComparisonCount==4) && all(strlength(preserved.TransmissionID)>0) && ...
    preserved.ObservationID(1)==preserved.ObservationID(2) && ...
    preserved.TransmissionID(1)==preserved.TransmissionID(2) && ...
    ~ismember('ExecutionID',preserved.Properties.VariableNames) && ...
    isequal(preserved.ReportSourceRow,[1;2]) && isequal(preserved.InputReportSourceRow,[19;29]));
for field=["ScenarioID","RunFolder","RunID","RunTag","ConfigHash","RandomSeed", ...
        "ChannelSeed","SweepPointIndex","ConfiguredSNR_dB","PopulationStudyID", ...
        "SweepAggregatePointIndex","SweepAggregateLabel","SweepAggregateConfiguredSNR_dB", ...
        "SweepAggregateSourceCSV","SweepAggregatePointStatus", ...
        "PopulationIdentitySource", ...
        "ReceiverClockEpoch","ReceiverClockDomain","ObservationStartSample", ...
        "ObservationEndSampleExclusive","ObservationSampleRateHz","AvailableAtSample"]
    assert(isequaln(preserved.(field),populations.(field)), ...
        'Population/clock metadata must survive unchanged: %s.',field);
end
transplanted=populations;
transplanted.CSIDeliveryAuditJSON(2)=populations.CSIDeliveryAuditJSON(1);
rejected=scoreTable(transplanted);
assert(rejected.EmissionVerified(1) && ~rejected.EmissionVerified(2) && ...
    rejected.FieldComparisonCount(2)==0 && ...
    rejected.EvidenceStatus(2)=="mismatched_supplied_population_context");
wrongSeed=populations; wrongSeed.RandomSeed(1)=uint32(303);
assert(~scoreTable(wrongSeed).EmissionVerified(1));
populations.ExecutionID=["supplied-execution-a";"supplied-execution-b"];
populations=sealPopulationRows(populations);
withExecution=scoreTable(populations);
assert(all(withExecution.EmissionVerified) && ...
    isequal(withExecution.ExecutionID,populations.ExecutionID));
% Optional reuse by the export-only regression; these remain declared test
% operands, not waveform observations or independently collected trials.
declaredExportFixtures=populations;
populations.InputReportSourceRow=[1;2];
reject(@()sixgr.report.collectCSIReportDeliveryEvidence(populations), ...
    'sixgr:report:CSIDeliverySourceRowCollision');
testBuilder();
ok=true;
fprintf('CSI_REPORT_DELIVERY_EVIDENCE_PASS exact_serialization=1 identity_guards=1 full_PMI=1 omission_guard=1 statistical_qualification=0\n');
end

function T=scoreTable(rows)
T=sixgr.report.collectCSIReportDeliveryEvidence(rows);
end

function rows=sealPopulationRows(rows)
for k=1:height(rows)
    a=jsondecode(rows.CSIDeliveryAuditJSON(k));
    a.PopulationIdentity=struct();
    for field=["RunID","RunTag","RunFolder","ExecutionID","ConfigHash","ScenarioID", ...
            "RandomSeed","ChannelSeed","SweepPointIndex","ConfiguredSNR_dB", ...
            "PopulationIdentitySource"]
        if ismember(field,string(rows.Properties.VariableNames))
            a.PopulationIdentity.(field)=rows.(field)(k);
        end
    end
    rows.CSIDeliveryAuditJSON(k)=seal(a);
end
end

function T=score(row)
T=sixgr.report.collectCSIReportDeliveryEvidence(struct2table(row,'AsArray',true));
end

function [row,a,request,values]=fixture()
request=struct('ReportConfigID',"delivery-test",'Epoch',2, ...
    'CodebookType',"typeI-singlePanel",'Ports',4,'Rank',1,'MaxRank',4, ...
    'AllowedRanks',[1 2 4],'ReportQuantity',"cri-ri-pmi-cqi", ...
    'NumCSIResources',8,'FrequencyGranularity',"wideband", ...
    'UCIChannel',"PUCCH",'N1',2,'N2',1,'O1',4,'O2',1,'CodebookMode',1);
[~,values]=sixgr.phy.mimo.TypeISinglePanelCodebook.matrix(request,3);
values.RI=1; values.CQI_CW0=11; values.CRI=6;
row=struct('Direction',"DL",'UEIndex',1,'RNTI',17,'ServingCell',1, ...
    'ReportIdentity',"report-19",'CSIReportConfigID',request.ReportConfigID, ...
    'CSIConfigurationEpoch',2,'CSIReferenceSlot',17,'DueSlot',19,'DeliveredSlot',19, ...
    'ObservationID',"rx-19",'ReceiverClockEpoch',3,'ObservationSampleRateHz',1000, ...
    'ObservationStartSample',80,'ObservationEndSampleExclusive',101, ...
    'ReceiverClockDomain',"shared_receiver_sample_clock/v1",'AvailableAtSample',101, ...
    'CSIUCIChannel',"PUCCH",'CSIUCIDecodeOk',true,'CSIUCICRCPass',NaN, ...
    'DeliveryStatus',"delivered_to_runtime_scheduler");
row=withReceived(row,request,values);
identity=struct();
for field=["Direction","UEIndex","RNTI","ServingCell","ReportIdentity", ...
        "CSIReportConfigID","CSIConfigurationEpoch","CSIReferenceSlot","DueSlot", ...
        "ObservationID","ReceiverClockEpoch","ObservationSampleRateHz", ...
        "ObservationStartSample","ObservationEndSampleExclusive","AvailableAtSample"]
    identity.(field)=row.(field);
end
ti=struct('ObservationID',row.ObservationID,'UEIndex',1,'RNTI',17, ...
    'RFConfigurationEpoch',3,'UCIConfigurationEpoch',2,'AssignmentDigest',"fixture-assignment", ...
    'ReportDigest',"fixture-report",'StartSample',80,'EndSampleExclusive',100,'SampleRateHz',1000);
ti.TransmissionID=sixgr.l2.mac.MACHash.of(orderfields(ti));
schemaJSON=string(jsonencode(orderfields(request)));
a=struct('Schema',"sixgr.csi_delivery_audit/v1", ...
    'Source',"executed_PUCCH_serialization_posthoc_not_receiver_input", ...
    'Scope',"single_configured_CSI_report_per_PUCCH",'Identity',identity, ...
    'TransmissionIdentity',ti,'FirstActiveSample',81,'CommittedAtSample',82, ...
    'TXSchemaJSON',schemaJSON,'RXSchemaJSON',schemaJSON, ...
    'TXSchemaSHA256',sixgr.l2.mac.MACHash.of(schemaJSON), ...
    'RXSchemaSHA256',sixgr.l2.mac.MACHash.of(schemaJSON), ...
    'SpecificationProfile',sixgr.phy.mimo.MIMOSpecificationProfile().ProfileID, ...
    'SpecificationJSON',string(jsonencode(sixgr.phy.mimo.MIMOSpecificationProfile().asStruct())), ...
    'TXPart1BitsToken',row.CSIPart1BitsToken,'TXPart2BitsToken',row.CSIPart2BitsToken, ...
    'TXPart1BitCount',row.CSIPart1BitCount,'TXPart2BitCount',row.CSIPart2BitCount);
row.CSIDeliveryAuditJSON=seal(a);
end

function row=withReceived(row,request,values)
codec=sixgr.phy.mimo.CSIReportConfiguration(request,request.Epoch);
encoded=codec.build(values); decoded=codec.decode(encoded.Part1Bits,encoded.Part2Bits);
row.CSIPart1BitsToken=sixgr.runtime.RawCSVArrayCodec.encode(encoded.Part1Bits);
row.CSIPart2BitsToken=sixgr.runtime.RawCSVArrayCodec.encode(encoded.Part2Bits);
row.CSIPart1BitCount=numel(encoded.Part1Bits); row.CSIPart2BitCount=numel(encoded.Part2Bits);
row.CSIUCIBitCount=row.CSIPart1BitCount+row.CSIPart2BitCount;
row.CSIUCIDecodedBitCount=row.CSIUCIBitCount;
row.CSIUCIDecodedBitsToken=sixgr.runtime.RawCSVArrayCodec.encode([encoded.Part1Bits;encoded.Part2Bits]);
row.CQI=decoded.CQI_CW0;
for field=["RI","PMI","CRI","PMI_I11","PMI_I12","PMI_I13","PMI_I2"]
    row.(field)=double(sixgr.util.structGet(decoded,field,NaN));
end
end

function token=seal(a)
if isfield(a,'AuditSHA256'), a=rmfield(a,'AuditSHA256'); end
a.AuditSHA256=sixgr.l2.mac.MACHash.of(orderfields(a)); token=string(jsonencode(a));
end

function testBuilder()
% Use the production typed selector and generated waveform. The emission
% receipt is an explicitly declared component fixture, not a shared-run result.
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_causal_tdd_connected_feedback_fixture.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,5,1);
carrier=sixgr.phy.grid.makeCarrier(cfg);
ofdm=nrOFDMInfo(carrier);
cfg.lls6g.userContext.RuntimeSlotStartTime_s= ...
    sixgr.phy.frame.slotStartSample(carrier,4,ofdm.SampleRate)/ofdm.SampleRate;
ue=struct('UEID',1,'RNTI',1,'ServingCell',1,'PUCCHCell',1, ...
    'ComponentCarrier',cfg.phy.frame.DefaultIdentity.ScheduledCCID, ...
    'ActiveULBWP',cfg.phy.frame.DefaultIdentity.ULBWPID);
frame=struct('K1',4,'K1Source',"decoded_dci",'PDSCHEndSlot',1,'TargetSlot',5, ...
    'DecodedPRI',0,'PRIFieldWidth',3,'FirstCCE',0,'NumCCE',8, ...
    'PRIProvenance',"declared_component_DCI",'SlotSymbolOwnership',"UUUUUUUUUUUUUU");
request=cfg.phy.csi.reportConfiguration;
values=struct('RI',request.Rank,'PMI',0,'CRI',0,'CQI_CW0',7,'LI',0);
codec=sixgr.phy.mimo.CSIReportConfiguration(request,request.Epoch);
encoded=codec.build(values);
for mode=["selected","omitted","not_requested"]
    omit=mode=="omitted"; noCSI=mode=="not_requested";
    part1=encoded.Part1Bits;
    if omit, part1=int8(ones(20,1)); end
    part2=encoded.Part2Bits;
    if noCSI, part1=int8.empty(0,1); part2=int8.empty(0,1); end
    planned=sixgr.phy.pucch.PUCCHConfigBuilder.planCombined( ...
        cfg,ue,int8([1;0;1;0]),part1,part2,frame);
    bound=sixgr.phy.pucch.PUCCHConfigBuilder.materialize(cfg,planned);
    trial=sixgr.link.runPUCCHWaveformTrial(cfg,'Carrier',carrier, ...
        'Assignment',bound.Assignment,'Report',bound.Report, ...
        'ChannelProfile',sixgr.channel.resolveConcreteProfile(cfg), ...
        'SNR_dB',30,'TimingAdvanceSamples',0,'PrepareOnly',true);
    prepared=trial.PreparedTransmission;
    id=sixgr.truth.preparedPUCCHTransmissionIdentity(prepared,1,"builder-fixture");
    first=find(any(abs(prepared.Tx.Waveform)>0,2),1)-1+prepared.StartSample;
    receipt=struct('Identity',id,'FirstActiveSample',first,'CommittedAtSample',first+1, ...
        'Source',"actual_shared_PUCCH_transmission_started_not_receiver_outcome");
    [r,~,~,~]=fixture();
    r.RNTI=1; r.CSIReportConfigID=request.ReportConfigID; r.CSIConfigurationEpoch=request.Epoch;
    r.DueSlot=5; r.DeliveredSlot=5; r.CSIReferenceSlot=1; r.ObservationID=id.ObservationID;
    r.ReceiverClockEpoch=id.RFConfigurationEpoch; r.ObservationSampleRateHz=id.SampleRateHz;
    r.ObservationStartSample=prepared.ReceiveStartSample;
    r.ObservationEndSampleExclusive=prepared.ReceiveEndSampleExclusive;
    % Declared component completion after both intervals; not a measured
    % shared-runtime timestamp or an assertion of physical RX completion.
    r.AvailableAtSample=max(prepared.EndSampleExclusive,prepared.ReceiveEndSampleExclusive);
    r=withReceived(r,request,values);
    originalReceived=r;
    r.CSIDeliveryAuditJSON=sixgr.truth.buildCSIDeliveryAudit(r,prepared,receipt,request);
    assert(isequaln(rmfield(r,'CSIDeliveryAuditJSON'),rmfield(originalReceived,'CSIDeliveryAuditJSON')), ...
        'Private TX audit must not rewrite the independent receiver outcome.');
    if omit || noCSI
        assert(r.CSIDeliveryAuditJSON=="" && ~score(r).EmissionVerified);
        if noCSI
            assert(isempty(prepared.Tx.Assignment.Data.CSISelection.RequestedReportIDs) && ...
                isempty(prepared.Tx.Report.Data.CSIReports) && ...
                ~any(startsWith(string(prepared.Tx.Serialization.Layout.FieldName),"CSI_")));
        end
    else
        assert(score(r).EmissionVerified && score(r).BitErrorCount==0 && ~score(r).PopulationScopeComplete);
        wrong=receipt; wrong.Identity.TransmissionID="wrong";
        reject(@()sixgr.truth.buildCSIDeliveryAudit(r,prepared,wrong,request), ...
            'sixgr:truth:CSIDeliveryEmissionIdentity');
        wrongSchema=request; wrongSchema.Epoch=request.Epoch+1;
        reject(@()sixgr.truth.buildCSIDeliveryAudit(r,prepared,receipt,wrongSchema), ...
            'sixgr:mimo:StaleCSIReportConfig');
    end
end
end

function reject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingRejection','Expected %s.',id);
end
