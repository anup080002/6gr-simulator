function tests = testMIMOCSIBeamformingPhase07Core
%TESTMIMOCSIBEAMFORMINGPHASE07CORE Focused production/vector Phase-07 tests.
tests = functiontests(localfunctions);
end

function setupOnce(~)
setup6GRSimToolkit("Verbose",false);
end

function testMIMOCapabilityProfile(testCase)
r = localVectors();
verifyEqual(testCase,sum(r.Capability.MismatchCount),0);
verifyEqual(testCase,height(r.Capability),164);
end

function testAntennaPanelGeometry(testCase)
r = localVectors();
verifyEqual(testCase,sum(r.Antenna.MismatchCount),0);
verifyEqual(testCase,height(r.Antenna),1860);
end

function testLogicalPhysicalPortMapping(testCase)
r = localVectors();
verifyEqual(testCase,sum(r.PortMapping.MismatchCount),0);
end

function testTypeI2PortCodebook(testCase)
r = localVectors();
verifyEqual(testCase,sum(r.TypeI2Port.MismatchCount),0);
verifyLessThanOrEqual(testCase,max(r.TypeI2Port.AbsoluteError),1e-12);
end

function testCSIReportConfigMaterializer(testCase)
r = localVectors();
verifyEqual(testCase,sum(r.CSIReportSchema.MismatchCount),0);
verifyEqual(testCase,height(r.CSIReportSchema),41);
end

function testCSIReportPUCCHSerialization(testCase)
request = localReportRequest("PUCCH");
cfg = sixgr.phy.mimo.CSIReportConfiguration(request,3);
report = cfg.build(struct("CRI",1,"RI",1,"CQI_CW0",9,"PMI",1,"LI",0));
decoded = cfg.encodeDecodeNoNoise(report);
verifyEqual(testCase,decoded.Part1BitErrors,0);
verifyEqual(testCase,decoded.Part2BitErrors,0);
verifyTrue(testCase,decoded.CRCPassed);
verifyFalse(testCase,report.CustomContainerUsed);
end

function testCSIReportPUSCHSerialization(testCase)
request = localReportRequest("PUSCH");
cfg = sixgr.phy.mimo.CSIReportConfiguration(request,3);
report = cfg.build(struct("CRI",0,"RI",2,"CQI_CW0",7,"PMI",1,"LI",1));
decoded = cfg.encodeDecodeNoNoise(report);
verifyEqual(testCase,decoded.Part1BitErrors+decoded.Part2BitErrors,0);
verifyEqual(testCase,cfg.UCIChannel,"PUSCH");
end

function testCovarianceEstimatorPSD(testCase)
r = localVectors();
verifyEqual(testCase,sum(r.Covariance.MismatchCount),0);
rng(71,"twister");
samples = (randn(64,2)+1i*randn(64,2))*[1 .6;.1 .8];
state = sixgr.phy.mimo.InterferenceCovarianceState.estimate(samples, ...
    MinSamples=16,ShrinkageFactor=.05);
verifyGreaterThanOrEqual(testCase,state.MinEigenvalue,-1e-10);
verifyLessThanOrEqual(testCase,state.HermitianError,1e-12);
end

function testStrictIRCNoFallback(testCase)
verifyError(testCase,@()sixgr.phy.rx.mimoDetect( ...
    ones(8,2),eye(2),.1,"Algorithm","IRC"), ...
    "sixgr:mimo:MissingInterferenceCovariance");
H = repmat(reshape(eye(2),1,2,2),8,1,1);
[~,~,info] = sixgr.phy.rx.mimoDetect(ones(8,2),H,.1, ...
    "Algorithm","IRC","Rint",eye(2));
verifyEqual(testCase,string(info.AlgorithmUsed),"IRC");
verifyEqual(testCase,string(info.EngineUsed),"manualIRC");
end

function testStrictIRCQualifiedCovarianceState(testCase)
rng(72,"twister");
samples = (randn(64,2)+1i*randn(64,2))*[1 .5;.1 .7];
state = sixgr.phy.mimo.InterferenceCovarianceState.estimate(samples, ...
    CovarianceID="IRC-PRG2",MinSamples=16,Slot=8, ...
    MaxAgeSlots=3,PRGID=2,ShrinkageFactor=.1);
