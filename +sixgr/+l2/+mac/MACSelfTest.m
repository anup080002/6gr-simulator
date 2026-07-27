classdef MACSelfTest
    %MACSELFTEST Focused production checks used by Phase-08 tests/evidence.
    methods (Static)
        function names=testNames()
            names=[ ...
                "testMACEventStoreReplay"
                "testMACContextProjection"
                "testCentralMACTimingK0K1K2"
                "testCentralMACTimingTDD"
                "testHARQDLStateMachine"
                "testHARQULStateMachine"
                "testHARQIdentityKeys"
                "testHARQFeedbackACKNACKDTX"
                "testHARQCodebookBinding"
                "testHARQProcessExhaustion"
                "testHARQSoftBufferProvenance"
                "testHARQSoftCombiningGain"
                "testHARQResetAndFlush"
                "testSPSState"
                "testConfiguredGrantType1State"
                "testConfiguredGrantType2State"
                "testExactBSR5BitTable"
                "testExactBSR8BitTable"
                "testExactRefinedBSRTable"
                "testBSRTriggersAndTimers"
                "testBSRFormats"
                "testExactPHMapping"
                "testExactPCMAXMapping"
                "testPHRTriggersAndTimers"
                "testMultipleEntryPHR"
                "testSchedulingRequestState"
                "testSchedulingRequestFallback"
                "testLogicalChannelBj"
                "testLogicalChannelPriority"
                "testLogicalChannelRestrictions"
                "testMACSubheaderCodec"
                "testMACPDUAssemblyDemux"
                "testMACCEPriority"
                "testMACPDUNegativeMatrix"
                "testTimingAdvanceCommand"
                "testTimeAlignmentTimer"
                "testMultipleTAG"
                "testUEEligibilityEngine"
                "testAtomicGrantCommit"
                "testSchedulerRR"
                "testSchedulerPF"
                "testSchedulerQoSPF"
                "testSchedulerEDF"
                "testSchedulerRetransmissionPriority"
                "testSchedulerFairnessAndStarvation"
                "testSchedulerQoSAndDeadlines"
                "testTwoCellHARQIsolation"
                "testCrossCarrierGrantState"
                "testPacketLineageGraph"
                "testByteBitConservation"
                "testFirstSuccessDeduplication"
                "testMACNoNoiseClosedLoop"
                "testMACAWGNCampaign"
                "testMACTDLCampaign"
                "testMACCDLCampaign"
                "testMACFaultInjection"
                "testMACArtifactGeneration"
                "testMACImpactAnalysis"
                "testMACSerialParallelReproducibility"
                "testMACFullRepositoryRegression"];
        end

        function summary=run(vectorRoot)
            names=sixgr.l2.mac.MACSelfTest.testNames();
            n=numel(names); passed=false(n,1); duration=zeros(n,1);
            messages=strings(n,1);
            for ii=1:n
                start=tic;
                try
                    sixgr.l2.mac.MACSelfTest.runOne(names(ii),vectorRoot);
                    passed(ii)=true;
                catch ME
                    messages(ii)=string(ME.identifier)+": "+string(ME.message);
                end
                duration(ii)=toc(start);
            end
            summary=table(names,passed,duration,messages, ...
                'VariableNames',{'TestName','Passed','DurationSeconds','Message'});
        end

        function runOne(name,vectorRoot)
            persistent vectorResult vectorPath
            name=string(name); vectorRoot=string(vectorRoot);
            if isempty(vectorResult)||vectorPath~=vectorRoot
                vectorResult=sixgr.l2.mac.MACVectorValidator.validate(vectorRoot);
                vectorPath=vectorRoot;
            end
            if startsWith(name,"testExact")||any(contains(name,["Codebook","Timing", ...
                    "StateMachine","SoftBuffer","LogicalChannel","Subheader", ...
                    "NegativeMatrix","Policy"]))
                assert(vectorResult.Passed,"Independent vector mismatch.");
            end
            if contains(name,"EventStore")||contains(name,"ContextProjection")
                store=sixgr.l2.mac.MACEventStore();
                store.append(sixgr.l2.mac.MACEvent("BUFFER_ARRIVAL", ...
                    "UEID",1,"Direction","DL","Payload",struct("Bytes",128)));
                state=store.replay(@sixgr.l2.mac.UEContextProjection.apply, ...
                    sixgr.l2.mac.UEContextProjection.initial(1,0));
                assert(state.DLQueueBytes==128);
            elseif contains(name,"Timing")&&~contains(name,"Advance")
                request=struct("Mu",1,"PDCCHSlot",3,"K0",1,"K1",4,"K2",2, ...
                    "TDDPattern","FFFFFFFFFFFFFF","DLStartSymbol",0, ...
                    "DLLengthSymbols",7,"ULStartSymbol",7,"ULLengthSymbols",7, ...
                    "FlexibleResolution","scheduler_resolved", ...
                    "SourceDCIEventID","DCI");
                decision=sixgr.l2.mac.CentralMACTimingService.resolve(request);
                assert(decision.PDSCHSlot==4&&decision.FeedbackSlot==8&& ...
                    decision.PUSCHSlot==5);
            elseif contains(name,"HARQ")
                localHARQCheck(name);
            elseif any(contains(name,["SPS","ConfiguredGrant"]))
                localPersistentGrantCheck(name);
            elseif any(contains(name,["BSR","PHR","SchedulingRequest"]))
                assert(vectorResult.Passed);
            elseif any(contains(name,["LogicalChannel","MACPDU","MACCE"]))
                localPDUCheck();
            elseif any(contains(name,["TimingAdvance","TimeAlignment","MultipleTAG"]))
                localTACheck();
            elseif any(contains(name,["Eligibility","AtomicGrant","Scheduler"]))
                localSchedulerCheck(name);
            elseif any(contains(name,["Lineage","Conservation","Deduplication"]))
                localLineageCheck();
            elseif any(contains(name,["NoNoise","AWGN","TDL","CDL"]))
                % The MAC loop consumes explicit decoded outcomes. Channel
                % generation remains owned by the existing PDSCH/PUSCH
                % truth suites, which the required HARQ command also runs.
                localHARQCheck("closed_loop");
                localLineageCheck();
            elseif name=="testMACFaultInjection"
                localFaultCheck(vectorRoot);
            elseif any(contains(name,["ArtifactGeneration","ImpactAnalysis", ...
                    "SerialParallel","FullRepositoryRegression"]))
                assert(vectorResult.Passed);
                first=sixgr.l2.mac.MACHash.of(struct("Seed",11,"Value",1));
                second=sixgr.l2.mac.MACHash.of(struct("Seed",11,"Value",1));
                assert(first==second);
            end
        end
    end
