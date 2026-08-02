function tests = testPUCCHPhase05
%TESTPUCCHPHASE05 Mandatory Phase-05 PUCCH/UCI production checks.
tests = functiontests(localfunctions);
end

function testUCIReportObject(t)
f=fixture(2); verifyClass(t,f.Report,"sixgr.phy.pucch.UCIReport");
verifyTrue(t,f.Assignment.Data.ConnectedModeEvidenceEligible);
end

function testUCIReportSerialization(t)
f=fixture(2); s=sixgr.phy.pucch.UCIReportSerializer.serialize(f.Report);
verifyEqual(t,s.Sequence1.Bits,int8(mod((0:19).',2)));
end

function testUCICodingBoundaries(t)
expected=["NO_UCI","SMALL_BLOCK_1_2","SMALL_BLOCK_3_11", ...
    "POLAR","POLAR","POLAR"];
for k=1:6
    a=[0 2 11 12 19 20]; p=sixgr.phy.pucch.UCIEncodingPlan( ...
        a(k),max(32,a(k)*3)); verifyEqual(t,p.CodingFamily,expected(k));
end
end

function testUCIPrioritySerialization(t)
f=fixture(3); verifyEqual(t,f.Context.Data.PriorityIndex,0);
verifyEqual(t,f.Context.Sequence1Length,20);
end

function testHARQACKCodebookType1(t), verifyHARQ(t,"TYPE1_SEMISTATIC"); end
function testHARQACKCodebookType2(t), verifyHARQ(t,"TYPE2_DYNAMIC"); end
function testHARQACKCodebookType3(t), verifyHARQ(t,"TYPE3_ONESHOT"); end

function testSchedulingRequestState(t)
s=sixgr.phy.pucch.SchedulingRequestState(struct( ...
    "SchedulingRequestID",1,"PeriodSlots",10,"OffsetSlots",3, ...
    "AbsoluteSlot",13,"PendingPositiveSR",true, ...
    "ProhibitTimerActive",false,"Priority",0,"ResourceID",1));
verifyTrue(t,s.Data.IsOccasion);verifyTrue(t,s.Data.Transmit);
end

function testSchedulingRequestMultiplexing(t)
f=fixture(1); verifyEqual(t,f.Assignment.Resource.Format,1);
end

function testCSIReportBuilder(t)
v=readS("pucch_csi_report_test_vectors.csv");
s=sixgr.phy.pucch.CSIReportBuilder.buildVector(v(1,:));
verifyNotEmpty(t,s);
end

function testCSIPart2Serialization(t)
v=readS("pucch_csi_report_test_vectors.csv");
s=sixgr.phy.pucch.CSIReportBuilder.buildVector(v(1,:));
verifyGreaterThanOrEqual(t,s(1).Data.Part2PaddingBits,0);
end

function testPUCCHResourceSetSelection(t)
v=readS("pucch_resource_set_test_vectors.csv");
e=readS("expected_pucch_resource_selection.csv");
for i=1:height(v)
    r=sixgr.phy.pucch.PUCCHResourceSetResolver.resolveVector(v(i,:));
    verifyEqual(t,r.Valid,truth(e.ExpectedValid(i)));
    verifyEqual(t,string(r.ErrorID),text(e.ExpectedErrorID(i)));
end
end

function testPUCCHResourceIndicator(t)
v=readS("pucch_resource_indicator_test_vectors.csv");
e=readS("expected_pucch_resource_indicator_selection.csv");
for i=1:height(v)
    r=sixgr.phy.pucch.PUCCHResourceIndicatorResolver.resolveVector(v(i,:));
    verifyEqual(t,string(r.ErrorID),text(e.ExpectedErrorID(i)));
    verifyEqual(t,r.Valid,truth(e.ExpectedValid(i)));
end
end

function testPUCCHSet0LargeResourceList(t)
r=sixgr.phy.pucch.PUCCHResourceIndicatorResolver.resolveVector(struct( ...
    "ResourceSetID",0,"ResourceListSize",16,"PRIFieldWidth",3, ...
    "PRIValue",2,"FirstCCE",8,"NumCCE",24, ...
    "RequiresSet0CCEFormula",true));
verifyTrue(t,r.Valid);verifyGreaterThan(t,r.Ordinal,0);
end

function testPUCCHDynamicHARQAssignment(t)
f=fixture(0); verifyEqual(t,f.Assignment.Data.AssignmentSource,"combined_uci");
verifyEqual(t,f.Assignment.Data.PRIProvenance,"decoded_dci");
end

function testPUCCHSPSAssignment(t)
f=fixture(0); verifyNotEmpty(t,f.RRCContext.Data.SPSPUCCHANResources);
end

function testPUCCHSRAndCSIAssignments(t)
f=fixture(2);verifyNotEmpty(t,f.RRCContext.Data.SRResources);
verifyNotEmpty(t,f.RRCContext.Data.CSIResources);
end

function testPUCCHFormat0Complete(t), verifyFormat(t,0); end
function testPUCCHFormat1Complete(t), verifyFormat(t,1); end
function testPUCCHFormat2Complete(t), verifyFormat(t,2); end
function testPUCCHFormat3Complete(t), verifyFormat(t,3); end
function testPUCCHFormat4Complete(t), verifyFormat(t,4); end

function testPUCCHDMRSComplete(t)
for format=0:4
    f=fixture(format);d=sixgr.phy.pucch.PUCCHDMRS.generate( ...
        f.Carrier,f.Assignment.Resource);
    verifyNotEmpty(t,d.SequenceSHA256);verifyNotEmpty(t,d.IndexSHA256);
end
end

function testPUCCHHoppingAndRepetition(t)
f=fixture(3);p=sixgr.phy.pucch.PUCCHHoppingPlan( ...
    f.Assignment.Resource,2);verifyEqual(t,height(p.Rows),2);
r=sixgr.phy.pucch.PUCCHRepetitionPlan(5,4);verifyEqual(t,r.Slots,5:8);
end

function testPUCCHInterlacedMapping(t)
f=fixture(2);tx=sixgr.phy.pucch.PUCCHTransmitter.transmit( ...
    f.Carrier,f.Assignment,f.Report);
verifyGreaterThan(t,height(tx.Ownership.Table),0);
end

function testPUCCHK1TDDTiming(t)
r=sixgr.phy.pucch.PUCCHTimingResolver.resolve( ...
    7,4,"decoded_dci","UUUUUUUUUUUUUU",12,2,false);
verifyEqual(t,r.DueSlot,11);verifyFalse(t,r.SymbolShiftApplied);
end

function testPUCCHCollisionResolution(t)
r=sixgr.phy.pucch.PUCCHCollisionResolver.resolveVector(struct( ...
    "Scenario","PUCCH_PUSCH","ExactREOverlap",true, ...
    "OrthogonalSequence",false,"PUSCHPresent",true));
verifyEqual(t,r.ResolutionAction,"MULTIPLEX_UCI_ON_PUSCH");
end

function testPUCCHPUSCHMultiplexing(t), testPUCCHCollisionResolution(t); end

function testPUCCHPowerControl(t)
r=sixgr.phy.pucch.PUCCHPowerController.resolve( ...
    fixture(2).Assignment.PowerControlState);
verifyLessThanOrEqual(t,r.AppliedPowerdBm,23);
end

function testPUCCHSpatialRelation(t)
f=fixture(2);verifyEqual(t, ...
    f.Assignment.SpatialRelationState.Data.SelectedBeamID, ...
    f.Assignment.SpatialRelationState.Data.AppliedBeamID);
end

function testPUCCHNoNoiseRoundTrip(t)
trial=waveTrial(2,100,"AWGN",true);verifyTrue(t,trial.Ok);
verifyEqual(t,trial.BitErrors,0);
end

function testPUCCHAWGNCampaign(t)
for snr=[10 30]
    trial=waveTrial(2,snr,"AWGN",true);
    verifyTrue(t,trial.WaveformGenerated);
end
end

function testPUCCHTDLAndCDL(t)
for channel=["TDL-A","CDL-A"]
    trial=waveTrial(2,50,channel,true);
    verifyTrue(t,trial.WaveformGenerated);
    verifyEqual(t,trial.Channel.ExecutionBackend,"waveform_truth");
end
end

function testPUCCHFormat0FadingNoncoherent(t)
% Format 0 has no DM-RS by specification.  A fading receiver must use the
% physical sequence/cyclic-shift detector rather than reject the waveform
% or fabricate a channel estimate.
for channel=["TDL-A","CDL-A"]
    trial=waveTrial(0,50,channel,true);
    verifyTrue(t,trial.WaveformGenerated);
    verifyFalse(t,trial.ReceiverDecodeFailed, ...
        sprintf("Format-0 %s receiver failed: %s | %s",channel, ...
        string(trial.ErrorID),string(trial.ErrorMessage)));
    verifyTrue(t,trial.Ok);
    verifyTrue(t,trial.NoncoherentSequenceDetection);
    verifyEqual(t,string(trial.ChannelEstimationMode), ...
        "format0_noncoherent_sequence_detection");
    verifyFalse(t,trial.ChannelEstimateAttempted);
    verifyTrue(t,trial.ChannelEstimateAvailable);
    verifyEqual(t,trial.BitErrors,0);
end
end

function testPUCCHNoSignalFalseAlarm(t)
trial=waveTrial(0,20,"AWGN",false);verifyTrue(t,trial.ReceiverDTX);
end

function testPUCCHWrongRNTI(t), verifyNegative(t,"wrong_rnti"); end
function testPUCCHWrongLength(t), verifyNegative(t,"wrong_length"); end
function testPUCCHWrongResource(t), verifyNegative(t,"wrong_resource"); end

function testPUCCHNegativeMatrix(t)
v=readS("pucch_negative_test_vectors.csv");
for i=1:height(v)
    if v.FaultType(i)=="no_signal",continue;end
    r=sixgr.phy.pucch.PUCCHNegativeCaseExecutor.execute( ...
        v.FaultType(i),str2double(v.Format(i)));
    verifyEqual(t,r.ObservedErrorID,v.ExpectedErrorID(i));
    verifyFalse(t,r.WaveformGenerated||r.StateChanged||r.GrantCreated);
end
end

function testPUCCHArtifactGeneration(t)
out=tempname;mkdir(out);c=onCleanup(@()rmdir(out,"s")); %#ok<NASGU>
s=sixgr.phy.pucch.runPUCCHPhaseValidation( ...
    "VectorRoot",vectorRoot(),"OutputDir",out,"SeedList",11, ...
    "Strict",true,"FastTestMode",true);
verifyTrue(t,s.Passed);verifyEqual(t,s.CSVCount,23);verifyEqual(t,s.PNGCount,15);
verifyFalse(t,s.TruthQualified);
end

function verifyHARQ(t,type)
v=readS("pucch_harq_codebook_test_vectors.csv");
row=find(v.CodebookType==type,1);
s=sixgr.phy.pucch.HARQACKCodebookBuilder.buildVector(v(row,:));
verifyEqual(t,s.CodebookType,type);verifyNotEmpty(t,s.BitTokens);
end

function verifyFormat(t,format)
f=fixture(format);tx=sixgr.phy.pucch.PUCCHTransmitter.transmit( ...
    f.Carrier,f.Assignment,f.Report);
verifyEqual(t,f.Assignment.Format,format);
verifyTrue(t,f.Assignment.Data.ConnectedModeEvidenceEligible);
verifyGreaterThan(t,numel(tx.Waveform),0);
end

function verifyNegative(t,fault)
r=sixgr.phy.pucch.PUCCHNegativeCaseExecutor.execute(fault,0);
verifyNotEmpty(t,r.ObservedErrorID);verifyFalse(t,r.WaveformGenerated);
verifyFalse(t,r.StateChanged);verifyFalse(t,r.GrantCreated);
end

function trial=waveTrial(format,snr,channel,present)
f=fixture(format);
trial=sixgr.link.runPUCCHWaveformTrial(f.Carrier, ...
    "Carrier",f.Carrier,"Assignment",f.Assignment,"Report",f.Report, ...
    "ReceiverContext",f.Context,"ChannelProfile",channel, ...
    "SNR_dB",snr,"SignalPresent",logical(present),"Seed",1800+format);
end

function f=fixture(format)
f=sixgr.phy.pucch.PUCCHFixtureFactory.connected(format,[]);
end

function t=readS(name)
t=readtable(fullfile(vectorRoot(),name),"TextType","string", ...
    "VariableNamingRule","preserve");
end

function value=truth(input)
value=ismember(upper(strtrim(string(input))),["TRUE","1","YES","PASS"]);
end

function value=text(input)
value=string(input);
if ismissing(value),value="";end
end

function p=vectorRoot()
testDir=fileparts(mfilename("fullpath"));
p=fullfile(testDir,"vectors","pucch");
end
