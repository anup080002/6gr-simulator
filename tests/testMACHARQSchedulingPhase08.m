function tests=testMACHARQSchedulingPhase08
%TESTMACHARQSCHEDULINGPHASE08 Named Phase-08 production checks.
tests=functiontests(localfunctions);
end

function testMACEventStoreReplay(t), runCase(t); end
function testMACContextProjection(t), runCase(t); end
function testCentralMACTimingK0K1K2(t), runCase(t); end
function testCentralMACTimingTDD(t), runCase(t); end
function testHARQDLStateMachine(t), runCase(t); end
function testHARQULStateMachine(t), runCase(t); end
function testHARQIdentityKeys(t), runCase(t); end
function testHARQFeedbackACKNACKDTX(t), runCase(t); end
function testHARQCodebookBinding(t), runCase(t); end
function testHARQProcessExhaustion(t), runCase(t); end
function testHARQSoftBufferProvenance(t), runCase(t); end
function testHARQSoftCombiningGain(t), runCase(t); end
function testHARQResetAndFlush(t), runCase(t); end
function testSPSState(t), runCase(t); end
function testConfiguredGrantType1State(t), runCase(t); end
function testConfiguredGrantType2State(t), runCase(t); end
function testExactBSR5BitTable(t), runCase(t); end
function testExactBSR8BitTable(t), runCase(t); end
function testExactRefinedBSRTable(t), runCase(t); end
function testBSRTriggersAndTimers(t), runCase(t); end
function testBSRFormats(t), runCase(t); end
function testExactPHMapping(t), runCase(t); end
function testExactPCMAXMapping(t), runCase(t); end
function testPHRTriggersAndTimers(t), runCase(t); end
function testMultipleEntryPHR(t), runCase(t); end
function testSchedulingRequestState(t), runCase(t); end
function testSchedulingRequestFallback(t), runCase(t); end
function testLogicalChannelBj(t), runCase(t); end
function testLogicalChannelPriority(t), runCase(t); end
function testLogicalChannelRestrictions(t), runCase(t); end
function testMACSubheaderCodec(t), runCase(t); end
function testMACPDUAssemblyDemux(t), runCase(t); end
function testMACCEPriority(t), runCase(t); end
function testMACPDUNegativeMatrix(t), runCase(t); end
function testTimingAdvanceCommand(t), runCase(t); end
function testTimeAlignmentTimer(t), runCase(t); end
function testMultipleTAG(t), runCase(t); end
function testUEEligibilityEngine(t), runCase(t); end
function testAtomicGrantCommit(t), runCase(t); end
function testSchedulerRR(t), runCase(t); end
function testSchedulerPF(t), runCase(t); end
function testSchedulerQoSPF(t), runCase(t); end
function testSchedulerEDF(t), runCase(t); end
function testSchedulerRetransmissionPriority(t), runCase(t); end
function testSchedulerFairnessAndStarvation(t), runCase(t); end
function testSchedulerQoSAndDeadlines(t), runCase(t); end
function testTwoCellHARQIsolation(t), runCase(t); end
function testCrossCarrierGrantState(t), runCase(t); end
function testPacketLineageGraph(t), runCase(t); end
function testByteBitConservation(t), runCase(t); end
function testFirstSuccessDeduplication(t), runCase(t); end
function testMACNoNoiseClosedLoop(t), runCase(t); end
function testMACAWGNCampaign(t), runCase(t); end
function testMACTDLCampaign(t), runCase(t); end
function testMACCDLCampaign(t), runCase(t); end
function testMACFaultInjection(t), runCase(t); end
function testMACArtifactGeneration(t), runCase(t); end
function testMACImpactAnalysis(t), runCase(t); end
function testMACSerialParallelReproducibility(t), runCase(t); end
function testMACFullRepositoryRegression(t), runCase(t); end

function runCase(testCase)
root=fileparts(fileparts(mfilename("fullpath")));
vectorRoot=fullfile(root,"tests","vectors","mac");
stack=dbstack;
name=string(stack(2).name);
separator=strfind(name,">");
if ~isempty(separator), name=extractAfter(name,separator(end)); end
sixgr.l2.mac.MACSelfTest.runOne(name,vectorRoot);
verifyTrue(testCase,true);
end
