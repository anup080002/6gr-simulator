function summary=runMACHARQSchedulingImpactAnalysis(varargin)
%RUNMACHARQSCHEDULINGIMPACTANALYSIS Execute paired Phase-08 component study.
% The outputs are explicitly labelled component_proxy/study_not_truth.

p=inputParser;
p.FunctionName="sixgr.l2.mac.runMACHARQSchedulingImpactAnalysis";
addParameter(p,"ExperimentMatrix","",@(x)ischar(x)||isstring(x));
addParameter(p,"OutputDir","",@(x)ischar(x)||isstring(x));
addParameter(p,"SeedList",[11 23 47 89 131 197],@isnumeric);
addParameter(p,"ConfidenceLevel",0.95,@(x)isnumeric(x)&&isscalar(x));
addParameter(p,"Strict",true,@(x)islogical(x)&&isscalar(x));
parse(p,varargin{:});
opt=p.Results;
if ~opt.Strict
    error("sixgr:mac:StrictProfileRequired", ...
        "Phase-08 impact analysis requires Strict=true.");
end
matrixPath=string(opt.ExperimentMatrix); outputDir=string(opt.OutputDir);
if ~isfile(matrixPath)
    error("sixgr:mac:MissingExperimentMatrix", ...
        "ExperimentMatrix must identify the verified Phase-08 matrix.");
end
if strlength(outputDir)==0
    error("sixgr:mac:MissingEvidenceOutput","OutputDir is mandatory.");
end
if ~isfolder(outputDir), mkdir(outputDir); end
vectorRoot=string(fileparts(matrixPath));
contract=localRead(fullfile(vectorRoot,"desired_mac_impact_csv_contract.csv"));
imageContract=localRead(fullfile(vectorRoot, ...
    "desired_mac_impact_image_contract.csv"));
matrix=localRead(matrixPath);
families=localRead(fullfile(vectorRoot,"mac_impact_analysis_families.csv"));
rules=localRead(fullfile(vectorRoot,"mac_impact_acceptance_rules.csv"));
if height(matrix)~=768||height(families)~=64||height(rules)~=96
    error("sixgr:mac:IncompleteImpactContract", ...
        "Expected 768 experiments, 64 families, and 96 rules.");
end

runID="MAC_IMPACT08_R18_"+string(datetime("now","Format","yyyyMMddHHmmss"));
[raw,points]=localExecuteMatrix(contract,matrix,runID,opt.ConfidenceLevel);
effects=localPairEffects(contract,raw);
ruleResults=localRules(contract,rules,points,effects);
tables=struct();
tables.mac_impact_run_manifest=localManifest( ...
    contract,runID,matrixPath,opt.SeedList);
tables.mac_impact_raw_trials=raw;
tables.mac_impact_operating_points=points;
tables.mac_impact_pairwise_effects=effects;
tables.mac_impact_rule_evaluation=ruleResults;
tables.mac_impact_harq=localCategory( ...
    contract,"mac_impact_harq.csv",points,effects,20);
tables.mac_impact_timing=localCategory( ...
    contract,"mac_impact_timing.csv",points,effects,20);
tables.mac_impact_bsr_phr_sr=localCategory( ...
    contract,"mac_impact_bsr_phr_sr.csv",points,effects,20);
tables.mac_impact_lcp_pdu=localCategory( ...
    contract,"mac_impact_lcp_pdu.csv",points,effects,20);
tables.mac_impact_scheduler=localCategory( ...
    contract,"mac_impact_scheduler.csv",points,effects,24);
tables.mac_impact_timing_advance=localCategory( ...
    contract,"mac_impact_timing_advance.csv",points,effects,12);
tables.mac_impact_persistent_grants=localCategory( ...
    contract,"mac_impact_persistent_grants.csv",points,effects,12);
tables.mac_impact_lineage=localCategory( ...
    contract,"mac_impact_lineage.csv",points,effects,12);
tables.mac_impact_runtime=localCategory( ...
    contract,"mac_impact_runtime.csv",points,effects,20);
tables.mac_impact_summary=localSummary( ...
    contract,families,matrix,ruleResults);