H = repmat(reshape(eye(2),1,2,2),12,1,1);
[~,~,info] = sixgr.phy.rx.mimoDetect(ones(12,2),H,.01, ...
    "Algorithm","IRC","Rint",state,"Strict",true, ...
    "CurrentSlot",10,"PRGID",2);
verifyTrue(testCase,info.CovarianceStateUsed);
verifyEqual(testCase,info.CovarianceID,"IRC-PRG2");
verifyEqual(testCase,info.CovarianceAgeSlots,2);
verifyFalse(testCase,info.FallbackUsed);
end

function testPrecoderMatrixConvention(testCase)
r = localVectors();
verifyEqual(testCase,sum(r.Precoder.MismatchCount),0);
W = sixgr.phy.mimo.TypeI2PortCodebook.matrix(2,0);
d = sixgr.phy.mimo.MatrixContract.digest(W);
[~,info] = sixgr.phy.mimo.precoder(ones(10,2),W, ...
    "Strict",true,"ExpectedDigest",d);
verifyEqual(testCase,info.Orientation,"Nport_by_Nlayer");
verifyEqual(testCase,info.AppliedMatrixSHA256,d);
end

function testMUMIMO2UE(testCase)
r = localVectors();
verifyEqual(testCase,sum(r.MUMIMO.MismatchCount),0);
ctx = sixgr.phy.mimo.MUMIMOTransmissionContext( ...
    UEIDs=["UE1","UE2"],SharedPRBs=0:23,SharedSymbols=2:13, ...
    DMRSIdentities=[0 1],Precoders={1,1},PowerDBM=[0 -3]);
x = ctx.combine({ones(32,1),1i*ones(32,1)});
verifySize(testCase,x,[32 1]);
verifyGreaterThan(testCase,mean(abs(x).^2),0);
end

function testMultiTRPContexts(testCase)
r = localVectors();
verifyEqual(testCase,sum(r.MultiTRP.MismatchCount),0);
ctx = sixgr.phy.mimo.MultiTRPTransmissionContext(Mode="CJT", ...
    TRPIDs=["TRP1","TRP2"],TCIStateIDs=[1 2]);
x = ctx.combineSamples({ones(16,1),ones(16,1)});
verifyEqual(testCase,x,2*ones(16,1),"AbsTol",1e-12);
end

function testHybridBeamformerRFChainLimit(testCase)
r = localVectors();
verifyEqual(testCase,sum(r.Hybrid.MismatchCount),0);
h = sixgr.phy.mimo.HybridBeamformer(Nant=16,NRFChains=2,NStreams=2, ...
    PhaseQuantizationBits=4,CenterFrequencyHz=28e9,BandwidthHz=400e6);
W = h.compositeWeights();
verifySize(testCase,W,[16 2]);
verifyEqual(testCase,sum(abs(W(:)).^2),1,"AbsTol",1e-12);
end

function testBeamStateTransitions(testCase)
r = localVectors();
verifyEqual(testCase,sum(r.BeamState.MismatchCount),0);
sm = sixgr.phy.beam.BeamManagementStateMachine();
sm.transition("AUTO_EVENT_FOR_P1_MEASURING");
sm.transition("AUTO_EVENT_FOR_P1_REPORTED",MeasuredResourceID="SSB-1", ...
    MeasuredRSRPDBM=-80,MeasuredSINRDB=10);
sm.transition("AUTO_EVENT_FOR_TCI_PENDING",MeasuredResourceID="CSI-RS-1");
sm.transition("AUTO_EVENT_FOR_TCI_ACTIVE",MeasuredResourceID="CSI-RS-1", ...
    ActivatedTCIState=4);
sm.transition("AUTO_EVENT_FOR_DATA_ACTIVE",MeasuredResourceID="CSI-RS-1");
verifyEqual(testCase,sm.State,"DATA_ACTIVE");
verifyEqual(testCase,sm.AppliedBeamID,"CSI-RS-1");
end

function testMIMONegativeVectors(testCase)
t = sixgr.phy.mimo.runNegativeVectorValidation(localVectorRoot());
verifyEqual(testCase,height(t),38);
verifyTrue(testCase,all(t.Passed));
verifyFalse(testCase,any(t.WaveformGenerated|t.StateChanged|t.GrantCreated));
end

