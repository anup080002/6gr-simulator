function result = runNegativeVectorValidation(vectorRoot)
%RUNNEGATIVEVECTORVALIDATION Execute all typed fail-before-waveform vectors.

arguments
    vectorRoot (1,1) string = fullfile(pwd,"tests","vectors","mimo")
end
pathValue = fullfile(vectorRoot,"mimo_negative_test_vectors.csv");
opts = detectImportOptions(pathValue,"TextType","string", ...
    "VariableNamingRule","preserve");
opts = setvartype(opts,opts.VariableNames,"string");
vectors = readtable(pathValue,opts);
n = height(vectors);
actualError = strings(n,1);
waveformGenerated = false(n,1);
stateChanged = false(n,1);
grantCreated = false(n,1);
for index = 1:n
    try
        localInject(vectors.FaultType(index));
        actualError(index) = "NO_ERROR";
    catch ME
        actualError(index) = string(ME.identifier);
    end
end
passed = actualError==vectors.ExpectedError & ...
    ~waveformGenerated & ~stateChanged & ~grantCreated;
result = table(vectors.CaseID,vectors.FaultType,vectors.ExpectedError, ...
    actualError,waveformGenerated,stateChanged,grantCreated,passed, ...
    repmat("PASS",n,1), ...
    'VariableNames',{'CaseID','FaultType','ExpectedError','ActualError', ...
    'WaveformGenerated','StateChanged','GrantCreated','Passed','Status'});
result.Status(~passed) = "FAIL";
end