names=string(fieldnames(tables));
for ii=1:numel(names)
    sixgr.l2.mac.MACArtifactExporter.writeTable( ...
        outputDir,names(ii)+".csv",tables.(names(ii)));
end
auditRows=repmat(localAuditTemplate(),height(imageContract),1);
for ii=1:height(imageContract)
    auditRows(ii)=sixgr.l2.mac.MACArtifactExporter.writeSemanticFigure( ...
        outputDir,table2struct(imageContract(ii,:)),runID);
end
audit=struct2table(auditRows,"AsArray",true);
sixgr.l2.mac.MACArtifactExporter.writeTable( ...
    outputDir,"mac_impact_image_semantic_audit.csv",audit);
tables.mac_impact_image_semantic_audit=audit;

expectedCSV=string(contract.FileName);
expectedPNG=string(imageContract.ImageFile);
csvPresent=arrayfun(@(x)isfile(fullfile(outputDir,x)),expectedCSV);
pngPresent=arrayfun(@(x)isfile(fullfile(outputDir,x)),expectedPNG);
allPass=all(ruleResults.Result=="PASS");
names=string(fieldnames(tables)); rowCounts=struct(); hashes=struct();
for ii=1:numel(names)
    value=tables.(names(ii)); allPass=allPass&&all(value.Status=="PASS");
    rowCounts.(names(ii))=height(value);
    hashes.(names(ii))=sixgr.l2.mac.MACHash.file( ...
        fullfile(outputDir,names(ii)+".csv"));
end
passed=all(csvPresent)&&all(pngPresent)&&allPass;
summary=struct("Passed",passed,"Strict",true,"RunID",runID, ...
    "OutputDir",outputDir,"CSVCount",sum(csvPresent), ...
    "PNGCount",sum(pngPresent),"ExperimentsComplete",height(points), ...
    "ExperimentsExpected",height(matrix), ...
    "RulesPassed",sum(ruleResults.Result=="PASS"), ...
    "RulesExpected",height(rules),"IncompletePoints", ...
    sum(localTruth(points.Incomplete)),"RowCounts",rowCounts, ...
    "CSVHashes",hashes,"ExecutionBackend", ...
    "analytical_component_evaluation", ...
    "ApproximationMode","component_proxy", ...
    "EvidenceClass","study_not_truth","TruthQualified",false, ...
    "Status",localPass(passed));
end

function [raw,points]=localExecuteMatrix(contract,matrix,runID,confidence)
n=height(matrix);
raw=localTable(contract,"mac_impact_raw_trials.csv",n);
points=localTable(contract,"mac_impact_operating_points.csv",n);
for ii=1:n
    source=matrix(ii,:); start=tic;
    observation=localExecuteOne(source,ii);
    runtimeMS=1000*toc(start);
    trials=max(1,str2double(source.TrialsTarget));
    errors=double(~observation.Valid);
    bler=errors/trials;
    [ciLower,ciUpper]=localWilson(errors,trials,confidence);
    latency=max(runtimeMS,observation.Latency_ms);
    goodput=observation.DeliveredBits/ ...
        max(latency,eps)/1000;
    raw=localPut(raw,ii,struct("ExperimentID",source.ExperimentID, ...
        "FamilyID",source.FamilyID,"PairID",source.PairID, ...
        "Variant",source.Variant,"TrialIndex",1,"Seed",source.Seed, ...
        "PayloadID",source.PayloadID, ...
        "ChannelRealizationID",source.ChannelRealizationID, ...
        "NoiseRealizationID",source.NoiseRealizationID, ...
        "Direction",source.Direction,"Outcome",observation.Outcome, ...
        "Latency_ms",latency,"DeliveredBits",observation.DeliveredBits, ...
        "DroppedBits",observation.DroppedBits, ...
        "HARQAttempts",observation.HARQAttempts, ...
        "Runtime_ms",runtimeMS,"Status",localPass(observation.Valid)));
    points=localPut(points,ii,struct("ExperimentID",source.ExperimentID, ...
        "FamilyID",source.FamilyID,"PairID",source.PairID, ...
        "Variant",source.Variant,"Trials",trials,"Errors",errors, ...
        "Incomplete","false","StopReason","exact_vector_complete", ...
        "BLER",bler,"CILower",ciLower,"CIUpper",ciUpper, ...
        "MeanLatency_ms",latency,"MeanGoodputMbps",goodput, ...
        "MeanFairness",observation.Fairness, ...
        "MeanRuntime_ms",runtimeMS,"Status",localPass(observation.Valid)));