function testDLClosedLoopCSISelection(testCase)
request = localReportRequest("PUCCH");
cfg = struct("Strict",true,"N1",1,"N2",1,"O1",1,"O2",1, ...
    "MaxRank",2,"RankDomain",[1 2],"NoiseVariance",.01, ...
    "ReportConfiguration",request,"ReportConfigurationEpoch",3);
H = [1 .2;.1 .9];
measurement = sixgr.phy.mimo.CSIMeasurementState( ...
    MeasurementID="csi-meas-3",UEID="UE1",ResourceType="NZP-CSI-RS", ...
    ResourceID="CSI-RS-1",Slot=12,MaxAgeSlots=4, ...
    ChannelEstimate=H,NoiseVariance=.01);
cfg.CurrentSlot = 12;
csi = sixgr.mimo.buildCSIFeedback(H,.01,cfg,"NominalRank",2, ...
    "MeasurementState",measurement);
verifyFalse(testCase,csi.ConfiguredSNRUsed);
verifyFalse(testCase,csi.SVDThresholdUsed);
verifyFalse(testCase,csi.CustomContainerUsed);
verifyEqual(testCase,csi.PrecoderMatrixSHA256, ...
    sixgr.phy.mimo.MatrixContract.digest(csi.Precoder_W));
end

function testULClosedLoopSRSAuthority(testCase)
H = [1 .2 .1 0;.1 .9 0 .2;0 .1 .8 .1;.1 0 .2 .7];
cfg = struct("Strict",true,"NoiseVar",.01);
cfg.phy.pusch.transmissionScheme = "codebook";
cfg.phy.pusch.NumAntennaPorts = 4;
cfg.phy.pusch.codebookType = "codebook1_ng1n4n1";
[W,~,~,~,info] = sixgr.mimo.selectULBeamFromSRS([],[],H,[],cfg);
verifyTrue(testCase,info.MeasurementAuthoritative);
verifyFalse(testCase,info.ConfiguredOverrideUsed);
verifyEqual(testCase,size(W,1),4);
verifyEqual(testCase,info.SelectionMatrixSHA256,info.AppliedMatrixSHA256);
end

function testMeasuredBeamSelectionNoGeometryOracle(testCase)
measurements = permute([-92 -84 -88;-91 -89 -81],[1 3 2]);
[beam,gain,evidence] = sixgr.system.selectBestBeamPerLink( ...
    [10 0;20 0],[0 0],0,3,120,18, ...
    "Measurements",measurements,"Strict",true, ...
    "MeasurementResourceIDs",["SSB0","SSB1","SSB2"]);
verifyEqual(testCase,beam,[2;3]);
verifyEqual(testCase,gain,[-84;-81]);
verifyFalse(testCase,evidence.GeometryOracleUsed);
verifyEqual(testCase,evidence.SelectionSource,"measured_reference_signal");
end

function testStrictBeamGeometryRejected(testCase)
verifyError(testCase,@()sixgr.system.selectBestBeamPerLink( ...
    [10 0],[0 0],0,4,120,18,"Strict",true), ...
    "sixgr:mimo:BeamMeasurementOracleForbidden");
end

function testStrictSpatialCompositeMU(testCase)
W1 = sixgr.phy.mimo.TypeI2PortCodebook.matrix(1,0);
W2 = sixgr.phy.mimo.TypeI2PortCodebook.matrix(1,2);
ctx = sixgr.phy.mimo.MUMIMOTransmissionContext( ...
    UEIDs=["UE1","UE2"],SharedPRBs=0:3,SharedSymbols=2:5, ...
    DMRSIdentities=[10 11],Precoders={W1,W2},PowerDBM=[0 0]);
tx = [localSpatialTx("UE1","TX1",10,W1,ones(16,1)); ...
      localSpatialTx("UE2","TX2",11,W2,1i*ones(16,1))];
rx = repmat(struct("UserId","","Channel",{{}}),2,1);
rx(1).UserId = "UE1"; rx(1).Channel = {eye(2),.2*eye(2)};
rx(2).UserId = "UE2"; rx(2).Channel = {.2*eye(2),eye(2)};
out = sixgr.mimo.executeSpatialComposite(tx,rx,struct(), ...
    "Strict",true,"TransmissionContext",ctx,"NoiseVariance",.01);
verifyTrue(testCase,out.Strict);
verifyTrue(testCase,out.SimultaneousSharedPRB);
verifyFalse(testCase,out.FallbackUsed);
verifyEqual(testCase,numel(out.PrecoderSHA256),2);
verifyGreaterThan(testCase,out.SumRate_bpsHz,0);
end