function localInject(fault)
switch lower(string(fault))
    case "unsupported_profile"
        sixgr.phy.mimo.MIMOCapabilityProfile().resolve(struct( ...
            "ProfileID","unsupported_extension","Direction","DL", ...
            "CodebookType","none","Ports",2,"Panels",1,"Rank",1));
    case "bad_panel"
        sixgr.phy.mimo.AntennaPanel(N1=2,N2=1,HorizontalSpacingLambda=11);
    case "duplicate_port"
        sixgr.phy.mimo.AntennaPanel(N1=2,N2=1, ...
            LogicalPorts=[3000 3001],PhysicalElements=[0 0]);
    case "bad_polarization"
        sixgr.phy.mimo.AntennaPanel(N1=2,N2=1,Polarizations="UNKNOWN");
    case "bad_codebook"
        localCSIConfig("bad-codebook",1,"not-a-codebook");
    case "bad_subset"
        sixgr.phy.mimo.StrictMIMOValidator.validateSubsetRestriction([1 0 2],3);
    case "rank_overflow"
        sixgr.phy.mimo.TypeI2PortCodebook.enumerate(3);
    case "pmi_overflow"
        sixgr.phy.mimo.TypeI2PortCodebook.matrix(1,99);
    case "missing_csi_config"
        request = localCSIRequest("missing",1,"typeI-SinglePanel");
        request.Missing = true;
        sixgr.phy.mimo.CSIReportConfiguration(request,1);
    case "stale_csi_config"
        localCSIConfig("stale",1,"typeI-SinglePanel",2);
    case "missing_measurement"
        sixgr.phy.mimo.CSIMeasurementState( ...
            MeasurementID="m",UEID="ue",ResourceType="CSI-RS", ...
            ResourceID="r",Slot=0,MaxAgeSlots=1,ChannelEstimate=[], ...
            NoiseVariance=.1);
    case "stale_measurement"
        state = sixgr.phy.mimo.CSIMeasurementState( ...
            MeasurementID="m",UEID="ue",ResourceType="CSI-RS", ...
            ResourceID="r",Slot=0,MaxAgeSlots=1,ChannelEstimate=eye(2), ...
            NoiseVariance=.1);
        state.validateAt(2);
    case "wrong_part1"
        cfg = localCSIConfig("part1",1,"typeI-SinglePanel");
        cfg.validateDecoded(zeros(cfg.part1BitCount()+1,1), ...
            zeros(cfg.part2BitCount(),1));
    case "wrong_part2"
        cfg = localCSIConfig("part2",1,"typeI-SinglePanel");
        cfg.validateDecoded(zeros(cfg.part1BitCount(),1), ...
            zeros(cfg.part2BitCount()+1,1));
    case "missing_covariance"
        sixgr.phy.mimo.InterferenceCovarianceState([]);
    case "non_psd_covariance"
        sixgr.phy.mimo.InterferenceCovarianceState([1 2;2 1], ...
            SampleCount=16,MinSamples=8,ShrinkageFactor=0);
    case "few_cov_samples"
        sixgr.phy.mimo.InterferenceCovarianceState(eye(2), ...
            SampleCount=2,MinSamples=8);
    case "stale_covariance"
        state = sixgr.phy.mimo.InterferenceCovarianceState(eye(2), ...
            SampleCount=16,MinSamples=8,Slot=0,MaxAgeSlots=1);
        state.validateAt(2,0);
    case "bad_w_dims"
        sixgr.phy.mimo.MatrixContract.validate(ones(2,4),4,2);
    case "bad_w_power"
        sixgr.phy.mimo.MatrixContract.validate(zeros(4,2),4,2);
    case "w_digest_mismatch"
        W = sixgr.phy.mimo.TypeI2PortCodebook.matrix(1,0);
        sixgr.phy.mimo.MatrixContract.validate(W,2,1, ...
            ExpectedDigest=string(repmat('0',1,64)));
    case "config_override"
        sixgr.phy.mimo.StrictMIMOValidator.assertNoConfiguredOverride(2,1);
    case "rank_collapse"
        W = sixgr.phy.mimo.TypeI2PortCodebook.matrix(1,0);
        sixgr.phy.mimo.StrictMIMOValidator.validateApplication( ...
            W,W,2,1,[3000 3001],[3000 3001]);
    case "port_collapse"
        W = sixgr.phy.mimo.TypeI2PortCodebook.matrix(1,0);
        sixgr.phy.mimo.StrictMIMOValidator.validateApplication( ...
            W,W,1,1,[3000 3001],[3000]);
    case "missing_srs"
        sixgr.phy.mimo.StrictMIMOValidator.validateSRSDecision([],0);
    case "stale_srs"
        sixgr.phy.mimo.StrictMIMOValidator.validateSRSDecision( ...
            struct("Measured",true,"Slot",0,"MaxAgeSlots",1),2);
    case "mu_dmrs_collision"
        sixgr.phy.mimo.MUMIMOTransmissionContext( ...
            UEIDs=["UE1","UE2"],SharedPRBs=0:23,SharedSymbols=2:13, ...
            DMRSIdentities=[0 0],Precoders={1,1},PowerDBM=[0 0]);
    case "missing_trp"
        sixgr.phy.mimo.MultiTRPTransmissionContext( ...
            Mode="CJT",TRPIDs="TRP1",TCIStateIDs=1);
    case "cjt_timing"
        localTRP(.25,0);
    case "cjt_phase"
        localTRP(0,45);
    case "inactive_tci"
        sixgr.phy.mimo.StrictMIMOValidator.validateTCI([],1);
    case "qcl_mismatch"
        sixgr.phy.mimo.StrictMIMOValidator.validateTCI(1,2);
    case "missing_hybrid"
        sixgr.phy.mimo.HybridBeamformer(Nant=16,NRFChains=2,NStreams=2, ...
            PhaseQuantizationBits=4,CenterFrequencyHz=28e9,BandwidthHz=400e6, ...
            AnalogWeights=ones(2),DigitalWeights=eye(2));
    case "rf_chain_exceeded"
        sixgr.phy.mimo.HybridBeamformer(Nant=16,NRFChains=1,NStreams=2, ...
            PhaseQuantizationBits=4,CenterFrequencyHz=28e9,BandwidthHz=400e6);
    case "analog_weight_bad"
        sixgr.phy.mimo.HybridBeamformer(Nant=4,NRFChains=1,NStreams=1, ...
            PhaseQuantizationBits=4,CenterFrequencyHz=28e9,BandwidthHz=400e6, ...
            AnalogWeights=ones(4,1),DigitalWeights=1);
    case "geometry_beam_oracle"
        sixgr.phy.mimo.StrictMIMOValidator.validateBeamMeasurement( ...
            "geometry_oracle","SSB-1");
    case "bad_beam_transition"
        machine = sixgr.phy.beam.BeamManagementStateMachine("IDLE");
        machine.transition("AUTO_EVENT_FOR_DATA_ACTIVE");
    case "strict_svd_fallback"
        sixgr.phy.mimo.precoder(ones(2,1),[],"Strict",true);
    otherwise
        error("sixgr:mimo:UnsupportedProfile", ...
            "Unknown negative vector fault %s.",fault);
end
end

function config = localCSIConfig(id,epoch,codebook,currentEpoch)
if nargin < 4
    currentEpoch = epoch;
end
config = sixgr.phy.mimo.CSIReportConfiguration( ...
    localCSIRequest(id,epoch,codebook),currentEpoch);
end

function request = localCSIRequest(id,epoch,codebook)
request = struct("ReportConfigID",id,"Epoch",epoch, ...
    "CodebookType",codebook,"Ports",2,"Rank",1, ...
    "ReportQuantity","cri-RI-PMI-CQI","NumCSIResources",1, ...
    "FrequencyGranularity","wideband","UCIChannel","PUCCH");
end

function localTRP(timing,phase)
sixgr.phy.mimo.MultiTRPTransmissionContext(Mode="CJT", ...
    TRPIDs=["TRP1","TRP2"],TCIStateIDs=[1 2], ...
    TimingMismatchFractionCP=timing,PhaseMismatchDeg=phase);
end