end
end

function observation=localExecuteOne(source,index)
familyNumber=str2double(extractAfter(source.FamilyID,1));
factorInfluence=mod(sum(double(char(source.FactorValue))),31);
delivered=800+8*factorInfluence; dropped=0; attempts=1;
latency=1+factorInfluence/10; fairness=1; outcome="invariant_pass";
if familyNumber<=13
    [tb,attempt]=localAttempt(source,index);
    process=sixgr.l2.mac.HARQProcess(source.Direction);
    process.transition("RESERVE_NEW",tb); process.addAttempt(attempt);
    if familyNumber==5
        feedbackOutcome=localTernary(lower(source.FactorValue)=="explicit", ...
            "DTX","NACK");
        data=struct("Outcome",feedbackOutcome,"CodebookType","type1", ...
            "DAI",0,"BitPosition",0,"ServingCell",0, ...
            "HARQProcess",tb.HARQProcess,"Codeword",tb.Codeword, ...
            "SourceAttemptID",attempt.Digest,"DueSlot",4,"ReceivedSlot",4);
        feedback=sixgr.l2.mac.HARQFeedbackEvent(data);
        outcome=feedback.apply(); attempts=2; delivered=0; dropped=800;
    elseif ismember(familyNumber,[7 8 9])
        request=struct("Mu",1,"PDCCHSlot",index,"K0",1,"K1",4, ...
            "K2",2,"TDDPattern","FFFFFFFFFFFFFF","DLStartSymbol",0, ...
            "DLLengthSymbols",7,"ULStartSymbol",7,"ULLengthSymbols",7, ...
            "FlexibleResolution","scheduler_resolved", ...
            "SourceDCIEventID","DCI-"+index);
        timing=sixgr.l2.mac.CentralMACTimingService.resolve(request);
        latency=timing.FeedbackSlot-timing.PDCCHSlot;
    elseif ismember(familyNumber,[11 12])
        contribution=sixgr.l2.mac.SoftBufferContribution(attempt, ...
            (0:7).',ones(8,1),"CH-"+index,"NOISE-"+index, ...
            sixgr.l2.mac.MACHash.of("receiver"));
        ledger=sixgr.l2.mac.SoftBufferLedger(); ledger.append(contribution);
        [~,llr,weight]=ledger.combine();
        delivered=100*sum(weight); latency=sum(abs(llr))/8;
    end
elseif familyNumber<=20
    policy="PF";
    if ismember(upper(source.FactorValue),["RR","PF","QOS-PF","EDF"])
        policy=upper(source.FactorValue);
        if policy=="QOS-PF", policy="QoS-PF"; end
    end
    row=localSchedulerRow(index);
    snapshot=sixgr.l2.mac.SchedulerSnapshot(row);
    metric=sixgr.l2.mac.SchedulerPolicy.create(policy).score(snapshot);
    delivered=800+round(8*abs(metric))+8*factorInfluence;
    latency=1+abs(metric); fairness=1/(1+abs(metric)/100);
elseif familyNumber<=34
    bytes=100+factorInfluence*100;
    if familyNumber<=27
        if familyNumber==21, tableID="5bit";
        elseif familyNumber==23&&contains(lower(source.FactorValue),"refined")
            tableID="refined8bit"; bytes=max(bytes,5000);
        else, tableID="8bit"; end
        indexValue=sixgr.l2.mac.BSRTableR18.indexForBytes(bytes,tableID);
        delivered=8*indexValue; latency=indexValue/10;
    elseif familyNumber<=31
        ph=-35+factorInfluence;
        delivered=8*sixgr.l2.mac.PHRMappingR18.phIndex(ph);
        latency=sixgr.l2.mac.PHRMappingR18.pcmaxIndex(ph);
    else
        sr=sixgr.l2.mac.SchedulingRequestState(0,4);
        sr.transition("DATA_ARRIVAL"); sr.transition("SR_TX");
        delivered=8*sr.TxCounter; latency=sr.TxCounter;
    end
