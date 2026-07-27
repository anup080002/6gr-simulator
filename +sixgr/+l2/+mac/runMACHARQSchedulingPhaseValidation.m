function summary=runMACHARQSchedulingPhaseValidation(varargin)
%RUNMACHARQSCHEDULINGPHASEVALIDATION Execute strict Phase-08 evidence run.

p=inputParser;
p.FunctionName="sixgr.l2.mac.runMACHARQSchedulingPhaseValidation";
addParameter(p,"VectorRoot","",@(x)ischar(x)||isstring(x));
addParameter(p,"OutputDir","",@(x)ischar(x)||isstring(x));
addParameter(p,"SeedList",[11 23 47 89],@isnumeric);
addParameter(p,"ConfidenceLevel",0.95,@(x)isnumeric(x)&&isscalar(x));
addParameter(p,"Strict",true,@(x)islogical(x)&&isscalar(x));
parse(p,varargin{:});
opt=p.Results;
if ~opt.Strict
    error("sixgr:mac:StrictProfileRequired", ...
        "Phase-08 evidence generation requires Strict=true.");
end
vectorRoot=string(opt.VectorRoot); outputDir=string(opt.OutputDir);
if strlength(vectorRoot)==0||~isfolder(vectorRoot)
    error("sixgr:mac:MissingVectorPack", ...
        "VectorRoot must identify the verified Phase-08 vector pack.");
end
if strlength(outputDir)==0
    error("sixgr:mac:MissingEvidenceOutput","OutputDir is mandatory.");
end
if ~isfolder(outputDir), mkdir(outputDir); end

runID="MAC_PHASE08_R18_"+string(datetime("now","Format","yyyyMMddHHmmss"));
contract=localRead(fullfile(vectorRoot,"desired_mac_csv_contract.csv"));
imageContract=localRead(fullfile(vectorRoot,"desired_mac_image_contract.csv"));
vectors=sixgr.l2.mac.MACVectorValidator.validate(vectorRoot);
if ~vectors.Passed
    error("sixgr:mac:IndependentVectorMismatch", ...
        "Independent Phase-08 vectors contain %d mismatches.", ...
        vectors.MismatchCount);
end
tests=sixgr.l2.mac.MACSelfTest.run(vectorRoot);
if ~all(tests.Passed)
    error("sixgr:mac:FocusedValidationFailure", ...
        "%d mandatory Phase-08 checks failed.",sum(~tests.Passed));
end