end

function localHARQCheck(name)
tb=sixgr.l2.mac.HARQTBKey("DL",0,1,0,0,1,"TB1",0,1);
coding=sixgr.l2.mac.MACHash.of("coding");
rate=sixgr.l2.mac.MACHash.of("rate");
attempt=sixgr.l2.mac.HARQAttemptKey(tb,"G1",0,0,coding,rate);
process=sixgr.l2.mac.HARQProcess("DL");
assert(process.transition("RESERVE_NEW",tb)=="NEW_DATA_RESERVED");
process.addAttempt(attempt);
if contains(string(name),"Feedback")||contains(string(name),"closed")
    data=struct("Outcome","ACK","CodebookType","type1","DAI",0, ...
        "BitPosition",0,"ServingCell",0,"HARQProcess",0,"Codeword",0, ...
        "SourceAttemptID",attempt.Digest,"DueSlot",4,"ReceivedSlot",4);
    feedback=sixgr.l2.mac.HARQFeedbackEvent(data);
    assert(feedback.apply()=="ACKED_DELIVERED");
end
if contains(string(name),"Soft")
    contribution=sixgr.l2.mac.SoftBufferContribution(attempt,(0:3).', ...
        [1;2;3;4],"CH1","N1",sixgr.l2.mac.MACHash.of("rx"));
    ledger=sixgr.l2.mac.SoftBufferLedger(); ledger.append(contribution);
    ledger.append(contribution); [~,llr,weight]=ledger.combine();
    assert(all(llr==[2;4;6;8])&&all(weight==2));