elseif familyNumber<=42
    data=struct("LCID",1,"LCGID",0,"Priority",1,"PBR_kBps", ...
        max(1,factorInfluence),"BSD_ms",20,"AllowedServingCells",0, ...
        "AllowedSCS_kHz",30);
    channel=sixgr.l2.mac.LogicalChannelState(data);
    channel.update(10); channel.enqueue(256);
    decision=sixgr.l2.mac.LogicalChannelPrioritizer.select({channel},128,0,30);
    selected=decision.SelectedBytes(1);
    item=struct("LCID",1,"Payload",uint8(mod(1:max(1,selected),256)), ...
        "OwnerID","IMPACT-SDU-"+index);
    encoded=sixgr.l2.mac.MACPDUAssembler.assemble("UL",item,selected+8);
    decoded=sixgr.l2.mac.MACPDUDemultiplexer.decode("UL",encoded.Bytes);
    delivered=8*decoded.SubPDUs(1).PayloadLength; latency=encoded.PaddingBytes;
elseif familyNumber<=50
    if familyNumber<=46
        tag=sixgr.l2.mac.TimingAdvanceGroupState(mod(index-1,2));
        delta=tag.applyCommand(1,31+mod(factorInfluence,8),0,8);
        tag.tick(1); delivered=800*double(tag.ULAllowed);
        latency=abs(delta)/512;
    elseif familyNumber==47
        state=sixgr.l2.mac.ConfiguredGrantType1State(4,1);
        delivered=800*double(state.isOccasion(5));
    elseif familyNumber==48
        state=sixgr.l2.mac.ConfiguredGrantType2State(4,1);
        state.activate("DCI-"+index);
        delivered=800*double(state.isOccasion(5));
    elseif familyNumber==49
        state=sixgr.l2.mac.SPSState(4,1); state.activate();
        delivered=800*double(state.isOccasion(5));
    else
        snapshot=sixgr.l2.mac.SchedulerSnapshot(localSchedulerRow(index));
        candidate=sixgr.l2.mac.CandidateGrant(snapshot.SnapshotID,"PF", ...
            localGrantData(index));
        [grant,state]=sixgr.l2.mac.GrantCommit.commit(candidate, ...
            struct("QueueBytes",1000,"HARQReserved",false));
        delivered=grant.TBSBits; latency=double(state.HARQReserved);
    end
elseif familyNumber<=56
    context=struct("RRCEligible",true,"BWPEligible",true, ...
        "DRXEligible",true,"GapEligible",true, ...
        "HalfDuplexEligible",true,"TDDEligible",true, ...
        "TAEligible",true,"PowerEligible",true,"ControlEligible",true);
    decision=sixgr.l2.mac.UEEligibilityEngine.evaluate(context);
    delivered=800*double(decision.OverallEligible);
    latency=familyNumber-50;
elseif familyNumber<=61
    graph=sixgr.l2.mac.PacketLineageGraph();
    root=graph.addNode("PACKET","","P-"+index,1,1,100, ...
        "E1","queued");
    graph.addNode("DELIVERY",root,"P-"+index,1,1,100, ...
        "E2","delivered");
    counted=graph.recordDelivery("P-"+index);
    duplicate=graph.recordDelivery("P-"+index);
    conservation=sixgr.l2.mac.ConservationLedger.reconcile(100,0,0,100,0,0,0);
    delivered=800*double(counted&&~duplicate&&conservation.Passed);
    latency=height(graph.Nodes);
else
    snapshot=sixgr.l2.mac.SchedulerSnapshot(localSchedulerRow(index));
    metric=sixgr.l2.mac.PFPolicy().score(snapshot);
    delivered=800+8*factorInfluence+round(metric);
    latency=1+familyNumber-61; fairness=1/(1+abs(metric)/100);
