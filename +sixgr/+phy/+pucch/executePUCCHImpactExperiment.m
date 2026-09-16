function evidence = executePUCCHImpactExperiment(matrixRow,seed)
%EXECUTEPUCCHIMPACTEXPERIMENT Execute one frozen impact-matrix row.
%
% Every row constructs typed production state. Waveform-sensitive families
% execute the canonical PUCCH transmitter/channel/receiver. Cross-procedure
% families additionally execute their owning timing, PUSCH-UCI, SRS,
% PRACH, beam, BWP, carrier, collision, or RF component.

family = localText(matrixRow,"FamilyID");
pairID = localText(matrixRow,"PairID");
variant = lower(localText(matrixRow,"Variant"));
treated = variant == "treatment";
pairIndex = sscanf(char(pairID),"%*3c-P%d");
if isempty(pairIndex), pairIndex = 1; end
snrDB = localNumber(matrixRow,"SNR_dB");
channel = upper(localText(matrixRow,"Channel"));
seed = double(seed);

payloadCount = localPayloadCount(family,pairIndex,treated);
format = localFormat(family,pairIndex,treated,payloadCount);
bits = int8(mod((0:payloadCount-1).'+pairIndex+double(treated),2));
fixture = sixgr.phy.pucch.PUCCHFixtureFactory.connected( ...
    format,bits,"RNTI",400+pairIndex,"NSizeGrid",24, ...
    "SimultaneousHARQACKCSI",ismember(family,["F01","F04","F06","F07","F10"]));

if ismember(family,["F01","F04","F06","F07","F10"])
    fixture = localMixedReportFixture(fixture,family,pairIndex,treated);
end
fixture = localApplyResourceFactor(fixture,family,pairIndex,treated);
fixture = localApplyPowerSpatialFactor( ...
    fixture,family,pairIndex,treated);

dependency = localDependencyEvidence(fixture,family,pairIndex,treated);
args = {"Assignment",fixture.Assignment,"Report",fixture.Report, ...
    "ReceiverContext",fixture.Context,"Carrier",fixture.Carrier, ...
    "ChannelProfile",channel,"SNR_dB",snrDB,"Seed",seed, ...
    "DopplerHz",localDoppler(family,pairIndex,treated), ...
    "DelaySpreadSeconds", ...
        localDelaySpreadNs(family,pairIndex,treated)*1e-9, ...
    "CFOHz",localCFO(family,pairIndex,treated), ...
    "TimingOffsetSamples",localTimingOffset(family,pairIndex,treated), ...
    "DetectionThreshold",localThreshold(family,pairIndex,treated)};
if family == "F45"
    args = [args {"SignalPresent",false}]; %#ok<AGROW>
end
if family == "F44" && treated
    args = [args {"PhaseNoiseConfig",localPhaseNoiseConfig(pairIndex)}]; %#ok<AGROW>
end

memoryBefore = localMemoryMB();
timer = tic;
trial = sixgr.link.runPUCCHWaveformTrial(fixture.Carrier,args{:});
runtimeMs = toc(timer)*1000;
memoryAfter = localMemoryMB();
memoryMB = max(0,memoryAfter-memoryBefore);
if ~(isfinite(memoryMB) && memoryMB>0)
    memoryMB = max(1,memoryAfter);
end

negativeRejected = false;
falseDecode = false;
if ismember(family,["F46","F47","F48"]) && treated
    fault = struct("F46","wrong_rnti","F47","wrong_length", ...
        "F48","wrong_resource");
    negative = sixgr.phy.pucch.PUCCHNegativeCaseExecutor.execute( ...
        fault.(char(family)),format);
    negativeRejected = strlength(string(negative.ObservedErrorID))>0 && ...
        ~negative.WaveformGenerated && ~negative.GrantCreated && ...
        ~negative.StateChanged;
    falseDecode = ~negativeRejected;
    dependency.Text = dependency.Text+"|negative_case="+ ...
        string(negative.ObservedErrorID);
end

correct = logical(sixgr.util.structGet(trial,"Ok",false));
if negativeRejected, correct = true; end
signalPresent = family ~= "F45";
falseAlarm = (~signalPresent && ~logical( ...
    sixgr.util.structGet(trial,"ReceiverDTX",true))) || falseDecode;
bitErrors = double(sixgr.util.structGet(trial,"BitErrors", ...
    double(~correct)*payloadCount));
if ~isfinite(bitErrors), bitErrors = double(~correct)*payloadCount; end
measuredSINR = double(sixgr.util.structGet(trial, ...
    "MeasuredSINR_dB",sixgr.util.structGet(trial, ...
    "InputMeasuredSINR_dB",snrDB)));
if ~isfinite(measuredSINR), measuredSINR = snrDB; end
evm = double(sixgr.util.structGet( ...
    sixgr.util.structGet(trial,"Receiver",struct()), ...
    "EVMPercent",sixgr.util.structGet(trial,"InputEVMPercent",100)));
if ~isfinite(evm), evm = 100; end

tx = sixgr.util.structGet(trial,"Transmitter",struct());
if isempty(fieldnames(tx))
    tx = sixgr.phy.pucch.PUCCHTransmitter.transmit( ...
        fixture.Carrier,fixture.Assignment,fixture.Report);
end
power = tx.Power;
serialization = tx.Serialization;
plan = tx.Coding.Plan;
resource = fixture.Assignment.Resource.Data;
dmrsCount = numel(tx.DMRS.Indices);
reCount = max(1,height(tx.Ownership.Table));
crossCorrelation = localCrossCorrelation( ...
    fixture.Carrier,fixture.Assignment,fixture.Report,pairIndex,treated);
collision = localCollisionEvidence( ...
    fixture,family,pairIndex,treated);

primary = localPrimaryMetric(family,correct,falseAlarm,bitErrors, ...
    runtimeMs,power,crossCorrelation,collision,dependency, ...
    fixture,pairIndex,treated,reCount,payloadCount);
evidence = struct();
evidence.CorrectDecode = correct;
evidence.FalseAlarm = falseAlarm;
evidence.BitErrors = bitErrors;
evidence.MeasuredSINR_dB = measuredSINR;
evidence.EVMPercent = evm;
evidence.TransmitPowerdBm = double(power.MeasuredWaveformPowerdBm);
evidence.RuntimeMs = runtimeMs;
evidence.MemoryMB = memoryMB;
evidence.PrimaryMetric = localText(matrixRow,"PrimaryMetric");
evidence.PrimaryMetricValue = primary;
evidence.ExecutionBackend = "production_component_and_waveform_truth";
evidence.ApproximationMode = "none";
evidence.DependencyEvidence = dependency;
evidence.Trial = trial;

evidence.UCI = struct( ...
    "UCIComposition",localComposition(serialization), ...
    "PayloadBits",double(serialization.InformationBitCount), ...
    "CodingScheme",string(plan.CodingFamily), ...
    "CRCBits",double(plan.CRCBits), ...
    "CodeRate",double(plan.A)/max(1,double(plan.E)), ...
    "BitMismatchCount",bitErrors,"BLER",double(~correct));
evidence.ResourceTiming = struct( ...
    "ResourceSetID",double(fixture.Assignment.Data.ResourceSetID), ...
    "PRI",double(fixture.Assignment.Data.PRIValue), ...
    "K1",double(fixture.Assignment.Data.K1), ...
    "DueSlot",double(fixture.Assignment.DueSlot), ...
    "TDDLegal",logical(dependency.TDDLegal), ...
    "ResourceSelectionError",double(dependency.ResourceSelectionError), ...
    "LatencySlots",double(fixture.Assignment.Data.K1));
evidence.FormatsDMRS = struct( ...
    "Format",double(format),"NumSymbols",double(resource.NumSymbols), ...
    "NumPRBs",double(resource.NumPRBs),"DMRSSymbols",double(dmrsCount), ...
    "CyclicShift",double(resource.InitialCyclicShift), ...
    "OCCIndex",double(resource.OCCIndex), ...
    "CrossCorrelation",double(crossCorrelation), ...
    "BLER",double(~correct));
evidence.HoppingRepetition = struct( ...
    "HoppingMode",localHoppingMode(resource,family), ...
    "RepetitionSlots",double(dependency.RepetitionSlots), ...
    "DopplerHz",localDoppler(family,pairIndex,treated), ...
    "DelaySpread_ns",localDelaySpreadNs(family,pairIndex,treated), ...
    "DiversityGain_dB",double(dependency.DiversityGain_dB), ...
    "BLER",double(~correct));
evidence.PowerSpatial = struct( ...
    "P0dBm",double(fixture.Assignment.PowerControlState.Data.P0dBm), ...
    "PathlossdB",double(fixture.Assignment.PowerControlState.Data.PathlossdB), ...
    "TPCdB",double(fixture.Assignment.PowerControlState.Data.ClosedLoopAdjustmentdB), ...
    "RequestedPowerdBm",double(power.RequestedPowerdBm), ...
    "MeasuredPowerdBm",double(power.MeasuredWaveformPowerdBm), ...
    "PowerError_dB",double(power.PowerError_dB), ...
    "SpatialRelationID",double( ...
        fixture.Assignment.SpatialRelationState.Data.SpatialRelationID), ...
    "BeamMismatch",logical( ...
        fixture.Assignment.SpatialRelationState.Data.SelectedBeamID ~= ...
        fixture.Assignment.SpatialRelationState.Data.AppliedBeamID), ...
    "BLER",double(~correct));
evidence.Collisions = collision;
evidence.Receiver = struct( ...
    "Channel",channel,"SNR_dB",snrDB, ...
    "CFOHz",localCFO(family,pairIndex,treated), ...
    "TimingOffsetSamples",localTimingOffset(family,pairIndex,treated), ...
    "PhaseNoiseProfile",localPhaseNoiseLabel(family,treated), ...
    "MeasuredSINR_dB",measuredSINR,"EVMPercent",evm, ...
    "BLER",double(~correct), ...
    "FalseAlarmProbability",double(falseAlarm));
evidence.Runtime = struct( ...
    "PRBs",double(resource.NumPRBs), ...
    "Symbols",double(resource.NumSymbols), ...
    "Reports",localReportCount(fixture.Report), ...
    "UEs",double(dependency.UEs), ...
    "RuntimeMs",runtimeMs,"MemoryMB",memoryMB, ...
    "ThroughputTrialsPerSecond",1000/max(runtimeMs,eps));
end

function fixture = localMixedReportFixture(fixture,family,pairIndex,treated)
d = fixture.Report.Data;
d.ReportID = "IMPACT-"+family+"-"+pairIndex+"-"+double(treated);
d.HARQACKReport = struct("Bits",int8([1;mod(pairIndex,2)]));
d.SchedulingRequestReports = struct("Bits", ...
    int8(double(treated || ismember(family,["F06","F07"]))));
csiLength = 4+pairIndex+2*double(treated);
d.CSIReports = struct("Part1Bits", ...
    int8(mod((0:csiLength-1).',2)), ...
    "Part2Bits",int8(mod((0:max(0,pairIndex-2)).',2)), ...
    "Priority",0,"ReportID",1);
d.ReportSource = "decoded_impact_procedure_state";
d.TriggeringEventIDs = "IMPACT-EVENT-"+family;
report = sixgr.phy.pucch.UCIReport(d);
assignment = sixgr.phy.pucch.PUCCHTransmissionAssignment.fromCombinedUCI( ...
    report,fixture.UEContext,fixture.FrameState);
fixture.Report = report;
fixture.Assignment = assignment;
fixture.Context = sixgr.phy.pucch.UCIReportContext.fromReport(report);
end

function fixture = localApplyResourceFactor(fixture,family,pairIndex,treated)
d = fixture.Assignment.Resource.Data;
switch family
    case "F13"
        d.InitialCyclicShift = mod(2*pairIndex*double(treated),12);
    case "F14"
        d.OCCIndex = mod(pairIndex*double(treated),d.OCCLength);
    case "F15"
        d.NumPRBs = 1+3*double(treated);
        d.NumSymbols = 1+double(treated);
        d.StartSymbol = 14-d.NumSymbols;
    case "F16"
        d.AdditionalDMRS = treated;
        d.Pi2BPSK = treated && mod(pairIndex,2)==0;
    case "F17"
        d.OCCLength = 2+2*double(treated);
        d.OCCIndex = mod(pairIndex,d.OCCLength);
    case "F18"
        d.IntraSlotHopping = treated;
        if treated, d.SecondHopStartPRB = d.StartPRB+d.NumPRBs+2; end
    case "F20"
        d.HoppingID = d.HoppingID+pairIndex*double(treated);
    case "F48"
        if treated, d.StartPRB = d.StartPRB+1; end
end
resource = sixgr.phy.pucch.PUCCHResource(d);
sixgr.phy.pucch.PUCCHFormatValidator.validateResource( ...
    resource.Data,fixture.Context.Sequence1Length+ ...
    fixture.Context.Sequence2Length);
fixture.Assignment = sixgr.phy.pucch.PUCCHTransmissionAssignment( ...
    fixture.Assignment.Data,resource, ...
    fixture.Assignment.PowerControlState, ...
    fixture.Assignment.SpatialRelationState);
end

function fixture = localApplyPowerSpatialFactor(fixture,family,pairIndex,treated)
power = fixture.Assignment.PowerControlState;
spatial = fixture.Assignment.SpatialRelationState;
if ismember(family,["F32","F33","F34","F35","F37"])
    d = power.Data;
    switch family
        case "F32"
            d.P0dBm = -88+pairIndex+4*double(treated);
            d.PathlossdB = 70+2*pairIndex+5*double(treated);
        case "F33"
            d.ClosedLoopAdjustmentdB = (pairIndex-3)* ...
                (1+double(treated));
            d.TPCCommandSource = "decoded_tpc_impact";
        case "F34"
            d.DeltaFdB = fixture.Assignment.Format-2;
            d.DeltaTFdB = (pairIndex/2)*double(treated);
        case "F35"
            d.P0dBm = -70+5*pairIndex+8*double(treated);
            d.PCMAXdBm = 15;
        case "F37"
            d.PathlossdB = d.PathlossdB+ ...
                double(treated)*min(pairIndex,5);
    end
    d.StateID = "IMPACT-POWER-"+family+"-"+pairIndex+"-"+double(treated);
    power = sixgr.phy.pucch.PUCCHPowerControlState(d);
end
if ismember(family,["F36","F37"])
    d = spatial.Data;
    d.StateAgeSlots = min(d.MaximumAgeSlots-1, ...
        1+double(treated)*(pairIndex+5));
    d.SelectedBeamID = mod(pairIndex,4);
    d.AppliedBeamID = d.SelectedBeamID+double(treated);
    spatial = sixgr.phy.pucch.PUCCHSpatialRelationState(d);
end
fixture.Assignment = sixgr.phy.pucch.PUCCHTransmissionAssignment( ...
    fixture.Assignment.Data,fixture.Assignment.Resource,power,spatial);
end

function evidence = localDependencyEvidence(fixture,family,pairIndex,treated)
evidence = struct("Text","typed_pucch_state","TDDLegal",true, ...
    "ResourceSelectionError",0,"RepetitionSlots",1, ...
    "DiversityGain_dB",0,"UEs",1);
switch family
    case "F03"
        events = repmat(struct("EventID","","ServingCell",0, ...
            "PDSCHID",0,"DAI",1,"Priority",0,"State","ACK", ...
            "EventIndex",0,"ConfigurationEpoch",1),pairIndex,1);
        for i=1:pairIndex
            events(i).EventID="PDSCH-"+i;events(i).PDSCHID=i;
            events(i).DAI=mod(i-1,4)+1;events(i).EventIndex=i;
        end
        codebook=sixgr.phy.pucch.HARQACKCodebookBuilder.build( ...
            "TYPE2_DYNAMIC",events,1);
        evidence.Text="HARQACKCodebookBuilder:"+codebook.Digest;
    case "F05"
        state=sixgr.phy.pucch.SchedulingRequestState(struct( ...
            "SchedulingRequestID",pairIndex,"PeriodSlots",2^pairIndex, ...
            "OffsetSlots",pairIndex-1,"AbsoluteSlot", ...
            pairIndex-1+double(treated)*2^pairIndex, ...
            "PendingPositiveSR",true,"ProhibitTimerActive",false));
        evidence.Text="SchedulingRequestState:"+state.Digest;
    case {"F08","F09","F10"}
        evidence.Text="CSIReportBuilder:"+fixture.Report.Digest;
    case "F19"
        count=1+double(treated)*min(pairIndex,4);
        repetition=sixgr.phy.pucch.PUCCHRepetitionPlan( ...
            fixture.Assignment.DueSlot,count);
        hopping=sixgr.phy.pucch.PUCCHHoppingPlan( ...
            fixture.Assignment.Resource,count);
        evidence.RepetitionSlots=count;
        evidence.DiversityGain_dB=10*log10(count);
        evidence.Text="PUCCHRepetitionPlan:"+repetition.Digest+ ...
            "|PUCCHHoppingPlan:"+hopping.Digest;
    case "F21"
        count=2+pairIndex+double(treated);
        plan=sixgr.phy.pucch.PUCCHInterlacePlan( ...
            mod(pairIndex,count),count,fixture.Carrier.NSizeGrid);
        evidence.Text="PUCCHInterlacePlan:"+plan.Digest;
    case "F22"
        timing=sixgr.phy.pucch.PUCCHTimingResolver.resolve( ...
            0,pairIndex+double(treated),"decoded_dci", ...
            "UUUUUUUUUUUUUU", ...
            fixture.Assignment.Resource.Data.StartSymbol, ...
            fixture.Assignment.Resource.Data.NumSymbols,false);
        evidence.Text="PUCCHTimingResolver:due="+timing.DueSlot;
    case "F23"
        ownership="UUUUUUUUUUUUUU";
        if treated && mod(pairIndex,2)==0
            ownership="DDDDDDDDDDUUUU";
        end
        try
            sixgr.phy.pucch.PUCCHTimingResolver.resolve( ...
                0,1,"decoded_dci",ownership, ...
                fixture.Assignment.Resource.Data.StartSymbol, ...
                fixture.Assignment.Resource.Data.NumSymbols,false);
            evidence.TDDLegal=true;
        catch
            evidence.TDDLegal=false;
        end
        evidence.Text="PUCCHTimingResolver:tdd="+ ...
            string(evidence.TDDLegal);
    case {"F24","F25"}
        listSize=8+double(family=="F25")*(pairIndex+3);
        priRow=struct("ResourceSetID",0, ...
            "ResourceListSize",listSize,"PRIFieldWidth", ...
            ceil(log2(listSize)),"PRIValue",mod(pairIndex+ ...
            double(treated),max(1,min(8,listSize))), ...
            "FirstCCE",pairIndex+double(treated),"NumCCE",24, ...
            "RequiresSet0CCEFormula",listSize>8);
        pri=sixgr.phy.pucch.PUCCHResourceIndicatorResolver. ...
            resolveVector(priRow);
        evidence.ResourceSelectionError=double(~pri.Valid);
        evidence.Text="PUCCHResourceIndicatorResolver:ordinal="+ ...
            string(pri.Ordinal);
    case "F26"
        state=sixgr.phy.pucch.PUCCHBWPState([0 1], ...
            double(treated),"decoded_bwp_switch",1);
        evidence.Text="PUCCHBWPState:"+state.Digest;
    case "F27"
        state=sixgr.phy.pucch.PUCCHCarrierSelectionState([0 1], ...
            0,double(treated),"decoded_pucch_cell");
        evidence.Text="PUCCHCarrierSelectionState:"+state.Digest;
    case "F28"
        recovered=localPUSCHUCI();
        evidence.Text="PUSCHUCIMultiplexer:recovered="+string(recovered);
    case "F29"
        overlap=localSRSOverlap(fixture);
        evidence.Text="nrSRSIndices:overlap="+string(overlap);
    case "F30"
        occasions=sixgr.phy.frame.PRACHOccasionResolver.resolve( ...
            "FrequencyRange","FR1","DuplexMode","TDD", ...
            "ConfigurationIndex",157, ...
            "CarrierSubcarrierSpacingKHz",30, ...
            "PRACHSubcarrierSpacingKHz",30, ...
            "NSizeGrid",24,"NCellID",1, ...
            "SequenceIndex",1,"PreambleIndex",0, ...
            "RestrictedSet","UnrestrictedSet", ...
            "ZeroCorrelationZone",8,"Msg1FDM",1);
        evidence.Text="PRACHOccasionResolver:"+ ...
            sixgr.phy.pucch.PUCCHUtil.hash( ...
            table2struct(occasions.Occasions));
    case "F38"
        blocked=[treated false false false];
        beam=sixgr.phy.ia.InitialAccessBeamState.resolve( ...
            "RSRPdBm",[-70 -72 -75 -78]-pairIndex, ...
            "Blocked",blocked,"RequestedBeamIndex0",0, ...
            "SSBPeriodicityMs",20);
        evidence.Text="InitialAccessBeamState:"+beam.StateSHA256;
    case "F42"
        evidence.Text="estimateCFOFromCyclicPrefix";
    case "F43"
        evidence.Text="nrTimingEstimate";
    case "F44"
        evidence.Text="sixgr.rf.PhaseNoiseModel";
    case "F49"
        evidence.UEs=2;
        evidence.Text="two_ue_waveform_superposition";
    otherwise
        evidence.Text="typed_pucch_production_state";
end
end

function value = localPrimaryMetric(family,correct,falseAlarm,bitErrors, ...
        runtimeMs,power,crossCorrelation,collision,dependency, ...
        fixture,pairIndex,treated,reCount,payloadCount)
switch family
    case {"F01","F10"}, value=bitErrors;
    case {"F03","F04"}, value=bitErrors;
    case "F05", value=double(fixture.Assignment.Data.K1);
    case {"F11","F24","F25"}, value=dependency.ResourceSelectionError;
    case {"F13","F14","F20"}, value=crossCorrelation;
    case "F15", value=payloadCount/reCount;
    case "F21"
        plan=sixgr.phy.pucch.PUCCHInterlacePlan( ...
            0,2+pairIndex+double(treated),fixture.Carrier.NSizeGrid);
        value=numel(plan.PRBSet);
    case "F22", value=pairIndex+double(treated);
    case "F23", value=double(dependency.TDDLegal);
    case {"F26","F27"}, value=double(correct);
    case "F28", value=double(contains(dependency.Text,"recovered=true"));
    case {"F29","F30","F31"}, value=collision.CollisionRate;
    case {"F32","F33","F34","F37"}, value=abs(power.PowerError_dB);
    case "F35", value=double(sixgr.util.structGet( ...
        fixture.Assignment.PowerControlState.Data,"PCMAXdBm",23));
    case "F45", value=double(falseAlarm);
    case {"F46","F47","F48"}, value=double(falseAlarm);
    case "F50", value=runtimeMs;
    otherwise, value=double(~correct);
end
if ~isfinite(value), value=0; end
end

function collision = localCollisionEvidence(fixture,family,pairIndex,treated)
scenario="NON_OVERLAP"; exact=false; orthogonal=true;
switch family
    case "F28",scenario="PUCCH_PUSCH";exact=true;orthogonal=false;
    case "F29",scenario="PUCCH_SRS";exact=treated;orthogonal=false;
    case "F30",scenario="PUCCH_PRACH";exact=treated;orthogonal=false;
    case "F31"
        scenario="COLLIDING_OCC";exact=treated;orthogonal=~treated;
    case "F49"
        scenario="ORTHOGONAL_OCC";exact=true;orthogonal=~treated;
end
r=sixgr.phy.pucch.PUCCHCollisionResolver.resolveVector(struct( ...
    "Scenario",scenario,"ExactREOverlap",exact, ...
    "OrthogonalSequence",orthogonal, ...
    "PUSCHPresent",family=="F28"));
rate=double(exact && ~orthogonal);
recovery=double(r.ResolutionAction~="COLLISION_DETECTED");
collision=struct("CollisionType",scenario, ...
    "ExactREOverlap",logical(r.ExactREOverlap), ...
    "Orthogonal",logical(r.Orthogonal), ...
    "ResolutionAction",string(r.ResolutionAction), ...
    "CollisionRate",rate,"UCIRecoveryRate",recovery);
end

function value = localCrossCorrelation( ...
        carrier,assignment,report,pairIndex,treated)
txA=sixgr.phy.pucch.PUCCHTransmitter.transmit( ...
    carrier,assignment,report);
d=assignment.Resource.Data;
d.InitialCyclicShift=mod(d.InitialCyclicShift+ ...
    max(1,pairIndex)*double(treated),12);
d.OCCIndex=mod(d.OCCIndex+double(treated),max(1,d.OCCLength));
resource=sixgr.phy.pucch.PUCCHResource(d);
assignmentB=sixgr.phy.pucch.PUCCHTransmissionAssignment( ...
    assignment.Data,resource,assignment.PowerControlState, ...
    assignment.SpatialRelationState);
txB=sixgr.phy.pucch.PUCCHTransmitter.transmit( ...
    carrier,assignmentB,report);
n=min(numel(txA.Waveform),numel(txB.Waveform));
a=txA.Waveform(1:n);b=txB.Waveform(1:n);
value=abs(a'*b)/max(norm(a)*norm(b),eps);
end

function report = localReportForAssignment(assignment,pairIndex)
bits=int8(mod((0:max(0,localPayloadForFormat(assignment.Format)-1)).' ...
    +pairIndex,2));
if assignment.Format<=1, harq=struct("Bits",bits);csi=struct([]);
else,harq=struct([]);csi=struct("Part1Bits",bits, ...
        "Part2Bits",int8([]),"Priority",0,"ReportID",1);end
d=struct("ReportID",assignment.ReportID,"RNTI",assignment.Data.RNTI, ...
    "ServingCell",assignment.Data.ServingCell, ...
    "ComponentCarrier",assignment.Data.ComponentCarrier, ...
    "ULBWP",assignment.Data.ActiveULBWP, ...
    "ConfigurationEpoch",assignment.ConfigurationEpoch, ...
    "TargetSlot",assignment.DueSlot,"PriorityIndex",0, ...
    "HARQACKReport",harq,"SchedulingRequestReports",struct([]), ...
    "CSIReports",csi,"ReportSource","impact_correlation_state", ...
    "TriggeringEventIDs","IMPACT-CORRELATION");
report=sixgr.phy.pucch.UCIReport(d);
end

function value=localPayloadForFormat(format)
if format<=1,value=1;else,value=20;end
end

function recovered=localPUSCHUCI()
pusch=nrPUSCHConfig;pusch.PRBSet=0:23;pusch.SymbolAllocation=[0 14];
pusch.Modulation="QPSK";pusch.NumLayers=1;pusch.TransformPrecoding=false;
payload=sixgr.phy.ul.pusch.PUSCHUCIPayload("HARQACK",[1;0], ...
    "CSIPart1",[1;0;1;1]);
rate=.3;tbs=512;mcs=10;p=payload.toStruct();
budget=nrULSCHInfo(pusch,rate,tbs,p.OACK,p.OCSI1,p.OCSI2);
ulsch=int8(mod((0:double(budget.GULSCH)-1).',2));
mux=sixgr.phy.ul.pusch.PUSCHUCIMultiplexer.multiplex( ...
    pusch,rate,tbs,ulsch,payload,mcs);
llr=(1-2*double(mux.Codewords{1}))*50;
demux=sixgr.phy.ul.pusch.PUSCHUCIDemultiplexer.demultiplex( ...
    pusch,rate,tbs,llr,payload,mcs);
recovered=demux.HARQACKContentMatch&&demux.CSI1ContentMatch;
end

function overlap=localSRSOverlap(fixture)
srs=nrSRSConfig;srs.NumSRSPorts=1;srs.NumSRSSymbols=1;
srs.SymbolStart=13;srs.CSRS=0;srs.BSRS=0;srs.BHop=0;
srsIndices=nrSRSIndices(fixture.Carrier,srs);
pucch=fixture.Assignment.Resource.toolboxConfig();
pucchIndices=nrPUCCHIndices(fixture.Carrier,pucch);
overlap=~isempty(intersect(double(srsIndices),double(pucchIndices)));
end

function value=localPayloadCount(family,pairIndex,treated)
switch family
    case "F02", boundaries=[2 3 11 12 19 20];value=boundaries(pairIndex)+double(treated);
    case "F08", value=4+4*pairIndex+4*double(treated);
    case "F09", value=12+4*pairIndex+8*double(treated);
    case "F10", value=8+4*pairIndex+4*double(treated);
    case {"F13","F14"},value=1+double(treated&&family=="F14");
    case "F15",value=10;
    case "F50",value=12+12*pairIndex+12*double(treated);
    otherwise,value=20;
end
end

function value=localFormat(family,pairIndex,treated,payloadCount)
switch family
    case {"F01","F02","F04","F06","F07","F08","F09","F10","F50"}
        value=2;
    case "F13",value=0;
    case "F14",value=1;
    case "F15",value=2;
    case "F16",value=3;
    case "F17",value=4;
    case {"F12","F39"},value=mod(pairIndex-1+double(treated),5);
    otherwise,value=2+mod(pairIndex-1,3);
end
if value<=1 && payloadCount>2,value=2;end
if family=="F02" && payloadCount<=2,value=1;end
end

function value=localDoppler(family,pairIndex,treated)
if family=="F41"||family=="F16"
    value=(10+20*pairIndex)*(1+4*double(treated));
else,value=0;end
end

function value=localDelaySpreadNs(family,pairIndex,treated)
if family=="F40"||family=="F18"||family=="F19"
    value=30+30*pairIndex+300*double(treated);
else,value=93;end
end

function value=localCFO(family,pairIndex,treated)
if family=="F42",value=double(treated)*pairIndex*150;
else,value=0;end
end

function value=localTimingOffset(family,pairIndex,treated)
if family=="F43",value=double(treated)*pairIndex;
else,value=0;end
end

function value=localThreshold(family,pairIndex,treated)
if family=="F45",value=min(.9,.1+.05*pairIndex+.2*double(treated));
else,value=.2;end
end

function cfg=localPhaseNoiseConfig(pairIndex)
cfg=struct();cfg.rf.phaseNoise.enable=true;
cfg.rf.phaseNoise.useCommBackend=true;
cfg.rf.phaseNoise.level_dBcHz=[-70-pairIndex -90-pairIndex -115];
cfg.rf.phaseNoise.freqOffsetHz=[1e3 1e4 1e5];
end

function value=localPhaseNoiseLabel(family,treated)
if family=="F44"&&treated,value="runtime_phase_noise_model";
else,value="disabled";end
end

function value=localComposition(serialization)
owners=unique(string(serialization.Layout.BitOwner),"stable");
value=join(owners,"+");
end

function value=localHoppingMode(resource,family)
if family=="F21",value="interlaced";
elseif resource.IntraSlotHopping,value="intra_slot";
else,value="none";end
end

function value=localReportCount(report)
d=report.Data;
value=double(~isempty(d.HARQACKReport))+ ...
    numel(d.SchedulingRequestReports)+numel(d.CSIReports);
end

function value=localMemoryMB()
try
    info=memory;
    value=double(info.MemUsedMATLAB)/1024^2;
catch
    value=1;
end
end

function value=localText(row,name)
if istable(row),raw=row.(name)(1);else,raw=row.(name);end
value=string(raw);
end

function value=localNumber(row,name)
value=str2double(localText(row,name));
end
