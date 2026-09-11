function summary = runPUCCHPhaseValidation(varargin)
%RUNPUCCHPHASEVALIDATION Execute Phase-05 vector and waveform evidence.

p = inputParser;
p.FunctionName = "sixgr.phy.pucch.runPUCCHPhaseValidation";
addParameter(p,"VectorRoot","",@(x) ischar(x)||isstring(x));
addParameter(p,"OutputDir","",@(x) ischar(x)||isstring(x));
addParameter(p,"SeedList",[11 23 47 89],@isnumeric);
addParameter(p,"ConfidenceLevel",0.95,@(x) isnumeric(x)&&isscalar(x));
addParameter(p,"Strict",true,@(x) islogical(x)&&isscalar(x));
addParameter(p,"FastTestMode",false,@(x) islogical(x)&&isscalar(x));
parse(p,varargin{:});
opt = p.Results;
if ~opt.Strict
    error("sixgr:phy:pucch:StrictProfileRequired", ...
        "Phase-05 evidence requires Strict=true.");
end
vectorRoot = string(opt.VectorRoot);
outputDir = string(opt.OutputDir);
if strlength(vectorRoot)==0 || ~isfolder(vectorRoot)
    error("sixgr:phy:pucch:MissingVectorPack", ...
        "VectorRoot must identify the verified PUCCH vector pack.");
end
if strlength(outputDir)==0
    error("sixgr:phy:pucch:MissingEvidenceOutput", ...
        "OutputDir is mandatory.");
end
% Do not publish the legacy phase's hardcoded independent mismatch counts,
% unevaluated DMRS correlation, or selected==applied beam assertions as
% measured evidence. Real standalone receiver trials do not validate these
% other families. Remove this quarantine only with execution-backed
% replacement producers and an aggregate gate covering every family.
error("sixgr:phy:pucch:UnverifiedPhaseEvidence", ...
    "PUCCH Phase-05 qualification is unavailable: independent-vector, " + ...
    "DMRS correlation, hopping comparison and spatial application evidence " + ...
    "are not execution-backed. No phase CSV/PNG has been generated.");
if ~isfolder(outputDir), mkdir(outputDir); end
runID = "PUCCH_PHASE05_R18";
contract = sixgr.phy.pucch.PUCCHUtil.readAllStrings( ...
    fullfile(vectorRoot,"desired_pucch_csv_contract.csv"));
imageContract = sixgr.phy.pucch.PUCCHUtil.readAllStrings( ...
    fullfile(vectorRoot,"desired_pucch_image_contract.csv"));

[tables.pucch_uci_report_resolution,tables.pucch_uci_serialization] = ...
    localReports(contract,runID,vectorRoot);
tables.pucch_uci_coding = localCoding(contract,runID,vectorRoot);
tables.pucch_harq_codebook = localHARQ(contract,runID,vectorRoot);
tables.pucch_sr_events = localSR(contract,runID,vectorRoot);
tables.pucch_csi_reports = localCSI(contract,runID,vectorRoot);
tables.pucch_resource_set_selection = localResourceSets( ...
    contract,runID,vectorRoot);
tables.pucch_resource_indicator_selection = localPRI( ...
    contract,runID,vectorRoot);
[waveformTables,waveformSummary] = localWaveformEvidence( ...
    contract,runID,opt);
tables.pucch_resource_mapping = waveformTables.ResourceMapping;
tables.pucch_dmrs_sequence = waveformTables.DMRS;
tables.pucch_hopping_repetition = waveformTables.Hopping;
tables.pucch_receiver_metrics = waveformTables.ReceiverMetrics;
tables.pucch_bler_curve = waveformTables.BLERCycle;
tables.pucch_false_alarm_trials = waveformTables.FalseAlarm;
tables.pucch_format_matrix = localFormats(contract,runID,vectorRoot);
tables.pucch_timing_k1_tdd = localTiming(contract,runID,vectorRoot);
tables.pucch_collision_resolution = localCollision( ...
    contract,runID,vectorRoot);
tables.pucch_power_control = localPower(contract,runID,vectorRoot);
tables.pucch_spatial_relation = localSpatial(contract,runID,vectorRoot);
tables.pucch_negative_tests = localNegative(contract,runID,vectorRoot);
[tables.pucch_independent_vector_results,tables.pucch_independent_field_comparisons] = ...
    sixgr.phy.pucch.PUCCHIndependentVectorComparison.build(vectorRoot,runID);
tables.pucch_test_summary = localSummary(contract,runID,waveformSummary);

names = string(fieldnames(tables));
rowCounts = struct(); hashes = struct();
for index = 1:numel(names)
    fileName = names(index)+".csv";
    sixgr.phy.pucch.PUCCHArtifactExporter.writeTable( ...
        outputDir,fileName,tables.(names(index)));
    rowCounts.(names(index)) = height(tables.(names(index)));
    hashes.(names(index)) = ...
        sixgr.phy.pucch.PUCCHArtifactExporter.fileSHA256( ...
        fullfile(outputDir,fileName));
end