function testStrictSpatialCompositeMissingContext(testCase)
W = sixgr.phy.mimo.TypeI2PortCodebook.matrix(1,0);
tx = localSpatialTx("UE1","TX1",10,W,ones(8,1));
rx = struct("UserId","UE1","Channel",{{eye(2)}});
verifyError(testCase,@()sixgr.mimo.executeSpatialComposite( ...
    tx,rx,struct(),"Strict",true), ...
    "sixgr:mimo:MissingTransmissionContext");
end

function testStrictCSIProductionFacade(testCase)
H = [1 .2;.1 .85];
measurement = sixgr.phy.mimo.CSIMeasurementState( ...
    MeasurementID="facade-meas",UEID="UE1",ResourceType="NZP-CSI-RS", ...
    ResourceID="CSI-RS-7",Slot=20,MaxAgeSlots=3, ...
    ChannelEstimate=H,NoiseVariance=.02);
request = localReportRequest("PUCCH");
cfg = struct();
cfg.phy.mimo.strict = true;
cfg.phy.mimo.N1 = 1; cfg.phy.mimo.N2 = 1;
cfg.phy.mimo.O1 = 1; cfg.phy.mimo.O2 = 1;
cfg.phy.csi.maxRank = 2;
cfg.phy.csi.rankDomain = [1 2];
cfg.phy.csi.reportConfiguration = request;
cfg.phy.csi.reportConfigurationEpoch = 3;
cfg.runtime.currentSlot = 20;
[csi,info] = sixgr.phy.dl.CSI_Feedback(H,.02,cfg, ...
    "MaxRank",2,"MeasurementState",measurement);
verifyFalse(testCase,csi.CustomContainerUsed);
verifyTrue(testCase,csi.SeparateEncoding);
verifyEqual(testCase,csi.MeasurementID,"facade-meas");
verifyEqual(testCase,info.EngineUsed,"sixgr.mimo.buildCSIFeedback");
verifyFalse(testCase,info.ConfiguredSNRUsed);
end

function testStrictPDSCHPrecoderIdentity(testCase)
pdsch = nrPDSCHConfig;
pdsch.NumLayers = 2;
pdsch.DMRS.DMRSPortSet = [0 1];
W = sixgr.phy.mimo.TypeI2PortCodebook.matrix(2,0);
cfg = struct();
cfg.phy.mimo.strict = true;
cfg.phy.pdsch.numPorts = 2;
cfg.phy.pdsch.precoding.matrix = W;
cfg.phy.pdsch.normalizePrecodingMatrix = false;
cfg.phy.pdsch.selectedPrecoderSHA256 = ...
    sixgr.phy.mimo.MatrixContract.digest(W);
prec = sixgr.phy.dl.resolvePDSCHPrecoding(pdsch,cfg);
verifyEqual(testCase,prec.SelectedMatrixSHA256,prec.AppliedMatrixSHA256);
verifyEqual(testCase,prec.Orientation,"Nport_by_Nlayer");
verifyFalse(testCase,prec.MatrixRegenerated);
verifyTrue(testCase,prec.NormativeNormalizationPreserved);
end

function testStrictPUSCHSRSAuthority(testCase)
pusch = nrPUSCHConfig;
pusch.TransmissionScheme = "codebook";
pusch.NumLayers = 1;
pusch.NumAntennaPorts = 2;
pusch.TPMI = 0;
[W,~,~,~] = sixgr.phy.ul.puschCodebookProjectionMatrix(1,2,0,false);
decision = struct( ...
    "Authoritative",true,"MeasurementID","SRS-M1", ...
    "MeasurementSlot",14,"RI",1,"SRI",0,"TPMI",0, ...
    "NumPorts",2,"SelectionMatrixSHA256", ...
    sixgr.phy.mimo.MatrixContract.digest(W));
cfg = struct();
cfg.phy.mimo.strict = true;
cfg.phy.pusch.NumAntennaPorts = 2;
prec = sixgr.phy.ul.resolvePUSCHPrecoding(pusch,cfg, ...
    "SRSDecision",decision);
verifyTrue(testCase,prec.AuthoritativeSRSDecisionUsed);
verifyEqual(testCase,prec.SelectedMatrixSHA256,prec.AppliedMatrixSHA256);
verifyEqual(testCase,prec.SRSMeasurementID,"SRS-M1");
end