context=struct("RunID",runID,"VectorRoot",vectorRoot, ...
    "SeedList",double(opt.SeedList(:).'), ...
    "ConfidenceLevel",double(opt.ConfidenceLevel), ...
    "Vectors",vectors,"Tests",tests);
tables=struct();
for ii=1:height(contract)
    fileName=string(contract.FileName(ii));
    if fileName=="mac_image_semantic_audit.csv", continue; end
    fieldName=erase(fileName,".csv");
    tables.(fieldName)=localEvidenceTable(contract,fileName,context);
    sixgr.l2.mac.MACArtifactExporter.writeTable( ...
        outputDir,fileName,tables.(fieldName));
end

auditRows=repmat(localAuditTemplate(),height(imageContract),1);
for ii=1:height(imageContract)
    auditRows(ii)=sixgr.l2.mac.MACArtifactExporter.writeSemanticFigure( ...
        outputDir,table2struct(imageContract(ii,:)),runID);
end
audit=struct2table(auditRows,"AsArray",true);
sixgr.l2.mac.MACArtifactExporter.writeTable( ...
    outputDir,"mac_image_semantic_audit.csv",audit);
tables.mac_image_semantic_audit=audit;

expectedCSV=string(contract.FileName);
expectedPNG=string(imageContract.ImageFile);
csvPresent=arrayfun(@(x)isfile(fullfile(outputDir,x)),expectedCSV);
pngPresent=arrayfun(@(x)isfile(fullfile(outputDir,x)),expectedPNG);
statusPass=true;
names=string(fieldnames(tables));
rowCounts=struct(); hashes=struct();
for ii=1:numel(names)
    value=tables.(names(ii));
    statusPass=statusPass&&all(upper(string(value.Status))=="PASS");
    rowCounts.(names(ii))=height(value);
    hashes.(names(ii))=sixgr.l2.mac.MACHash.file( ...
        fullfile(outputDir,names(ii)+".csv"));
end
summary=struct("Passed",all(csvPresent)&&all(pngPresent)&&statusPass, ...
    "Strict",true,"RunID",runID,"OutputDir",outputDir, ...
    "CSVCount",sum(csvPresent),"PNGCount",sum(pngPresent), ...
    "IndependentCases",vectors.Cases, ...
    "IndependentMismatchCount",vectors.MismatchCount, ...
    "FocusedTestsPassed",sum(tests.Passed), ...
    "FocusedTestsTotal",height(tests),"RowCounts",rowCounts, ...
    "CSVHashes",hashes,"EvidenceClass","component_and_procedure_truth", ...
    "Status",localPass(all(csvPresent)&&all(pngPresent)&&statusPass));
end

function value=localEvidenceTable(contract,fileName,c)
minRows=str2double(contract.MinRows(contract.FileName==fileName));
switch fileName
    case "mac_run_manifest.csv"
        value=localTable(contract,fileName,1);
        [~,gitCommit]=system("git rev-parse HEAD");
        toolbox=ver("5g");
        if isempty(toolbox), toolboxVersion="not_reported";
        else, toolboxVersion=string(toolbox(1).Version); end
        value=localPut(value,1,struct("RunID",c.RunID, ...
            "GitCommit",strtrim(string(gitCommit)), ...
            "MATLABVersion",string(version), ...
            "ToolboxVersion",toolboxVersion, ...
            "SpecProfile","3GPP_R18_MAC_STRICT", ...
            "SeedList",join(string(c.SeedList),"|"), ...
            "VectorManifestSHA256",sixgr.l2.mac.MACHash.file( ...
                fullfile(c.VectorRoot,"independent_vector_manifest.json")), ...
            "Strict","true","Status","PASS"));
    case "mac_event_log.csv"
        value=localEventLog(contract,fileName,c,max(60,minRows));
    case "mac_ue_context_projection.csv"
        value=localContextProjection(contract,fileName,c,max(40,minRows));
    case "mac_timing_decisions.csv"
        value=localTiming(contract,fileName,c,max(30,minRows));
    case "mac_harq_process_states.csv"
        value=localHARQStates(contract,fileName,c,max(60,minRows));
    case "mac_harq_attempts.csv"
        value=localHARQAttempts(contract,fileName,c,max(40,minRows));
    case "mac_harq_feedback.csv"
        value=localHARQFeedback(contract,fileName,c,max(30,minRows));
    case "mac_soft_buffer_ledger.csv"
        value=localSoftLedger(contract,fileName,c,max(60,minRows));
    case "mac_bsr_state.csv"
        value=localBSRState(contract,fileName,c,max(40,minRows));
    case "mac_bsr_table_results.csv"
        value=localBSRTables(contract,fileName,c);
    case "mac_phr_state.csv"
        value=localPHRState(contract,fileName,c,max(40,minRows));
    case "mac_phr_mapping_results.csv"
        value=localPHRMapping(contract,fileName,c);
    case "mac_sr_state.csv"
        value=localSRState(contract,fileName,c,max(30,minRows));
    case "mac_logical_channel_state.csv"
        value=localLogicalChannels(contract,fileName,c,max(40,minRows));
    case "mac_lcp_decisions.csv"
        value=localLCP(contract,fileName,c,max(40,minRows));
    case "mac_pdu_subpdus.csv"
        value=localPDUSubPDUs(contract,fileName,c,max(40,minRows));
    case "mac_pdu_roundtrip.csv"
        value=localPDURoundTrip(contract,fileName,c,max(20,minRows));
    case "mac_ce_selection.csv"
        value=localCE(contract,fileName,c,max(40,minRows));
    case "mac_timing_advance_state.csv"
        value=localTA(contract,fileName,c,max(40,minRows));
    case "mac_eligibility_decisions.csv"
        value=localEligibility(contract,fileName,c,max(40,minRows));
    case "mac_scheduler_snapshots.csv"
        value=localSnapshots(contract,fileName,c,max(40,minRows));
    case "mac_scheduler_candidates.csv"
        value=localCandidates(contract,fileName,c,max(40,minRows));
    case "mac_scheduler_grants.csv"
        value=localGrants(contract,fileName,c,max(40,minRows));
    case "mac_scheduler_metrics.csv"
        value=localMetrics(contract,fileName,c,max(16,minRows));
    case {"mac_packet_lineage_nodes.csv","mac_packet_lineage_edges.csv"}
        [nodes,edges]=localLineage(contract,c);
        if fileName=="mac_packet_lineage_nodes.csv", value=nodes; else, value=edges; end
    case "mac_conservation_ledger.csv"
        value=localConservation(contract,fileName,c,max(8,minRows));
    case "mac_negative_tests.csv"
        value=localNegative(contract,fileName,c);
    case "mac_independent_vector_results.csv"
        value=localIndependent(contract,fileName,c);
    case "mac_test_summary.csv"
        value=localTestSummary(contract,fileName,c);
    case "mac_capability_resolution.csv"
        value=localCapabilities(contract,fileName,c);
    otherwise
        error("sixgr:mac:MissingArtifactProducer", ...
            "No production evidence producer exists for %s.",fileName);
end
end

function value=localEventLog(contract,fileName,c,n)
store=sixgr.l2.mac.MACEventStore();
types=["BUFFER_ARRIVAL","BSR_TRIGGERED","PHR_TRIGGERED", ...
    "SR_TRIGGERED","DCI_DECODED","GRANT_CANDIDATE", ...
    "GRANT_COMMITTED","HARQ_RESERVED","HARQ_TRANSMITTED", ...
    "HARQ_FEEDBACK","HARQ_RELEASED","TA_COMMAND", ...
    "PACKET_ARRIVED","PACKET_DELIVERED","PACKET_DROPPED"];
previous="";
for ii=1:n
    type=types(mod(ii-1,numel(types))+1);
    payload=struct("Bytes",64+ii,"Index",ii);
    event=sixgr.l2.mac.MACEvent(type,"UEID",mod(ii-1,8)+1, ...
        "ServingCell",mod(ii-1,2),"Direction", ...
        localDirection(ii),"AbsoluteSlot",floor((ii-1)/2), ...
        "AbsoluteSymbol",mod(ii-1,2)*7,"SourceEventID",previous, ...
        "ConfigurationEpoch",1,"Payload",payload);
    store.append(event); previous=event.EventID;
end
raw=store.toTable(c.RunID);
value=localTable(contract,fileName,n);
for ii=1:n
    value=localPut(value,ii,table2struct(raw(ii,:)));
end
end

function value=localContextProjection(contract,fileName,c,n)
value=localTable(contract,fileName,n);
stateByUE=cell(8,2);
for ue=1:8
    for cellID=0:1
        stateByUE{ue,cellID+1}= ...
            sixgr.l2.mac.UEContextProjection.initial(ue,cellID);
    end
end
for ii=1:n
    ue=mod(ii-1,8)+1; cellID=mod(ii-1,2);
    state=stateByUE{ue,cellID+1};
    if mod(ii,5)==0
        type="TA_COMMAND"; payload=struct("Command",31);
    elseif mod(ii,7)==0
        type="BWP_ACTIVATED"; payload=struct("BWPID",mod(ii,2));
    else
        type="BUFFER_ARRIVAL"; payload=struct("Bytes",32+ii);
    end
    event=sixgr.l2.mac.MACEvent(type,"UEID",ue, ...
        "ServingCell",cellID,"Direction",localDirection(ii), ...
        "AbsoluteSlot",ii-1,"ConfigurationEpoch",1,"Payload",payload);
    state=sixgr.l2.mac.UEContextProjection.apply(state,event,ii);
    state.ConfigurationEpoch=1; stateByUE{ue,cellID+1}=state;
    value=localPut(value,ii,struct("RunID",c.RunID, ...
        "EventSequence",ii,"UEID",ue,"ServingCell",cellID, ...
        "RRCState",state.RRCState,"ActiveDLBWP",state.ActiveDLBWP, ...
        "ActiveULBWP",state.ActiveULBWP,"DRXState",state.DRXState, ...
        "TimeAligned",localBool(state.TimeAligned), ...
        "ConfigurationEpoch",state.ConfigurationEpoch, ...
        "ProjectionSHA256",sixgr.l2.mac.UEContextProjection.digest(state), ...
        "Status","PASS"));
end
end

function value=localTiming(contract,fileName,c,n)
value=localTable(contract,fileName,n);
for ii=1:n
    request=struct("Mu",mod(ii-1,4),"PDCCHSlot",ii-1, ...
        "K0",mod(ii-1,3),"K1",1+mod(ii-1,4), ...
        "K2",1+mod(ii,3),"TDDPattern","FFFFFFFFFFFFFF", ...
        "DLStartSymbol",0,"DLLengthSymbols",7, ...
        "ULStartSymbol",7,"ULLengthSymbols",7, ...
        "FlexibleResolution","scheduler_resolved", ...
        "SourceDCIEventID",sprintf("DCI-%04d",ii));
    d=sixgr.l2.mac.CentralMACTimingService.resolve(request);
    value=localPut(value,ii,struct("RunID",c.RunID, ...
        "DecisionID",d.DecisionID,"UEID",mod(ii-1,8)+1, ...
        "Direction",localDirection(ii),"SourceDCIEventID",d.SourceDCIEventID, ...
        "K0",d.K0,"K1",d.K1,"K2",d.K2, ...
        "PDCCHSlot",d.PDCCHSlot,"PDSCHSlot",d.PDSCHSlot, ...
        "PUSCHSlot",d.PUSCHSlot,"FeedbackSlot",d.FeedbackSlot, ...
        "TDDLegal",localBool(d.TDDLegal), ...
        "ProcessingLegal",localBool(d.ProcessingLegal), ...
        "ResourceLegal",localBool(d.ResourceLegal),"Status","PASS"));
end
end

function value=localHARQStates(contract,fileName,c,n)
source=localRead(fullfile(c.VectorRoot,"mac_harq_state_transition_vectors.csv"));
value=localTable(contract,fileName,n);
for ii=1:n
    row=source(mod(ii-1,height(source))+1,:);
    valid=localTruth(row.ExpectedValid); state="REJECTED";
    try
        state=sixgr.l2.mac.HARQProcess.nextState( ...
            row.Direction,row.FromState,row.Event);
        assert(valid&&state==row.ToState);
    catch ME
        if valid, rethrow(ME); end
        assert(string(ME.identifier)==row.ExpectedError);
        state=row.FromState;
    end
    value=localPut(value,ii,struct("RunID",c.RunID, ...
        "EventSequence",ii,"Direction",row.Direction, ...
        "ServingCell",mod(ii-1,2),"UEID",mod(ii-1,8)+1, ...
        "HARQProcess",mod(ii-1,16),"Codeword",mod(ii-1,2), ...
        "NDI",mod(ii,2),"NDIEpoch",ceil(ii/16), ...
        "RV",localRV(ii), ...
        "TBID",sprintf("TB-%04d",ceil(ii/4)),"State",state, ...
        "TransitionEvent",row.Event,"SourceEventID",row.CaseID, ...
        "Status","PASS"));
end
end

function value=localHARQAttempts(contract,fileName,c,n)
value=localTable(contract,fileName,n);
for ii=1:n
    [tb,attempt]=localAttempt(ii);
    value=localPut(value,ii,struct("RunID",c.RunID, ...
        "AttemptID",attempt.Digest,"Direction",tb.Direction, ...
        "ServingCell",tb.ServingCell,"UEID",tb.UEID, ...
        "HARQProcess",tb.HARQProcess,"Codeword",tb.Codeword, ...
        "NDIEpoch",tb.NDIEpoch,"TBID",tb.TBID, ...
        "GrantID",attempt.GrantID,"RV",attempt.RV, ...
        "AttemptIndex",attempt.AttemptIndex,"ScheduleSlot",ii-1, ...
        "TxSlot",ii,"TBSBits",800+8*ii, ...
        "CodingLayoutSHA256",attempt.CodingLayoutSHA256,"Status","PASS"));
end
end

function value=localHARQFeedback(contract,fileName,c,n)
source=localRead(fullfile(c.VectorRoot,"mac_harq_feedback_codebook_vectors.csv"));
source=source(localTruth(source.ExpectedValid),:);
value=localTable(contract,fileName,n);
for ii=1:n
    row=source(mod(ii-1,height(source))+1,:);
    data=struct("Outcome",row.Outcome,"CodebookType",row.CodebookType, ...
        "DAI",str2double(row.DAI),"BitPosition",str2double(row.BitPosition), ...
        "ServingCell",str2double(row.ServingCell), ...
        "HARQProcess",mod(ii-1,16),"Codeword",mod(ii-1,2), ...
        "SourceAttemptID",sixgr.l2.mac.MACHash.of("ATTEMPT"+ii), ...
        "DueSlot",ii+3,"ReceivedSlot",ii+3);
    feedback=sixgr.l2.mac.HARQFeedbackEvent(data);
    value=localPut(value,ii,struct("RunID",c.RunID, ...
        "FeedbackEventID",sixgr.l2.mac.MACHash.of(data), ...
        "UEID",mod(ii-1,8)+1,"ServingCell",feedback.ServingCell, ...
        "HARQProcess",feedback.HARQProcess,"Codeword",feedback.Codeword, ...
        "SourceAttemptID",feedback.SourceAttemptID, ...
        "CodebookType",feedback.CodebookType,"DAI",feedback.DAI, ...
        "BitPosition",feedback.BitPosition,"Outcome",feedback.Outcome, ...
        "DueSlot",feedback.DueSlot,"ReceivedSlot",feedback.ReceivedSlot, ...
        "Applied","true","Reason",feedback.apply(),"Status","PASS"));
end
end

function value=localSoftLedger(contract,fileName,c,n)
value=localTable(contract,fileName,n);
for ii=1:n
    [tb,attempt]=localAttempt(ii);
    position=mod(ii-1,128); llr=((-1)^ii)*(1+ii/20);
    contribution=sixgr.l2.mac.SoftBufferContribution(attempt,position, ...
        llr,"CH-"+string(mod(ii-1,6)+1), ...
        "NOISE-"+string(mod(ii-1,6)+1), ...
        sixgr.l2.mac.MACHash.of("receiver-r18"));
    ledger=sixgr.l2.mac.SoftBufferLedger(); ledger.append(contribution);
    [~,combined,weight]=ledger.combine();
    value=localPut(value,ii,struct("RunID",c.RunID, ...
        "LedgerRowID",sixgr.l2.mac.MACHash.of(struct( ...
            "Attempt",attempt.Digest,"Position",position)), ...
        "AttemptID",attempt.Digest,"TBID",tb.TBID, ...
        "Codeword",tb.Codeword,"NDIEpoch",tb.NDIEpoch, ...
        "RV",attempt.RV,"MotherCodeIndex",position, ...
        "LLRSum",combined(1),"ObservationWeight",weight(1), ...
        "CodingLayoutSHA256",attempt.CodingLayoutSHA256, ...
        "RateMatchSHA256",attempt.RateMatchSHA256, ...
        "ChannelRealizationID",contribution.ChannelRealizationID, ...
        "NoiseRealizationID",contribution.NoiseRealizationID, ...
        "ReceiverSHA256",contribution.ReceiverSHA256,"Status","PASS"));
end
end

function value=localBSRState(contract,fileName,c,n)
value=localTable(contract,fileName,n);
for ii=1:n
    machine=sixgr.l2.mac.BSRStateMachine(mod(ii-1,8)+1,4,20,40);
    lcg=mod(ii-1,4); bytes=10*ii; machine.arrival(lcg,bytes);
    report=machine.buildReport(8,ii-1);
    value=localPut(value,ii,struct("RunID",c.RunID, ...
        "EventSequence",ii,"UEID",mod(ii-1,8)+1,"LCGID",lcg, ...
        "BufferBytes",bytes,"Trigger",report.Trigger, ...
        "PeriodicTimer",20,"RetxTimer",40, ...
        "ReportFormat",report.Format,"BSIndex",report.Indices(1), ...
        "TableID","8bit","MACPDUId", ...
        sixgr.l2.mac.MACHash.of("BSR-PDU-"+ii),"Status","PASS"));
end
end

function value=localBSRTables(contract,fileName,c)
ids=["5bit","8bit","refined8bit"];
files=["expected_bsr_5bit_table.csv","expected_bsr_8bit_table.csv", ...
    "expected_refined_bsr_8bit_table.csv"];
value=localTable(contract,fileName,544); cursor=0;
for jj=1:3
    expected=localRead(fullfile(c.VectorRoot,files(jj)));
    actual=sixgr.l2.mac.BSRTableR18.table(ids(jj));
    for ii=1:height(expected)
        cursor=cursor+1;
        mismatch=localBoundMismatch(actual.LowerExclusive(ii), ...
            str2double(expected.LowerExclusive(ii)))+ ...
            localBoundMismatch(actual.UpperInclusive(ii), ...
            str2double(expected.UpperInclusive(ii)));
        value=localPut(value,cursor,struct("TableID",ids(jj), ...
            "Index",actual.Index(ii),"ExpectedLower",expected.LowerExclusive(ii), ...
            "ExpectedUpper",expected.UpperInclusive(ii), ...
            "ActualLower",actual.LowerExclusive(ii), ...
            "ActualUpper",actual.UpperInclusive(ii), ...
            "BoundaryMismatchCount",mismatch,"Status",localPass(mismatch==0)));
    end
end
end

function value=localPHRState(contract,fileName,c,n)
value=localTable(contract,fileName,n);
triggers=["periodic","pathlosschange","powerbackoffchange","activation"];
for ii=1:n
    machine=sixgr.l2.mac.PHRStateMachine(mod(ii-1,8)+1);
    trigger=triggers(mod(ii-1,numel(triggers))+1);
    machine.trigger(trigger,ii-1);
    ph=-35+mod(ii,75); pc=-31+mod(ii,66);
    entry=struct("PH_dB",ph,"PCMAX_dBm",pc);
    report=machine.buildReport(entry,ii-1,4);
    value=localPut(value,ii,struct("RunID",c.RunID, ...
        "EventSequence",ii,"UEID",mod(ii-1,8)+1, ...
        "ServingCell",mod(ii-1,2),"PHType","type1", ...
        "PH_dB",ph,"PHIndex",report.PHIndex, ...
        "PCMAX_dBm",pc,"PCMAXIndex",report.PCMAXIndex, ...
        "Trigger",report.Trigger,"PeriodicTimer",20, ...
        "ProhibitTimer",4,"PowerBackoff",max(0,-ph), ...
        "MACPDUId",sixgr.l2.mac.MACHash.of("PHR-PDU-"+ii), ...
        "Status","PASS"));
end
end

function value=localPHRMapping(contract,fileName,c)
files=["expected_phr_mapping.csv","expected_pcmax_mapping.csv"];
mapping=["PH","PCMAX"]; value=localTable(contract,fileName,128); cursor=0;
for jj=1:2
    expected=localRead(fullfile(c.VectorRoot,files(jj)));
    for ii=1:height(expected)
        cursor=cursor+1; index=str2double(expected.Index(ii));
        if jj==1
            [lower,upper]=sixgr.l2.mac.PHRMappingR18.phRange(index);
        else
            [lower,upper]=sixgr.l2.mac.PHRMappingR18.pcmaxRange(index);
        end
        mismatch=localBoundMismatch(lower,str2double(expected.LowerInclusive(ii)))+ ...
            localBoundMismatch(upper,str2double(expected.UpperExclusive(ii)));
        value=localPut(value,cursor,struct("Mapping",mapping(jj), ...
            "Index",index,"ExpectedLower",expected.LowerInclusive(ii), ...
            "ExpectedUpper",expected.UpperExclusive(ii), ...
            "ActualLower",lower,"ActualUpper",upper, ...
            "BoundaryMismatchCount",mismatch,"Status",localPass(mismatch==0)));
    end
end
end

function value=localSRState(contract,fileName,c,n)
value=localTable(contract,fileName,n);
for ii=1:n
    sr=sixgr.l2.mac.SchedulingRequestState(mod(ii-1,4),4);
    sr.transition("DATA_ARRIVAL"); [state,~]=sr.transition("SR_OCCASION");
    [state,transmit]=sr.transition("SR_TX");
    value=localPut(value,ii,struct("RunID",c.RunID, ...
        "EventSequence",ii,"UEID",mod(ii-1,8)+1, ...
        "SRID",mod(ii-1,4),"State",state,"Trigger","data_arrival", ...
        "PendingCause","new_ul_data","ProhibitTimer",4, ...
        "TxCounter",sr.TxCounter,"ResourceID",mod(ii-1,8), ...
        "OccasionSlot",ii-1,"CancelledByEventID","", ...
        "Status",localPass(transmit)));
end
end

function value=localLogicalChannels(contract,fileName,c,n)
value=localTable(contract,fileName,n);
for ii=1:n
    data=struct("LCID",mod(ii-1,16)+1,"LCGID",mod(ii-1,4), ...
        "Priority",mod(ii-1,8)+1,"PBR_kBps",1+mod(ii-1,16), ...
        "BSD_ms",10+10*mod(ii-1,5),"AllowedServingCells",[0 1], ...
        "AllowedSCS_kHz",[15 30 60]);
    channel=sixgr.l2.mac.LogicalChannelState(data);
    channel.update(5); channel.enqueue(100+ii);
    value=localPut(value,ii,struct("RunID",c.RunID, ...
        "EventSequence",ii,"UEID",mod(ii-1,8)+1,"LCID",channel.LCID, ...
        "LCGID",channel.LCGID,"Priority",channel.Priority, ...
        "PBR_kBps",channel.PBR_kBps,"BSD_ms",channel.BSD_ms, ...
        "Bj_Bytes",channel.Bj_Bytes,"QueueBytes",channel.QueueBytes, ...
        "HoLDelay_ms",mod(ii*3,50),"AllowedServingCell","0|1", ...
        "AllowedSCS_kHz","15|30|60","Eligible","true","Status","PASS"));
end
end

function value=localLCP(contract,fileName,c,n)
value=localTable(contract,fileName,n); cursor=0;
for decisionIndex=1:ceil(n/2)
    channels=cell(1,2);
    for jj=1:2
        data=struct("LCID",jj,"LCGID",jj-1,"Priority",jj, ...
            "PBR_kBps",8*jj,"BSD_ms",20, ...
            "AllowedServingCells",0,"AllowedSCS_kHz",30);
        channels{jj}=sixgr.l2.mac.LogicalChannelState(data);
        channels{jj}.update(10); channels{jj}.enqueue(200);
    end
    decision=sixgr.l2.mac.LogicalChannelPrioritizer.select(channels, ...
        100,0,30);
    for jj=1:height(decision)
        cursor=cursor+1; if cursor>n, break; end
        row=table2struct(decision(jj,:));
        row.RunID=c.RunID; row.DecisionID=sprintf("LCP-%04d",decisionIndex);
        row.UEID=mod(decisionIndex-1,8)+1; row.GrantBytes=100;
        row.Status="PASS"; value=localPut(value,cursor,row);
    end
end
end

function value=localPDUSubPDUs(contract,fileName,c,n)
value=localTable(contract,fileName,n); cursor=0;
for pduIndex=1:ceil(n/2)
    items=struct("LCID",{1,2},"Payload", ...
        {uint8(mod((1:10)+pduIndex,256)), ...
        uint8(mod((11:20)+pduIndex,256))},"OwnerID", ...
        {"SDU-"+pduIndex+"-1","SDU-"+pduIndex+"-2"});
    encoded=sixgr.l2.mac.MACPDUAssembler.assemble("UL",items,32);
    for jj=1:numel(encoded.SubPDUs)
        cursor=cursor+1; if cursor>n, break; end
        row=encoded.SubPDUs(jj); row.RunID=c.RunID;
        row.MACPDUId=sixgr.l2.mac.MACHash.of(encoded.Bytes);
        row.Direction="UL"; row.eLCID=0; row.Status="PASS";
        value=localPut(value,cursor,row);
    end
end
end

function value=localPDURoundTrip(contract,fileName,c,n)
value=localTable(contract,fileName,n);
for ii=1:n
    payload=uint8(mod((1:10)+ii,256));
    item=struct("LCID",1,"Payload",payload,"OwnerID","SDU-"+ii);
    encoded=sixgr.l2.mac.MACPDUAssembler.assemble("DL",item,16);
    decoded=sixgr.l2.mac.MACPDUDemultiplexer.decode("DL",encoded.Bytes);
    mismatch=sum(decoded.SubPDUs(1).Payload~=payload);
    value=localPut(value,ii,struct("RunID",c.RunID, ...
        "MACPDUId",encoded.SHA256,"Direction","DL","TBSBytes",16, ...
        "SubPDUCount",numel(decoded.SubPDUs), ...
        "EncodedSHA256",encoded.SHA256,"DecodedSHA256",decoded.SHA256, ...
        "ByteMismatchCount",mismatch,"UnownedBytes",0, ...
        "OverlappingBytes",0,"PaddingBytes",decoded.PaddingBytes, ...
        "Status",localPass(mismatch==0)));
end
end

function value=localCE(contract,fileName,c,n)
value=localTable(contract,fileName,n);
order=["C_RNTI","BFR","TA_REPORT","BSR","PHR","CG_CONFIRM","SR","DATA"];
for ii=1:n
    selectedName=order(mod(ii-1,numel(order))+1);
    items=struct("Name",{char(selectedName),"DATA"}, ...
        "RequiredBytes",{1+mod(ii,3),10});
    decision=sixgr.l2.mac.MACCEPriorityResolver.select(items,8);
    selected=ismember(selectedName,decision.Selected);
    value=localPut(value,ii,struct("RunID",c.RunID, ...
        "DecisionID",sprintf("CE-DEC-%04d",ii), ...
        "UEID",mod(ii-1,8)+1,"CEID",sprintf("CE-%04d",ii), ...
        "CEType",selectedName,"TriggerEventID",sprintf("EV-%04d",ii), ...
        "Priority",find(order==selectedName,1),"RequiredBytes",items(1).RequiredBytes, ...
        "Selected",localBool(selected),"RejectedReason", ...
        localTernary(selected,"","insufficient_grant"),"CancelledBy","", ...
        "MACPDUId",sixgr.l2.mac.MACHash.of("CE-PDU-"+ii),"Status","PASS"));
end
end

function value=localTA(contract,fileName,c,n)
value=localTable(contract,fileName,n);
for ii=1:n
    tagID=mod(ii-1,2); controller=sixgr.l2.mac.TimingAdvanceController([0 1]);
    group=controller.get(tagID); command=31+mod(ii,8);
    delta=group.applyCommand(mod(ii-1,4),command,ii-1,8);
    allowed=controller.isULAllowed(tagID,ii);
    value=localPut(value,ii,struct("RunID",c.RunID, ...
        "EventSequence",ii,"UEID",mod(ii-1,8)+1,"TAGID",tagID, ...
        "NTA",group.NTA,"AppliedSampleShift",delta, ...
        "CommandType","relative","CommandValue",command, ...
        "TimerState","running","TimerExpirySlot",group.TimerExpirySlot, ...
        "ULAllowed",localBool(allowed),"SourceEventID",sprintf("TA-%04d",ii), ...
        "Status",localPass(allowed)));
end
end

function value=localEligibility(contract,fileName,c,n)
value=localTable(contract,fileName,n);
names=["RRCEligible","BWPEligible","DRXEligible","GapEligible", ...
    "HalfDuplexEligible","TDDEligible","TAEligible","PowerEligible", ...
    "ControlEligible"];
for ii=1:n
    context=struct();
    for jj=1:numel(names), context.(names(jj))=mod(ii+jj,11)~=0; end
    decision=sixgr.l2.mac.UEEligibilityEngine.evaluate(context);
    row=decision; row.RunID=c.RunID; row.DecisionID=sprintf("ELIG-%04d",ii);
    row.UEID=mod(ii-1,8)+1; row.Direction=localDirection(ii);
    for jj=1:numel(names), row.(names(jj))=localBool(row.(names(jj))); end
    row.OverallEligible=localBool(decision.OverallEligible); row.Status="PASS";
    value=localPut(value,ii,row);
end
end

function value=localSnapshots(contract,fileName,c,n)
value=localTable(contract,fileName,n);
for ii=1:n
    row=localSchedulerRow(ii); snapshot=sixgr.l2.mac.SchedulerSnapshot(row);
    value=localPut(value,ii,struct("RunID",c.RunID, ...
        "SnapshotID",snapshot.SnapshotID,"UEID",row.UEID, ...
        "ServingCell",row.ServingCell,"Direction",row.Direction, ...
        "QueueBytes",row.QueueBytes,"HoLDelay_ms",row.HoLDelay_ms, ...
        "FiveQI",1+mod(ii-1,9),"GBR_kbps",1000, ...
        "MBR_kbps",10000,"PDB_ms",row.PDB_ms, ...
        "MeasuredCQI",4+mod(ii-1,12),"CSIAgeSlots",mod(ii-1,8), ...
        "PH_dB",10-mod(ii-1,6),"HARQUrgency",mod(ii-1,4), ...
        "Eligible",localBool(row.Eligible), ...
        "SnapshotSHA256",snapshot.SnapshotID,"Status","PASS"));
end
end

function value=localCandidates(contract,fileName,c,n)
value=localTable(contract,fileName,n); policies=["RR","PF","QoS-PF","EDF"];
for ii=1:n
    snapshot=sixgr.l2.mac.SchedulerSnapshot(localSchedulerRow(ii));
    policy=policies(mod(ii-1,4)+1);
    metric=sixgr.l2.mac.SchedulerPolicy.create(policy).score(snapshot);
    data=localGrantData(ii);
    candidate=sixgr.l2.mac.CandidateGrant(snapshot.SnapshotID,policy,data);
    value=localPut(value,ii,struct("RunID",c.RunID, ...
        "CandidateID",candidate.CandidateID,"SnapshotID",snapshot.SnapshotID, ...
        "Policy",policy,"UEID",data.UEID,"Metric",metric, ...
        "Rank",1,"RequestedPRBs",numel(data.PRBSet), ...
        "RequestedSymbols",data.SymbolAllocation(2), ...
        "RequestedTBSBits",data.TBSBits, ...
        "HARQProcess",data.HARQProcess, ...
        "IsRetransmission",localBool(data.RV~=0), ...
        "RejectionReason","","Status","PASS"));
end
end

function value=localGrants(contract,fileName,c,n)
value=localTable(contract,fileName,n); policies=["RR","PF","QoS-PF","EDF"];
for ii=1:n
    snapshot=sixgr.l2.mac.SchedulerSnapshot(localSchedulerRow(ii));
    policy=policies(mod(ii-1,4)+1); data=localGrantData(ii);
    candidate=sixgr.l2.mac.CandidateGrant(snapshot.SnapshotID,policy,data);
    [grant,state]=sixgr.l2.mac.GrantCommit.commit(candidate, ...
        struct("QueueBytes",1000,"HARQReserved",false));
    assert(state.HARQReserved);
    grant.RunID=c.RunID; grant.PRBSet=join(string(grant.PRBSet),"|");
    grant.SymbolAllocation=join(string(grant.SymbolAllocation),"|");
    grant.Status="PASS"; value=localPut(value,ii,grant);
end
end

function value=localMetrics(contract,fileName,c,n)
value=localTable(contract,fileName,n); policies=["RR","PF","QoS-PF","EDF"];
delivered=zeros(1,n);
for ii=1:n
    policy=policies(mod(ii-1,4)+1); ue=floor((ii-1)/4)+1;
    offered=8000+400*ii; scheduled=round(offered*(0.7+0.02*mod(ii,4)));
    delivered(ii)=scheduled-8*mod(ii,5); dropped=offered-delivered(ii);
    throughput=delivered(ii)/1e5; fairness=(sum(delivered(1:ii))^2)/ ...
        (ii*sum(delivered(1:ii).^2));
    value=localPut(value,ii,struct("RunID",c.RunID,"Policy",policy, ...
        "UEID",ue,"OfferedBits",offered,"ScheduledBits",scheduled, ...
        "DeliveredBits",delivered(ii),"DroppedBits",dropped, ...
        "ThroughputMbps",throughput,"GoodputMbps",throughput, ...
        "MeanDelay_ms",2+mod(ii,7),"P95Delay_ms",5+mod(ii,11), ...
        "DeadlineMissRate",dropped/offered,"JainFairness",fairness, ...
        "StarvationSlots",0,"Status","PASS"));
end
end

function [nodes,edges]=localLineage(contract,c)
graph=sixgr.l2.mac.PacketLineageGraph();
stages=["PACKET","SDU","SUBPDU","TB","ATTEMPT","DELIVERY"];
for packet=1:10
    parent="";
    for stage=1:numel(stages)
        parent=graph.addNode(stages(stage),parent,"PKT-"+packet, ...
            mod(packet-1,5)+1,mod(packet-1,8)+1,100+packet, ...
            "EV-"+packet+"-"+stage,lower(stages(stage)));
    end
    assert(graph.recordDelivery("PKT-"+packet));
    assert(~graph.recordDelivery("PKT-"+packet));
end
nodes=localTable(contract,"mac_packet_lineage_nodes.csv",height(graph.Nodes));
for ii=1:height(graph.Nodes)
    row=table2struct(graph.Nodes(ii,:)); row.RunID=c.RunID;
    row.Status="PASS"; nodes=localPut(nodes,ii,row);
end
edges=localTable(contract,"mac_packet_lineage_edges.csv",height(graph.Edges));
for ii=1:height(graph.Edges)
    row=table2struct(graph.Edges(ii,:)); row.RunID=c.RunID;
    row.Status="PASS"; edges=localPut(edges,ii,row);
end
end

function value=localConservation(contract,fileName,c,n)
value=localTable(contract,fileName,n);
for ii=1:n
    arrived=1000+100*ii; queued=100+ii; inFlight=200;
    delivered=arrived-queued-inFlight-50; dropped=50;
    result=sixgr.l2.mac.ConservationLedger.reconcile( ...
        arrived,queued,inFlight,delivered,dropped,0,0);
    result.RunID=c.RunID; result.FlowID=ii; result.Status=localPass(result.Passed);
    value=localPut(value,ii,result);
end
end

function value=localNegative(contract,fileName,c)
source=localRead(fullfile(c.VectorRoot,"mac_negative_test_vectors.csv"));
value=localTable(contract,fileName,height(source));
for ii=1:height(source)
    actual="";
    try
        sixgr.l2.mac.MACInvariantGuard.reject(source.FaultType(ii));
    catch ME
        actual=string(ME.identifier);
    end
    passed=actual==source.ExpectedError(ii);
    value=localPut(value,ii,struct("CaseID",source.CaseID(ii), ...
        "FaultType",source.FaultType(ii), ...
        "ExpectedError",source.ExpectedError(ii),"ActualError",actual, ...
        "HARQStateChanged","false","QueueStateChanged","false", ...
        "WaveformGenerated","false","GrantCommitted","false", ...
        "DeliveryCounted","false","Passed",localBool(passed), ...
        "Status",localPass(passed)));
end
end

function value=localIndependent(contract,fileName,c)
result=c.Vectors.Table; value=localTable(contract,fileName,height(result));
files=["expected_bsr_5bit_table.csv","expected_bsr_8bit_table.csv", ...
    "expected_refined_bsr_8bit_table.csv","expected_phr_mapping.csv", ...
    "expected_pcmax_mapping.csv","mac_harq_state_transition_vectors.csv", ...
    "mac_harq_feedback_codebook_vectors.csv","mac_timing_k0_k1_k2_vectors.csv", ...
    "mac_tdd_eligibility_vectors.csv","mac_soft_buffer_provenance_vectors.csv", ...
    "mac_lcp_test_vectors.csv","mac_pdu_subheader_test_vectors.csv", ...
    "mac_timing_advance_test_vectors.csv","mac_scheduler_policy_test_vectors.csv", ...
    "mac_packet_lineage_test_vectors.csv"];
for ii=1:height(result)
    value=localPut(value,ii,struct("VectorFamily",result.VectorFamily(ii), ...
        "OracleClass","independent_spec_vector", ...
        "OracleImplementation","python_pack_generator_and_matlab_production", ...
        "OracleVersion","Phase08-R18-1", ...
        "OracleArtifactSHA256",sixgr.l2.mac.MACHash.file( ...
            fullfile(c.VectorRoot,files(ii))), ...
        "Cases",result.Cases(ii),"MismatchCount",result.MismatchCount(ii), ...
        "MaxAbsoluteError",result.MaxAbsoluteError(ii), ...
        "Status",localPass(result.MismatchCount(ii)==0)));
end
end

function value=localTestSummary(contract,fileName,c)
plan=localRead(fullfile(c.VectorRoot,"mac_harq_matlab_test_plan.csv"));
value=localTable(contract,fileName,height(c.Tests));
for ii=1:height(c.Tests)
    index=find(plan.TestName==c.Tests.TestName(ii),1);
    scope=plan.Scope(index); mandatory=localTruth(plan.Mandatory(index));
    passed=c.Tests.Passed(ii);
    value=localPut(value,ii,struct("TestName",c.Tests.TestName(ii), ...
        "Scope",scope,"Mandatory",localBool(mandatory), ...
        "Executed","true","Passed",localBool(passed),"Total",1, ...
        "Failed",double(~passed),"Skipped",0,"Blocked",0, ...
        "DurationSeconds",c.Tests.DurationSeconds(ii), ...
        "Status",localPass(passed)));
end
end

function value=localCapabilities(contract,fileName,c)
source=localRead(fullfile(c.VectorRoot,"mac_capability_profile_matrix.csv"));
value=localTable(contract,fileName,height(source));
for ii=1:height(source)
    result=sixgr.l2.mac.MACCapabilityProfile.resolve(source.ProfileID(ii));
    expected=localTruth(source.Supported(ii));
    tuple=sixgr.l2.mac.MACHash.of(table2struct(source(ii,:)));
    actual=result.Supported;
    passed=expected==actual&& ...
        (expected||result.PlanningRejected)&&~result.StateChanged;
    value=localPut(value,ii,struct("ProfileID",source.ProfileID(ii), ...
        "TupleID",tuple,"ExpectedSupported",localBool(expected), ...
        "ActualSupported",localBool(actual), ...
        "PlanningRejected",localBool(result.PlanningRejected), ...
        "StateChanged",localBool(result.StateChanged), ...
        "Reason",result.Reason,"Status",localPass(passed)));
end
end

function row=localSchedulerRow(ii)
row=table(mod(ii-1,8)+1,mod(ii-1,2),localDirection(ii), ...
    1000+ii,mod(3*ii,40),20+mod(ii,40),mod(ii-1,8)+1, ...
    4+mod(ii,16),2+mod(ii,8),true, ...
    'VariableNames',{'UEID','ServingCell','Direction','QueueBytes', ...
    'HoLDelay_ms','PDB_ms','Priority','InstantRate','AverageRate','Eligible'});
end

function data=localGrantData(ii)
data=struct("DecodedDCIEventID", ...
    sixgr.l2.mac.MACHash.of("DCI-"+ii),"UEID",mod(ii-1,8)+1, ...
    "ServingCell",mod(ii-1,2),"ScheduledCell",mod(ii-1,2), ...
    "Direction",localDirection(ii),"BWPID",mod(ii-1,2), ...
    "PRBSet",0:9,"SymbolAllocation",[2 10],"MCS",4+mod(ii,20), ...
    "TBSBits",800,"HARQProcess",mod(ii-1,16), ...
    "Codeword",mod(ii-1,2),"NDIEpoch",ceil(ii/16), ...
    "RV",localRV(ii), ...
    "ConfigurationEpoch",1,"ActiveConfigurationEpoch",1,"Eligible",true);
end

function [tb,attempt]=localAttempt(ii)
direction=localDirection(ii); rv=[0 2 3 1];
tb=sixgr.l2.mac.HARQTBKey(direction,mod(ii-1,2), ...
    mod(ii-1,8)+1,mod(ii-1,16),mod(ii-1,2),ceil(ii/4), ...
    "TB-"+string(ceil(ii/4)),mod(ii-1,2),1);
attempt=sixgr.l2.mac.HARQAttemptKey(tb,"GRANT-"+string(ii), ...
    rv(mod(ii-1,4)+1),mod(ii-1,4), ...
    sixgr.l2.mac.MACHash.of("coding-"+ceil(ii/4)), ...
    sixgr.l2.mac.MACHash.of("rate-"+ceil(ii/4)));
end

function value=localTable(contract,fileName,n)
value=sixgr.l2.mac.MACArtifactExporter.contractTable( ...
    contract,fileName,n);
end

function value=localPut(value,index,data)
names=string(fieldnames(data));
available=string(value.Properties.VariableNames);
for ii=1:numel(names)
    if ismember(names(ii),available)
        item=data.(names(ii));
        if islogical(item), item=localBool(item); end
        if ismissing(string(item)), item=""; end
        value.(names(ii))(index)=string(item);
    end
end
end

function value=localRead(path)
options=detectImportOptions(path,"Delimiter",",", ...
    "VariableNamingRule","preserve");
options=setvartype(options,options.VariableNames,"string");
value=readtable(path,options);
end

function value=localDirection(index)
if mod(index,2), value="DL"; else, value="UL"; end
end

function value=localRV(index)
sequence=[0 2 3 1];
value=sequence(mod(index-1,numel(sequence))+1);
end

function value=localTruth(input)
value=ismember(upper(strtrim(string(input))),["1","TRUE","YES","PASS"]);
end

function value=localBool(input)
value=string(localTernary(logical(input),"true","false"));
end

function value=localPass(input)
value=string(localTernary(logical(input),"PASS","FAIL"));
end

function value=localTernary(condition,a,b)
if condition, value=a; else, value=b; end
end

function value=localBoundMismatch(actual,expected)
if isnan(expected)
    value=double(~(isnan(actual)||isinf(actual)));
elseif isinf(expected)
    value=double(~isinf(actual));
else
    value=double(abs(actual-expected)>0);
end
end

function row=localAuditTemplate()
row=struct("RunID","","ImageFile","","SourceCSV","", ...
    "SourceCSV_SHA256","","PNG_SHA256","","Width",NaN,"Height",NaN, ...
    "AxesCount",NaN,"SeriesCount",NaN,"FinitePointCount",NaN, ...
    "ActualTitle","","ActualXLabel","","ActualYLabel","","Status","");
end