auditRows = repmat(localAuditRow(),height(imageContract),1);
for index = 1:height(imageContract)
    auditRow = sixgr.phy.pucch.PUCCHArtifactExporter.writeSemanticFigure( ...
        outputDir,table2struct(imageContract(index,:)));
    auditRow.RunID = runID;
    auditRows(index) = orderfields(auditRow,auditRows(index));
end
audit = struct2table(auditRows,"AsArray",true);
audit = movevars(audit,"RunID","Before",1);
sixgr.phy.pucch.PUCCHArtifactExporter.writeTable( ...
    outputDir,"pucch_image_semantic_audit.csv",audit);
rowCounts.pucch_image_semantic_audit = height(audit);
hashes.pucch_image_semantic_audit = ...
    sixgr.phy.pucch.PUCCHArtifactExporter.fileSHA256( ...
    fullfile(outputDir,"pucch_image_semantic_audit.csv"));

expectedCSV = string(contract.FileName);
expectedPNG = string(imageContract.ImageFile);
csvPresent = arrayfun(@(x) exist(fullfile(outputDir,x),"file")==2,expectedCSV);
pngPresent = arrayfun(@(x) exist(fullfile(outputDir,x),"file")==2,expectedPNG);
mismatches = sum(tables.pucch_independent_vector_results.MismatchCount);
allStatusPass=true;
for name=names.'
    t=tables.(name);
    if ismember('Status',t.Properties.VariableNames)
        allStatusPass=allStatusPass&&all(string(t.Status)=="PASS");
    end
end
passed = all(csvPresent)&&all(pngPresent)&&mismatches==0&& ...
    waveformSummary.Failures==0&&allStatusPass;
summary = struct( ...
    "Passed",passed,"Strict",true,"RunID",runID, ...
    "OutputDir",outputDir,"CSVCount",sum(csvPresent), ...
    "PNGCount",sum(pngPresent),"RowCounts",rowCounts, ...
    "CSVHashes",hashes, ...
    "IndependentMismatchCount",mismatches, ...
    "WaveformTrials",waveformSummary.Trials, ...
    "WaveformFailures",waveformSummary.Failures, ...
    "TruthQualified",passed&&~opt.FastTestMode, ...
    "ExecutionBackend","waveform_truth_and_independent_spec_vectors", ...
    "ApproximationMode","none","Status",localStatus(passed));
end

function [reports,serialization] = localReports(contract,runID,root)
input = localRead(root,"pucch_uci_report_test_vectors.csv");
expected = localRead(root,"expected_pucch_uci_serialization.csv");
reports = localTable(contract,"pucch_uci_report_resolution.csv",height(input));
serialization = localTable(contract,"pucch_uci_serialization.csv",0);
for index = 1:height(input)
    actual = sixgr.phy.pucch.UCIReportSerializer.serializeVector(input(index,:));
    harq = strlength(sixgr.phy.pucch.PUCCHUtil.text( ...
        input(index,:),"HARQACKBits",""));
    sr = strlength(sixgr.phy.pucch.PUCCHUtil.text( ...
        input(index,:),"SRBits",""));
    csi1 = strlength(sixgr.phy.pucch.PUCCHUtil.text( ...
        input(index,:),"CSIPart1Bits",""));
    csi2 = strlength(sixgr.phy.pucch.PUCCHUtil.text( ...
        input(index,:),"CSIPart2Bits",""));
    reports.RunID(index)=runID; reports.CaseID(index)=input.CaseID(index);
    reports.ReportType(index)=localReportType(harq,sr,csi1,csi2);
    reports.HARQACKBits(index)=string(harq);
    reports.SRBits(index)=string(sr);
    reports.CSIPart1Bits(index)=string(csi1);
    reports.CSIPart2Bits(index)=string(csi2);
    reports.ConfigurationEpoch(index)=input.ConfigurationEpoch(index);
    reports.ReportProvenance(index)="decoded_configured_procedure_state";
    reports.Status(index)="PASS";
    for sequenceIndex = 1:2
        sequence = actual.Sequences{sequenceIndex};
        expectedBits = sixgr.phy.pucch.PUCCHUtil.bits( ...
            sixgr.phy.pucch.PUCCHUtil.text(expected(index,:), ...
            "Sequence"+sequenceIndex+"Bits",""));
        for bitIndex = 1:numel(sequence.Bits)
            row = localLike(serialization);
            row.RunID=runID; row.CaseID=input.CaseID(index);
            row.SequenceIndex=string(sequenceIndex);
            row.BitIndex=string(bitIndex-1);
            row.BitOwner=sequence.Owners(bitIndex);
            row.FieldName=sequence.FieldNames(bitIndex);
            row.BitValue=string(sequence.Bits(bitIndex));
            row.ExpectedBitValue=string(expectedBits(bitIndex));
            row.Mismatch=localBool(sequence.Bits(bitIndex)~=expectedBits(bitIndex));
            row.Status="PASS";
            serialization=[serialization;row]; %#ok<AGROW>
        end
    end
end
end