function testStrictPMICandidateFacade(testCase)
cfg = struct();
cfg.phy.mimo.strict = true;
cfg.phy.mimo.profileID = "fr1_typeI_single_panel_strict";
cfg.phy.mimo.panels = 1;
cfg.phy.mimo.N1 = 1; cfg.phy.mimo.N2 = 1;
cfg.phy.mimo.O1 = 1; cfg.phy.mimo.O2 = 1;
[candidates,info] = sixgr.phy.dl.pmiCodebookCandidates( ...
    cfg,2,2,"Mode","type1_su_mimo");
verifyEqual(testCase,numel(candidates),2);
verifyFalse(testCase,info.GenericDFTApproximationUsed);
verifyEqual(testCase,candidates(1).MatrixSHA256, ...
    char(sixgr.phy.mimo.MatrixContract.digest(candidates(1).W)));
end

function testCSIRefinementUsesMeasuredResource(testCase)
H = [1 .1;.1 .8];
measurement = sixgr.phy.mimo.CSIMeasurementState( ...
    MeasurementID="P2-M1",UEID="UE1",ResourceType="NZP-CSI-RS", ...
    ResourceID="CSI-RS-SET-2",Slot=30,MaxAgeSlots=2, ...
    ChannelEstimate=H,NoiseVariance=.01);
W = squeeze(sixgr.phy.mimo.TypeI2PortCodebook.enumerate(1));
[w,resource,decision] = sixgr.rf.BeamRefinementCSIRS.selectMeasuredResource( ...
    measurement,W,CurrentSlot=31,ResourceIDs="CSI-RS-"+string(0:3));
verifySize(testCase,w,[2 1]);
verifyTrue(testCase,any(resource=="CSI-RS-"+string(0:3)));
verifyFalse(testCase,decision.GeometryOracleUsed);
verifyEqual(testCase,decision.MeasurementID,"P2-M1");
end

function testSRSReciprocityUsesMeasuredAuthority(testCase)
H = [1 .2 .1 0;.1 .9 0 .2;0 .1 .8 .1;.1 0 .2 .7];
measurement = sixgr.phy.mimo.CSIMeasurementState( ...
    MeasurementID="SRS-M2",UEID="UE1",ResourceType="SRS", ...
    ResourceID="SRS-3",Slot=40,MaxAgeSlots=4, ...
    ChannelEstimate=H,NoiseVariance=.01);
cfg = struct();
cfg.phy.pusch.transmissionScheme = "codebook";
cfg.phy.pusch.NumAntennaPorts = 4;
cfg.phy.pusch.codebookType = "codebook1_ng1n4n1";
out = sixgr.rf.BeamformingSRSReciprocity.fromMeasuredSRS( ...
    measurement,cfg,42);
verifyTrue(testCase,out.MeasurementAuthoritative);
verifyFalse(testCase,out.ConfiguredOverrideUsed);
verifyEqual(testCase,out.SelectionMatrixSHA256,out.AppliedMatrixSHA256);
verifyEqual(testCase,out.MeasurementID,"SRS-M2");
end

function tx = localSpatialTx(userID,sourceID,dmrsID,W,symbols)
tx = struct( ...
    "Symbols",symbols, ...
    "Precoder",W, ...
    "UserId",userID, ...
    "SourceId",sourceID, ...
    "TRPId","", ...
    "Muted",false, ...
    "PowerScale",1, ...
    "PhaseRad",0, ...
    "PRBSet",0:3, ...
    "SymbolSet",2:5, ...
    "DMRSIdentity",dmrsID);
end

function r = localVectors()
persistent cached
if isempty(cached)
    cached = sixgr.phy.mimo.runIndependentVectorValidation(localVectorRoot());
end
r = cached;
end

function root = localVectorRoot()
root = fullfile(fileparts(mfilename("fullpath")),"vectors","mimo");
end

function request = localReportRequest(channel)
request = struct("ReportConfigID","report-3","Epoch",3, ...
    "CodebookType","typeI-SinglePanel","Ports",2,"Rank",2, ...
    "ReportQuantity","cri-RI-PMI-CQI","NumCSIResources",2, ...
    "FrequencyGranularity","wideband","UCIChannel",channel);
end