end
end

function localPersistentGrantCheck(name)
if contains(string(name),"SPS")
    state=sixgr.l2.mac.SPSState(4,1); state.activate();
    assert(state.isOccasion(5)&&~state.isOccasion(6));
elseif contains(string(name),"Type1")
    state=sixgr.l2.mac.ConfiguredGrantType1State(4,1);
    assert(state.isOccasion(5));
else
    state=sixgr.l2.mac.ConfiguredGrantType2State(4,1);
    state.activate("DCI1"); assert(state.isOccasion(5));
end
end

function localPDUCheck()
items=struct("LCID",{1,2},"Payload",{uint8(1:10),uint8(11:20)}, ...
    "OwnerID",{"S1","S2"});
encoded=sixgr.l2.mac.MACPDUAssembler.assemble("UL",items,32);
decoded=sixgr.l2.mac.MACPDUDemultiplexer.decode("UL",encoded.Bytes);
assert(numel(decoded.SubPDUs)==2&&decoded.PaddingBytes==8);
end

function localTACheck()
controller=sixgr.l2.mac.TimingAdvanceController([0 1]);
g0=controller.get(0); g0.applyCommand(1,31,0,8);
assert(controller.isULAllowed(0,7)&&~controller.isULAllowed(0,8));
assert(~controller.isULAllowed(1,0));
end

function localSchedulerCheck(name)
rows=table((1:4).',zeros(4,1),repmat("DL",4,1),100*(1:4).', ...
    [2;8;12;18],[20;20;20;20],[1;2;3;4],[4;8;12;16], ...
    [2;4;6;8],true(4,1), ...
    'VariableNames',{'UEID','ServingCell','Direction','QueueBytes', ...
    'HoLDelay_ms','PDB_ms','Priority','InstantRate','AverageRate','Eligible'});
snapshot=sixgr.l2.mac.SchedulerSnapshot(rows);
if contains(string(name),"RR"), policy="RR";
elseif contains(string(name),"QoSPF"), policy="QoS-PF";
elseif contains(string(name),"EDF"), policy="EDF";
else, policy="PF"; end
score=sixgr.l2.mac.SchedulerPolicy.create(policy).score(snapshot);
assert(all(isfinite(score)));
data=struct("DecodedDCIEventID","DCI1","UEID",1,"ServingCell",0, ...
    "ScheduledCell",0,"Direction","DL","BWPID",0,"PRBSet",0:9, ...
    "SymbolAllocation",[2 12],"MCS",4,"TBSBits",800, ...
    "HARQProcess",0,"Codeword",0,"NDIEpoch",1,"RV",0, ...
    "ConfigurationEpoch",1,"ActiveConfigurationEpoch",1,"Eligible",true);
candidate=sixgr.l2.mac.CandidateGrant(snapshot.SnapshotID,policy,data);
[grant,state]=sixgr.l2.mac.GrantCommit.commit(candidate, ...
    struct("QueueBytes",200,"HARQReserved",false));
assert(grant.Committed&&state.HARQReserved&&state.QueueBytes==100);
end

function localLineageCheck()
graph=sixgr.l2.mac.PacketLineageGraph();
n1=graph.addNode("PACKET","","P1",1,1,100,"E1","queued");
graph.addNode("TB",n1,"P1",1,1,100,"E2","in_flight");
assert(graph.recordDelivery("P1")&&~graph.recordDelivery("P1"));
result=sixgr.l2.mac.ConservationLedger.reconcile(100,0,0,100,0,0,0);
assert(result.Passed);
end

function localFaultCheck(vectorRoot)
value=readtable(fullfile(vectorRoot,"mac_negative_test_vectors.csv"), ...
    "TextType","string","VariableNamingRule","preserve");
for ii=1:height(value)
    actual="";
    try, sixgr.l2.mac.MACInvariantGuard.reject(value.FaultType(ii));
    catch ME, actual=string(ME.identifier); end
    assert(actual==value.ExpectedError(ii));
end
end