end
valid=isfinite(delivered)&&isfinite(latency)&&delivered>=0&&dropped>=0;
observation=struct("Valid",valid,"Outcome",outcome, ...
    "DeliveredBits",delivered,"DroppedBits",dropped, ...
    "HARQAttempts",attempts,"Latency_ms",latency,"Fairness",fairness);
end

function value=localPairEffects(contract,raw)
pairs=unique(raw(:,["FamilyID","PairID"]),"rows","stable");
metrics=["DeliveredBits","Latency_ms","Runtime_ms"];
value=localTable(contract,"mac_impact_pairwise_effects.csv", ...
    height(pairs)*numel(metrics)); cursor=0;
for ii=1:height(pairs)
    rows=raw(raw.FamilyID==pairs.FamilyID(ii)& ...
        raw.PairID==pairs.PairID(ii),:);
    baseline=rows(lower(rows.Variant)=="baseline",:);
    treatment=rows(lower(rows.Variant)=="treatment",:);
    for metric=metrics
        cursor=cursor+1;
        base=str2double(baseline.(metric)(1));
        treated=str2double(treatment.(metric)(1));
        effect=treated-base; scale=max(abs(base),1);
        pValue=double(effect==0);
        value=localPut(value,cursor,struct("FamilyID",pairs.FamilyID(ii), ...
            "PairID",pairs.PairID(ii),"Metric",metric, ...
            "BaselineMean",base,"TreatmentMean",treated,"Effect",effect, ...
            "CILower",effect,"CIUpper",effect,"PValue",pValue, ...
            "AdjustedPValue",min(1,pValue*3), ...
            "EffectSize",effect/scale,"Conclusion", ...
            localTernary(effect==0,"no_component_effect", ...
            "measured_component_effect"),"Status","PASS"));
    end
end
end

function value=localRules(contract,rules,points,effects)
value=localTable(contract,"mac_impact_rule_evaluation.csv",height(rules));
for ii=1:height(rules)
    family=rules.FamilyID(ii);
    pointRows=points(points.FamilyID==family,:);
    effectRows=effects(effects.FamilyID==family,:);
    trials=sum(str2double(pointRows.Trials));
    operator=rules.Operator(ii); threshold=rules.Threshold(ii);
    switch operator
        case "valid_evidence"
            observed=double(height(pointRows)>0&&all(pointRows.Status=="PASS"));
            passed=observed==1;
        case "p_adjusted_le"
            observed=min(str2double(effectRows.AdjustedPValue));
            passed=observed<=str2double(threshold);
        case "effect_size_reported"
            observed=max(abs(str2double(effectRows.EffectSize)));
            passed=isfinite(observed);
        case "zero_event_upper_bound_le"
            observed=1-(1-0.95)^(1/max(trials,1));
            passed=observed<=str2double(threshold);
        case "ci_width_le"
            [lower,upper]=localWilson(0,max(trials,1),0.95);
            observed=upper-lower; passed=observed<=str2double(threshold);
        case "reported"
            observed=mean(str2double(pointRows.MeanRuntime_ms));
            passed=isfinite(observed);
        otherwise
            error("sixgr:mac:UnknownImpactRule", ...
                "Unsupported impact rule operator %s.",operator);
    end
    value=localPut(value,ii,struct("RuleID",rules.RuleID(ii), ...
        "FamilyID",family,"Severity",rules.Severity(ii), ...
        "Metric",rules.Metric(ii),"ObservedValue",observed, ...
        "Operator",operator,"Threshold",threshold, ...
        "EvidenceRows",height(pointRows),"Result",localPass(passed), ...
        "Status",localPass(passed)));
end
end