function value = localCoding(contract,runID,root)
input = localRead(root,"pucch_uci_coding_test_vectors.csv");
expected = localRead(root,"expected_pucch_uci_coding_plan.csv");
value = localTable(contract,"pucch_uci_coding.csv",height(input));
value.RoundTripExecutionE = repmat("",height(input),1);
value.RoundTripStatus = repmat("",height(input),1);
for index = 1:height(input)
    actual = sixgr.phy.pucch.UCIEncodingPlan.fromVector(input(index,:));
    mismatch = double(actual.Scheme~=expected.Scheme(index))+ ...
        double(actual.CRCBits~=str2double(expected.CRCBits(index)))+ ...
        double(actual.SegmentationExpected~=localTruth( ...
        expected.SegmentationExpected(index)))+ ...
        double(actual.Valid~=localTruth(expected.ExpectedValid(index)));
    roundTripErrors = 0;
    if actual.Valid && actual.A > 0 && actual.E > 0
        executionE = max(actual.E,2048);
        bits = int8(mod((0:actual.A-1).'+index,2));
        sequence = sixgr.phy.pucch.UCISequence(1,bits, ...
            repmat("UCI",actual.A,1), ...
            repmat("independent_coding_round_trip",actual.A,1));
        encoded = sixgr.phy.pucch.UCIEncoder.encode( ...
            sequence,executionE,"QPSK");
        % nrUCIEncode uses negative placeholder tokens for repeated
        % small-block positions. They are erasures at the decoder, not
        % binary values.
        coded = double(encoded.CodedBits(:));
        llr = zeros(size(coded));
        llr(coded==0) = 100;
        llr(coded==1) = -100;
        decoded = sixgr.phy.pucch.UCIDecoder.decode(llr,actual.A);
        common = min(numel(bits),numel(decoded.Bits));
        roundTripErrors = abs(numel(bits)-numel(decoded.Bits)) + ...
            sum(bits(1:common)~=decoded.Bits(1:common));
        mismatch = mismatch + double(roundTripErrors~=0);
        value.RoundTripExecutionE(index)=string(executionE);
        value.RoundTripStatus(index)="executed_production_encoder_decoder";
    elseif actual.A == 0
        value.RoundTripExecutionE(index)="0";
        value.RoundTripStatus(index)="not_applicable_no_payload";
    else
        value.RoundTripExecutionE(index)="";
        value.RoundTripStatus(index)="not_executed_invalid_plan";
    end
    value.RunID(index)=runID; value.CaseID(index)=input.CaseID(index);
    value.A(index)=string(actual.A); value.E(index)=string(actual.E);
    value.CodingScheme(index)=actual.Scheme;
    value.CRCBits(index)=string(actual.CRCBits);
    value.Segmentation(index)=localBool(actual.SegmentationExpected);
    value.CodeBlocks(index)=string(actual.CodeBlocks);
    value.RateMatchingDigest(index)=actual.RateMatchingDigest;
    value.RoundTripBitErrors(index)=string(roundTripErrors);
    value.IndependentMismatchCount(index)=string(mismatch);
    value.Status(index)=localStatus(mismatch==0);
end
end

function value = localHARQ(contract,runID,root)
input=localRead(root,"pucch_harq_codebook_test_vectors.csv");
expected=localRead(root,"expected_pucch_harq_codebook.csv");
value=localTable(contract,"pucch_harq_codebook.csv",0);
for index=1:height(input)
    actual=sixgr.phy.pucch.HARQACKCodebookBuilder.buildVector(input(index,:));
    expectedTokens=char(expected.ExpectedBitTokens(index));
    for bit=1:numel(actual.BitTokens)
        event=actual.Events(bit).Data;
        row=localLike(value); row.RunID=runID; row.CaseID=input.CaseID(index);
        row.CodebookType=actual.CodebookType; row.BitIndex=string(bit-1);
        row.ServingCell=string(event.ServingCell); row.PDSCHID=string(event.PDSCHID);
        row.DAI=string(event.DAI); row.Priority=string(event.Priority);
        row.ACKState=actual.BitTokens(bit); row.ExpectedACKState=string(expectedTokens(bit));
        row.Mismatch=localBool(actual.BitTokens(bit)~=string(expectedTokens(bit)));
        row.Status="PASS"; value=[value;row]; %#ok<AGROW>
    end
end
end

function value = localSR(contract,runID,root)
input=localRead(root,"pucch_sr_test_vectors.csv");
expected=localRead(root,"expected_pucch_sr_occasion.csv");
value=localTable(contract,"pucch_sr_events.csv",height(input));
for index=1:height(input)
    actual=sixgr.phy.pucch.SchedulingRequestState.fromVector(input(index,:));
    mismatch=actual.Data.IsOccasion~=localTruth(expected.IsSROccasion(index))|| ...
        actual.Data.Transmit~=localTruth(expected.TransmitPUCCH(index));
    value.RunID(index)=runID; value.CaseID(index)=input.CaseID(index);
    value.SchedulingRequestID(index)=input.SchedulingRequestID(index);
    value.AbsoluteSlot(index)=input.AbsoluteSlot(index);
    value.IsOccasion(index)=localBool(actual.Data.IsOccasion);
    value.PendingPositiveSR(index)=input.PendingPositiveSR(index);
    value.Transmitted(index)=localBool(actual.Data.Transmit);
    value.ResourceID(index)=string(actual.Data.ResourceID);
    value.Mismatch(index)=localBool(mismatch); value.Status(index)=localStatus(~mismatch);
end
end

function value = localCSI(contract,runID,root)
input=localRead(root,"pucch_csi_report_test_vectors.csv");
expected=localRead(root,"expected_pucch_csi_serialization.csv");
value=localTable(contract,"pucch_csi_reports.csv",0);
for index=1:height(input)
    states=sixgr.phy.pucch.CSIReportBuilder.buildVector(input(index,:));
    reportData=arrayfun(@(x)x.Data,states);
    report=localCSIReport(input.CaseID(index), ...
        str2double(input.ConfigurationEpoch(index)),reportData);
    serialized=sixgr.phy.pucch.UCIReportSerializer.serialize(report);
    exp1=sixgr.phy.pucch.PUCCHUtil.text(expected(index,:), ...
        "ExpectedCSIPart1Bits","");
    exp2=sixgr.phy.pucch.PUCCHUtil.text(expected(index,:), ...
        "ExpectedCSIPart2Bits","");
    mismatch=double(sixgr.phy.pucch.PUCCHUtil.bitString( ...
        serialized.Sequence1.Bits)~=exp1)+ ...
        double(sixgr.phy.pucch.PUCCHUtil.bitString( ...
        serialized.Sequence2.Bits)~=exp2);
    for stateIndex=1:numel(states)
        state=states(stateIndex).Data;
        row=localLike(value); row.RunID=runID; row.CaseID=input.CaseID(index);
        row.ReportID=string(state.ReportID); row.ReportPriority=string(state.Priority);
        row.Part="1"; row.FieldName=join(string(state.Part1FieldNames),"|");
        row.FieldWidth=string(sum(state.Part1Widths)); row.BitOffset="0";
        row.Bits=sixgr.phy.pucch.PUCCHUtil.bitString(state.Part1Bits);
        row.ExpectedBits=row.Bits; row.Mismatch=localBool(mismatch~=0);
        row.Status=localStatus(mismatch==0); value=[value;row]; %#ok<AGROW>
        if ~isempty(state.Part2Bits)
            row.Part="2"; row.FieldName=join(string(state.Part2FieldNames),"|");
            row.FieldWidth=string(sum(state.Part2Widths));
            row.Bits=sixgr.phy.pucch.PUCCHUtil.bitString(state.Part2Bits);
            row.ExpectedBits=row.Bits; value=[value;row]; %#ok<AGROW>
        end
    end
end
end

function value = localResourceSets(contract,runID,root)
input=localRead(root,"pucch_resource_set_test_vectors.csv");
expected=localRead(root,"expected_pucch_resource_selection.csv");
value=localTable(contract,"pucch_resource_set_selection.csv",height(input));
for index=1:height(input)
    actual=sixgr.phy.pucch.PUCCHResourceSetResolver.resolveVector(input(index,:));
    expectedSet=str2double(expected.SelectedSetID(index));
    mismatch=actual.Valid~=localTruth(expected.ExpectedValid(index))|| ...
        ~(isnan(expectedSet)&&isnan(actual.SelectedSetID)|| ...
        expectedSet==actual.SelectedSetID);
    value.RunID(index)=runID; value.CaseID(index)=input.CaseID(index);
    value.OUCI(index)=input.OUCI(index); value.ReportSource(index)=input.ReportSource(index);
    value.SelectedSetID(index)=localNumber(actual.SelectedSetID);
    value.ResourceSource(index)=actual.SelectedResourceSource;
    value.RRCConfigurationEpoch(index)=input.ConfigurationEpoch(index);
    value.SelectionMismatchCount(index)=string(double(mismatch));
    value.DefaultOrHashUsed(index)="false"; value.Status(index)=localStatus(~mismatch);
end
end

function value = localPRI(contract,runID,root)
input=localRead(root,"pucch_resource_indicator_test_vectors.csv");
expected=localRead(root,"expected_pucch_resource_indicator_selection.csv");
value=localTable(contract,"pucch_resource_indicator_selection.csv",height(input));
for index=1:height(input)
    actual=sixgr.phy.pucch.PUCCHResourceIndicatorResolver.resolveVector(input(index,:));
    expectedOrdinal=sixgr.phy.pucch.PUCCHUtil.text( ...
        expected(index,:),"ExpectedOrdinal","");
    mismatch=actual.Valid~=localTruth(expected.ExpectedValid(index));
    if actual.Valid
        if ~isfinite(str2double(expectedOrdinal))
            error("sixgr:phy:pucch:MissingNumericPRIReference", ...
                "PRI validation requires an independent numeric ordinal, not a placeholder.");
        end
        mismatch=mismatch||actual.Ordinal~=str2double(expectedOrdinal);
    end
    value.RunID(index)=runID; value.CaseID(index)=input.CaseID(index);
    value.ResourceSetID(index)=input.ResourceSetID(index);
    value.ResourceListSize(index)=input.ResourceListSize(index);
    value.PRIValue(index)=input.PRIValue(index); value.FirstCCE(index)=input.FirstCCE(index);
    value.NumCCE(index)=input.NumCCE(index);
    value.SelectedResourceOrdinal(index)=localNumber(actual.Ordinal);
    value.ExpectedResourceOrdinal(index)=expectedOrdinal;
    value.MismatchCount(index)=string(double(mismatch)); value.Status(index)=localStatus(~mismatch);
end
end

function value = localFormats(contract,runID,root)
input=localRead(root,"pucch_format_matrix_test_vectors.csv");
expected=localRead(root,"expected_pucch_format_validation.csv");
value=localTable(contract,"pucch_format_matrix.csv",height(input));
for index=1:height(input)
    actual=sixgr.phy.pucch.PUCCHFormatValidator.validateVector(input(index,:));
    expectedError=sixgr.phy.pucch.PUCCHUtil.text( ...
        expected(index,:),"ExpectedErrorID","");
    mismatch=actual.Valid~=localTruth(expected.ExpectedValid(index))|| ...
        actual.ErrorID~=expectedError;
    value.RunID(index)=runID;value.CaseID(index)=input.CaseID(index);
    value.Format(index)=input.Format(index);value.NumSymbols(index)=input.NumSymbols(index);
    value.UCIBits(index)=input.UCIBits(index);value.NumPRBs(index)=input.NumPRBs(index);
    value.Hopping(index)=input.IntraSlotHopping(index);value.Interlaced(index)="false";
    value.RepetitionSlots(index)="1";value.Valid(index)=localBool(actual.Valid);
    value.ExpectedValid(index)=expected.ExpectedValid(index);
    value.ParameterMutated(index)="false";value.ErrorID(index)=actual.ErrorID;
    value.Status(index)=localStatus(~mismatch);
end
end

function value = localTiming(contract,runID,root)
input=localRead(root,"pucch_k1_tdd_test_vectors.csv");
expected=localRead(root,"expected_pucch_timing_resolution.csv");
value=localTable(contract,"pucch_timing_k1_tdd.csv",height(input));
for index=1:height(input)
    actual=sixgr.phy.pucch.PUCCHTimingResolver.resolveVector(input(index,:));
    mismatch=actual.DueSlot~=str2double(expected.ExpectedDueSlot(index))|| ...
        actual.Legal~=localTruth(expected.ExpectedLegal(index));
    value.RunID(index)=runID;value.CaseID(index)=input.CaseID(index);
    value.PDSCHEndSlot(index)=input.PDSCHEndSlot(index);value.K1(index)=input.K1(index);
    value.K1Source(index)="decoded_dci";value.DueSlot(index)=string(actual.DueSlot);
    value.ExpectedDueSlot(index)=expected.ExpectedDueSlot(index);
    value.SlotSymbolOwnership(index)=input.SlotSymbolOwnership(index);
    value.StartSymbol(index)=string(actual.StartSymbol);value.NumSymbols(index)=string(actual.NumSymbols);
    value.SymbolShiftApplied(index)="false";value.Legal(index)=localBool(actual.Legal);
    value.ExpectedLegal(index)=expected.ExpectedLegal(index);value.Status(index)=localStatus(~mismatch);
end
end

function value = localCollision(contract,runID,root)
input=localRead(root,"pucch_collision_test_vectors.csv");
expected=localRead(root,"expected_pucch_collision_resolution.csv");
value=localTable(contract,"pucch_collision_resolution.csv",height(input));
for index=1:height(input)
    actual=sixgr.phy.pucch.PUCCHCollisionResolver.resolveVector(input(index,:));
    mismatch=actual.ResolutionAction~=expected.ExpectedAction(index);
    value.RunID(index)=runID;value.CaseID(index)=input.CaseID(index);
    value.ResourceA(index)=input.ResourceAType(index);value.ResourceB(index)=input.ResourceBType(index);
    value.ExactREOverlap(index)=input.ExactREOverlap(index);
    value.Orthogonal(index)=input.OrthogonalSequence(index);
    value.ResolutionAction(index)=actual.ResolutionAction;
    value.ExpectedAction(index)=expected.ExpectedAction(index);
    value.UnresolvedCollision(index)="false";
    value.StateDigestBefore(index)=sixgr.phy.pucch.PUCCHUtil.hash(input.CaseID(index)+"before");
    value.StateDigestAfter(index)=sixgr.phy.pucch.PUCCHUtil.hash(input.CaseID(index)+"after");
    value.Status(index)=localStatus(~mismatch);
end
end

function value = localPower(contract,runID,root)
% Policy is an explicit component-validation profile, not a main-run override.
repository=fileparts(which('setup6GRSimToolkit'));
profile=fullfile(repository,'simulator','configs','validation','pucch_power_waveform.yaml');
value=sixgr.phy.pucch.PUCCHPowerVectorEvidence.build(root,runID,profile);
end

function value = localSpatial(contract,runID,root)
input=localRead(root,"pucch_spatial_relation_test_vectors.csv");
expected=localRead(root,"expected_pucch_spatial_relation.csv");
value=localTable(contract,"pucch_spatial_relation.csv",height(input));
for index=1:height(input)
    actual=sixgr.phy.pucch.PUCCHSpatialRelationState.resolveVector(input(index,:));
    mismatch=actual.Valid~=localTruth(expected.ExpectedValid(index));
    value.RunID(index)=runID;value.CaseID(index)=input.CaseID(index);
    value.SpatialRelationID(index)=input.RequestedSpatialRelationID(index);
    value.ReferenceSignalType(index)=input.ReferenceSignalType(index);
    value.ReferenceSignalID(index)=input.ReferenceSignalID(index);
    value.PathlossReferenceRSID(index)=localNumber(actual.PathlossReferenceRSID);
    value.P0PUCCHID(index)=input.P0PUCCHID(index);value.ClosedLoopIndex(index)=input.ClosedLoopIndex(index);
    value.StateAgeSlots(index)=string(double(sixgr.phy.pucch.PUCCHUtil.truth( ...
        input(index,:),"StateStale"))*100);
    beam=localBeam(actual.Valid,input.RequestedSpatialRelationID(index));
    value.SelectedBeamID(index)=beam;value.AppliedBeamID(index)=beam;
    value.MismatchCount(index)=string(double(mismatch));value.Status(index)=localStatus(~mismatch);
end
end

function value = localNegative(contract,runID,root)
input=localRead(root,"pucch_negative_test_vectors.csv");
value=localTable(contract,"pucch_negative_tests.csv",height(input));
for index=1:height(input)
    fault=input.FaultType(index); expected=input.ExpectedErrorID(index);
    if fault=="no_signal"
        fixture=localFixture(str2double(input.Format(index)));
        trial=sixgr.link.runPUCCHWaveformTrial(fixture.Carrier, ...
            "Carrier",fixture.Carrier,"Assignment",fixture.Assignment, ...
            "Report",fixture.Report,"ReceiverContext",fixture.Context, ...
            "ChannelProfile","AWGN","SNR_dB",20,"SignalPresent",false, ...
            "DetectionThreshold",0.9,"Seed",9000+index);
        if trial.ReceiverDTX
            observed="DTX_NO_FALSE_ALARM";
        else
            observed="FALSE_ALARM";
        end
        waveform=trial.WaveformGenerated;
        stateChanged=trial.StateChanged;
        grantCreated=trial.GrantCreated;
    else
        executed=sixgr.phy.pucch.PUCCHNegativeCaseExecutor.execute( ...
            fault,str2double(input.Format(index)));
        observed=executed.ObservedErrorID;
        waveform=executed.WaveformGenerated;
        stateChanged=executed.StateChanged;
        grantCreated=executed.GrantCreated;
    end
    value.RunID(index)=runID;value.CaseID(index)=input.CaseID(index);
    value.FaultType(index)=fault;value.ExpectedErrorID(index)=expected;
    value.ObservedErrorID(index)=observed;value.Passed(index)=localBool(observed==expected);
    value.WaveformGenerated(index)=localBool(waveform);
    value.StateChanged(index)=localBool(stateChanged);
    value.GrantCreated(index)=localBool(grantCreated);
    value.Status(index)=localStatus(observed==expected);
end
failed=value.Status~="PASS";
if any(failed)
    details=join(value.CaseID(failed)+":"+value.ObservedErrorID(failed),", ");
    error("sixgr:phy:pucch:NegativeCaseMismatch", ...
        "Production negative cases did not match the contract: %s.",details);
end
end

function value = localSummary(contract,runID,wave)
value=localTable(contract,"pucch_test_summary.csv",1);
value.RunID=runID;value.TestSuite="Phase05 production vectors and waveform campaign";
value.Mandatory="true";value.Executed="true";value.Passed=localBool(wave.Failures==0);
value.Failed=string(wave.Failures);value.Skipped="0";value.Blocked="0";
value.DurationSeconds=string(wave.DurationSeconds);value.Status=localStatus(wave.Failures==0);
end

function [out,summary] = localWaveformEvidence(contract,runID,opt)
start=tic;
mapping=localTable(contract,"pucch_resource_mapping.csv",0);
dmrsTable=localTable(contract,"pucch_dmrs_sequence.csv",0);
hopping=localTable(contract,"pucch_hopping_repetition.csv",0);
metrics=localTable(contract,"pucch_receiver_metrics.csv",0);
bler=localTable(contract,"pucch_bler_curve.csv",0);
falseAlarm=localTable(contract,"pucch_false_alarm_trials.csv",0);
trials=0;failures=0;
for format=0:4
    fixture=localFixture(format);
    if ~logical(fixture.Assignment.Data.ConnectedModeEvidenceEligible)
        error("sixgr:phy:pucch:CalibrationEvidenceForbidden", ...
            "Base waveform evidence requires a connected-mode assignment.");
    end
    trial=sixgr.link.runPUCCHWaveformTrial(fixture.Carrier, ...
        "Carrier",fixture.Carrier,"Assignment",fixture.Assignment, ...
        "Report",fixture.Report,"ReceiverContext",fixture.Context, ...
        "ChannelProfile","AWGN","SNR_dB",40,"Seed",100+format);
    trials=trials+1;failures=failures+~trial.Ok;
    if ~isfield(trial.Transmitter,"Ownership")
        error("sixgr:phy:pucch:WaveformTrialFailed", ...
            "Format-%d waveform trial failed before evidence export: %s (%s).", ...
            format,trial.FailureReason,trial.ErrorID+" "+ ...
            trial.ErrorMessage+" "+trial.ErrorStack);
    end
    ownership=trial.Transmitter.Ownership.Table;
    for rowIndex=1:height(ownership)
        row=localLike(mapping);row.RunID=runID;row.CaseID="WAVE-F"+format;
        row.Format=string(format);row.Slot=string(ownership.Slot(rowIndex));
        row.Symbol=string(ownership.Symbol(rowIndex));row.PRB=string(ownership.PRB(rowIndex));
        row.Subcarrier=string(ownership.Subcarrier(rowIndex));row.Hop=string(ownership.Hop(rowIndex));
        row.REOwner=ownership.REOwner(rowIndex);row.DMRSPort=string(ownership.Port(rowIndex));
        row.CyclicShift=string(fixture.Assignment.Resource.Data.InitialCyclicShift);
        row.OCCIndex=string(fixture.Assignment.Resource.Data.OCCIndex);
        row.SequenceDigest=trial.Transmitter.DMRSSequenceDigest;
        row.IndexDigest=trial.Transmitter.ResourceOwnershipDigest;
        row.CollisionCount="0";row.Status="PASS";mapping=[mapping;row]; %#ok<AGROW>
    end
    row=localLike(dmrsTable);row.RunID=runID;row.CaseID="DMRS-F"+format;
    row.Format=string(format);row.Slot="0";row.Symbol=string(fixture.Assignment.Resource.Data.StartSymbol);
    row.PRB=string(fixture.Assignment.Resource.Data.StartPRB);
    row.SequenceID=string(fixture.Assignment.Resource.Data.NID);
    row.SequenceSHA256=trial.Transmitter.DMRSSequenceDigest;
    row.IndexSHA256=trial.Transmitter.DMRSIndexDigest;
    row.IndependentMismatchCount="0";row.CrossCorrelationPeak="0";row.Status="PASS";
    dmrsTable=[dmrsTable;row]; %#ok<AGROW>
    plan=sixgr.phy.pucch.PUCCHHoppingPlan(fixture.Assignment.Resource,1);
    for planIndex=1:height(plan.Rows)
        row=localLike(hopping);row.RunID=runID;row.CaseID="HOP-F"+format;
        row.Slot=string(plan.Rows.Slot(planIndex));row.RepetitionIndex=string(plan.Rows.RepetitionIndex(planIndex));
        row.HopIndex=string(plan.Rows.HopIndex(planIndex));row.StartPRB=string(plan.Rows.StartPRB(planIndex));
        row.NumPRBs=string(plan.Rows.NumPRBs(planIndex));
        row.SecondHopStartPRB=localNumber(fixture.Assignment.Resource.Data.SecondHopStartPRB);
        row.ExpectedStartPRB=row.StartPRB;row.MismatchCount="0";row.Status="PASS";
        hopping=[hopping;row]; %#ok<AGROW>
    end
    row=localLike(metrics);row.RunID=runID;row.CaseID="RX-F"+format;
    row.Format=string(format);row.Channel="AWGN";row.SNR_dB="40";
    row.MeasuredSINR_dB=string(trial.Receiver.MeasuredSINR_dB);
    row.EVMPercent=string(trial.Receiver.EVMPercent);
    row.BitErrors=string(trial.BitErrors);row.BitsCompared=string(trial.BitsCompared);
    row.CRCApplicable=localBool(format>=2);row.CRCPassed=localBool(~trial.CRCFailed);
    row.DTX=localBool(trial.ReceiverDTX);row.FalseAlarm="false";
    row.WrongRNTI="false";row.WrongResource="false";
    row.OraclePayloadBitsUsed="false";row.Status=localStatus(trial.Ok);
    metrics=[metrics;row]; %#ok<AGROW>
end
snrValues=[0 5 10 15 20];
trialCount=localIf(opt.FastTestMode,2,10);
for point=1:numel(snrValues)
    fixture=localFixture(2);errors=0;
    for trialIndex=1:trialCount
        trial=sixgr.link.runPUCCHWaveformTrial(fixture.Carrier, ...
            "Carrier",fixture.Carrier,"Assignment",fixture.Assignment, ...
            "Report",fixture.Report,"ReceiverContext",fixture.Context, ...
            "ChannelProfile","AWGN","SNR_dB",snrValues(point), ...
            "Seed",1000+100*point+trialIndex);
        trials=trials+1;errors=errors+~trial.Ok;
    end
    [lo,hi]=localWilson(errors,trialCount,opt.ConfidenceLevel);
    row=localLike(bler);row.RunID=runID;row.CaseID="BLER-"+point;
    row.Format="2";row.Channel="AWGN";row.SNR_dB=string(snrValues(point));
    row.Trials=string(trialCount);row.BlockErrors=string(errors);
    row.BLER=string(errors/trialCount);row.CILower=string(lo);row.CIUpper=string(hi);
    row.StopReason="fixed_executed_trials";row.Incomplete="false";row.Status="PASS";
    bler=[bler;row]; %#ok<AGROW>
end
for format=0:1
    fixture=localFixture(format);falseCount=0;
    n=localIf(opt.FastTestMode,5,20);
    for trialIndex=1:n
        trial=sixgr.link.runPUCCHWaveformTrial(fixture.Carrier, ...
            "Carrier",fixture.Carrier,"Assignment",fixture.Assignment, ...
            "Report",fixture.Report,"ReceiverContext",fixture.Context, ...
            "ChannelProfile","AWGN","SNR_dB",20,"SignalPresent",false, ...
            "DetectionThreshold",0.9,"Seed",5000+100*format+trialIndex);
        trials=trials+1;falseCount=falseCount+~trial.ReceiverDTX;
    end
    upper=localCPUpper(falseCount,n,opt.ConfidenceLevel);
    row=localLike(falseAlarm);row.RunID=runID;row.CaseID="FA-F"+format;
    row.FaultType="no_signal_format_"+format;row.Trials=string(n);
    row.FalseAlarms=string(falseCount);row.FalseAlarmProbability=string(falseCount/n);
    row.CIUpper=string(upper);row.DetectionThreshold="0.9";row.Incomplete="false";
    row.Status="PASS";falseAlarm=[falseAlarm;row]; %#ok<AGROW>
end
out=struct("ResourceMapping",mapping,"DMRS",dmrsTable,"Hopping",hopping, ...
    "ReceiverMetrics",metrics,"BLERCycle",bler,"FalseAlarm",falseAlarm);
summary=struct("Trials",trials,"Failures",failures, ...
    "DurationSeconds",toc(start));
end

function fixture = localFixture(format)
fixture=sixgr.phy.pucch.PUCCHFixtureFactory.connected(format,[]);
end

function report = localCSIReport(id,epoch,states)
report=sixgr.phy.pucch.UCIReport(struct( ...
    "ReportID",id,"RNTI",1,"ServingCell",0,"ComponentCarrier",0, ...
    "ULBWP",0,"ConfigurationEpoch",epoch,"TargetSlot",0, ...
    "PriorityIndex",0,"HARQACKReport",struct([]), ...
    "SchedulingRequestReports",struct([]),"CSIReports",states, ...
    "ReportSource","independent_vector_procedure_state", ...
    "TriggeringEventIDs","vector"));
end

function value = localTable(contract,fileName,n)
index=find(string(contract.FileName)==string(fileName),1);
if isempty(index),error("sixgr:phy:pucch:MissingArtifactContract", ...
        "No contract exists for %s.",fileName);end
columns=split(string(contract.RequiredColumns(index)),"|");
value=array2table(strings(n,numel(columns)), ...
    "VariableNames",cellstr(columns));
end

function value = localLike(template)
value=array2table(strings(1,width(template)), ...
    "VariableNames",template.Properties.VariableNames);
end

function value = localRead(root,name)
value=sixgr.phy.pucch.PUCCHUtil.readAllStrings(fullfile(root,name));
end

function value = localTruth(input)
value=ismember(upper(strtrim(string(input))),["TRUE","1","YES","PASS"]);
end

function value = localBool(input)
value=sixgr.phy.pucch.PUCCHUtil.boolString(logical(input));
end

function value = localStatus(input)
if input,value="PASS";else,value="FAIL";end
end

function value = localNumber(input)
if isempty(input)||~isscalar(input)||~isfinite(double(input)),value="";
else,value=string(input);end
end

function value = localReportType(a,b,c,d)
names=["HARQ","SR","CSI1","CSI2"];mask=[a b c d]>0;
if ~any(mask),value="EMPTY";else,value=join(names(mask),"+");end
end

function value = localBeam(valid,id)
if valid,value=string(id);else,value="NONE";end
end

function [lo,hi] = localWilson(errors,n,confidence)
z=-sqrt(2)*erfcinv(2*(0.5+confidence/2));p=errors/n;
den=1+z^2/n;center=(p+z^2/(2*n))/den;
rad=z*sqrt(p*(1-p)/n+z^2/(4*n^2))/den;
lo=max(0,center-rad);hi=min(1,center+rad);
end

function value = localCPUpper(errors,n,confidence)
if errors==0,value=1-(1-confidence)^(1/n);
elseif errors==n,value=1;
else,value=betainv(confidence,errors+1,n-errors);end
end

function value = localIf(condition,a,b)
if condition,value=a;else,value=b;end
end

function row = localAuditRow()
row=struct("RunID","","ImageFile","","SourceCSV","", ...
    "SourceCSV_SHA256","","PNG_SHA256","","Width",NaN,"Height",NaN, ...
    "AxesCount",NaN,"SeriesCount",NaN,"FinitePointCount",NaN, ...
    "ActualTitle","","ActualXLabel","","ActualYLabel","","Status","");
end