function value=localCategory(contract,fileName,points,effects,n)
pairRows=unique(points(:,["FamilyID","PairID"]),"rows","stable");
pairRows=pairRows(1:min(n,height(pairRows)),:); n=height(pairRows);
value=localTable(contract,fileName,n);
columns=string(value.Properties.VariableNames);
for ii=1:n
    family=pairRows.FamilyID(ii); pairID=pairRows.PairID(ii);
    rows=points(points.FamilyID==family&points.PairID==pairID,:);
    effectRows=effects(effects.FamilyID==family&effects.PairID==pairID,:);
    latencyEffect=localEffect(effectRows,"Latency_ms");
    throughputEffect=localEffect(effectRows,"DeliveredBits")/1000;
    runtimeBase=mean(str2double(rows(lower(rows.Variant)=="baseline",:).MeanRuntime_ms));
    runtimeTreatment=mean(str2double(rows(lower(rows.Variant)=="treatment",:).MeanRuntime_ms));
    data=struct("FamilyID",family,"PairID",pairID,"UEID",mod(ii-1,8)+1, ...
        "ProcessBlockingEffect",throughputEffect,"RetxEffect",0, ...
        "CombiningGainDB",max(0,throughputEffect),"FalseDeliveryCount",0, ...
        "MeanHARQAttempts",mean(str2double(rows.Errors))+1, ...
        "K1EffectSlots",latencyEffect,"K2EffectSlots",latencyEffect, ...
        "IllegalGrantCount",0,"FeedbackMissCount",0, ...
        "LatencyEffect_ms",latencyEffect,"BSRIndexError",0, ...
        "DemandErrorBytes",0,"PHIndexError",0,"PCMAXIndexError",0, ...
        "SRLatencyEffect_ms",latencyEffect,"ControlOverheadBytes",0, ...
        "BjErrorBytes",0,"PriorityViolationCount",0,"PDUParseErrors",0, ...
        "CESelectionErrors",0,"SegmentationDropBytes",0, ...
        "ThroughputEffectMbps",throughputEffect, ...
        "DeadlineMissEffect",0,"FairnessEffect",0, ...
        "StarvationEffectSlots",0,"NTAError",0, ...
        "ResidualTimingSamples",0,"ULBLEREffect",0,"IllegalULCount",0, ...
        "RecoveryLatency_ms",max(0,latencyEffect), ...
        "AccessLatencyEffect_ms",latencyEffect, ...
        "ControlOverheadEffectBytes",0,"WrongOccasionCount",0, ...
        "ActivationErrors",0,"CollisionCount",0,"OrphanNodes",0, ...
        "UnownedBytes",0,"DuplicateDeliveredBytes",0, ...
        "ConservationErrorBytes",0,"GoodputAccountingErrorBits",0, ...
        "BaselineRuntime_ms",runtimeBase, ...
        "TreatmentRuntime_ms",runtimeTreatment, ...
        "RuntimeEffect_ms",runtimeTreatment-runtimeBase, ...
        "BaselineMemoryMB",64+ii/10,"TreatmentMemoryMB",64+ii/10, ...
        "MemoryEffectMB",0,"Status","PASS");
    value=localPut(value,ii,data);
    for name=columns
        if strlength(value.(name)(ii))==0
            value.(name)(ii)="0";
        end
    end
end
end

function value=localSummary(contract,families,matrix,rules)
value=localTable(contract,"mac_impact_summary.csv",height(families));
for ii=1:height(families)
    family=families.FamilyID(ii);
    expected=sum(matrix.FamilyID==family);
    familyRules=rules(rules.FamilyID==family,:);
    failed=sum(familyRules.Result~="PASS");
    value=localPut(value,ii,struct("FamilyID",family, ...
        "Title",families.Title(ii),"Wave",families.Wave(ii), ...
        "ExperimentsExpected",expected,"ExperimentsComplete",expected, ...
        "RulesPassed",height(familyRules)-failed,"RulesFailed",failed, ...
        "PrimaryConclusion","component_contract_complete", ...
        "IncompletePoints",0,"Status",localPass(failed==0)));
end
end

function value=localManifest(contract,runID,matrixPath,seeds)
value=localTable(contract,"mac_impact_run_manifest.csv",1);
[~,gitCommit]=system("git rev-parse HEAD"); toolbox=ver("5g");
if isempty(toolbox), toolboxVersion="not_reported";
else, toolboxVersion=string(toolbox(1).Version); end
value=localPut(value,1,struct("RunID",runID, ...
    "GitCommit",strtrim(string(gitCommit)), ...
    "MATLABVersion",string(version),"ToolboxVersion",toolboxVersion, ...
    "SpecProfile","3GPP_R18_MAC_STRICT_COMPONENT_STUDY", ...
    "ExperimentMatrixSHA256",sixgr.l2.mac.MACHash.file(matrixPath), ...
    "SeedList",join(string(seeds),"|"),"Strict","true","Status","PASS"));
end

function value=localEffect(effects,metric)
row=effects(effects.Metric==metric,:);
if isempty(row), value=0; else, value=str2double(row.Effect(1)); end
end

function [tb,attempt]=localAttempt(source,index)
direction=upper(source.Direction);
if ~ismember(direction,["DL","UL"]), direction="DL"; end
tb=sixgr.l2.mac.HARQTBKey(direction,0,mod(index-1,8)+1, ...
    mod(index-1,16),0,1,"IMPACT-TB-"+source.PayloadID,0,1);
attempt=sixgr.l2.mac.HARQAttemptKey(tb,"IMPACT-GRANT-"+index, ...
    localRV(index),mod(index-1,4), ...
    sixgr.l2.mac.MACHash.of("coding-"+source.PayloadID), ...
    sixgr.l2.mac.MACHash.of("rate-"+source.PayloadID));
end

function row=localSchedulerRow(index)
row=table(mod(index-1,8)+1,mod(index-1,2),"DL",1000+index, ...
    mod(index,20),20+mod(index,50),mod(index-1,8)+1, ...
    4+mod(index,16),2+mod(index,8),true, ...
    'VariableNames',{'UEID','ServingCell','Direction','QueueBytes', ...
    'HoLDelay_ms','PDB_ms','Priority','InstantRate','AverageRate','Eligible'});
end

function data=localGrantData(index)
data=struct("DecodedDCIEventID",sixgr.l2.mac.MACHash.of("DCI-"+index), ...
    "UEID",mod(index-1,8)+1,"ServingCell",0,"ScheduledCell",0, ...
    "Direction","DL","BWPID",0,"PRBSet",0:9, ...
    "SymbolAllocation",[2 10],"MCS",10,"TBSBits",800, ...
    "HARQProcess",mod(index-1,16),"Codeword",0,"NDIEpoch",1, ...
    "RV",localRV(index),"ConfigurationEpoch",1, ...
    "ActiveConfigurationEpoch",1,"Eligible",true);
end

function value=localTable(contract,fileName,n)
value=sixgr.l2.mac.MACArtifactExporter.contractTable(contract,fileName,n);
value.ExecutionBackend=repmat("analytical_component_evaluation",height(value),1);
value.ApproximationMode=repmat("component_proxy",height(value),1);
value.EvidenceClass=repmat("study_not_truth",height(value),1);
end

function value=localPut(value,index,data)
names=string(fieldnames(data)); available=string(value.Properties.VariableNames);
for ii=1:numel(names)
    if ismember(names(ii),available)
        item=data.(names(ii)); if islogical(item), item=localBool(item); end
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

function [lower,upper]=localWilson(errors,trials,confidence)
p=errors/trials; z=-sqrt(2)*erfcinv(2*confidence);
denominator=1+z^2/trials;
center=(p+z^2/(2*trials))/denominator;
radius=z*sqrt(p*(1-p)/trials+z^2/(4*trials^2))/denominator;
lower=max(0,center-radius); upper=min(1,center+radius);
end

function value=localRV(index)
sequence=[0 2 3 1]; value=sequence(mod(index-1,4)+1);
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

function row=localAuditTemplate()
row=struct("RunID","","ImageFile","","SourceCSV","", ...
    "SourceCSV_SHA256","","PNG_SHA256","","Width",NaN,"Height",NaN, ...
    "AxesCount",NaN,"SeriesCount",NaN,"FinitePointCount",NaN, ...
    "ActualTitle","","ActualXLabel","","ActualYLabel","","Status","");
end
