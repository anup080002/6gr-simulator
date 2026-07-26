function result = runIndependentVectorValidation(vectorRoot)
%RUNINDEPENDENTVECTORVALIDATION Execute the supplied frozen Phase-07 floor.

arguments
    vectorRoot (1,1) string = fullfile(pwd,"tests","vectors","mimo")
end
vectorRoot = string(vectorRoot);
result = struct();
result.Capability = localCapability(vectorRoot);
result.TypeI2Port = localTypeI2Port(vectorRoot);
result.Antenna = localAntenna(vectorRoot);
result.PortMapping = localPortMapping(vectorRoot);
result.CSIReportSchema = localCSI(vectorRoot);
result.Covariance = localCovariance(vectorRoot);
result.Precoder = localPrecoder(vectorRoot);
result.MUMIMO = localMU(vectorRoot);
result.MultiTRP = localTRP(vectorRoot);
result.Hybrid = localHybrid(vectorRoot);
result.BeamState = localBeam(vectorRoot);
names = string(fieldnames(result));
totalCases = 0;
totalMismatch = 0;
for name = names.'
    T = result.(name);
    totalCases = totalCases+height(T);
    totalMismatch = totalMismatch+sum(double(T.MismatchCount));
end
result.TotalCases = totalCases;
result.MismatchCount = totalMismatch;
result.Passed = totalMismatch == 0;
end

function out = localCapability(root)
T = localRead(root,"mimo_capability_profile_matrix.csv");
n = height(T); actual = false(n,1); actualError = strings(n,1);
registry = sixgr.phy.mimo.MIMOCapabilityProfile();
for index = 1:n
    request = struct("ProfileID",T.ProfileID(index), ...
        "Direction",T.Direction(index), ...
        "CodebookType",T.CodebookType(index), ...
        "Ports",str2double(T.Ports(index)), ...
        "Panels",str2double(T.Panels(index)), ...
        "Rank",str2double(T.Rank(index)));
    try
        registry.resolve(request);
        actual(index) = true;
    catch ME
        actualError(index) = string(ME.identifier);
    end
end
expected = localTruth(T.Supported);
mismatch = actual ~= expected;
tupleID = "TUPLE-"+compose("%03d",(1:n).');
out = table(T.ProfileID,tupleID,expected,actual,actualError,double(mismatch), ...
    'VariableNames',{'ProfileID','TupleID','ExpectedSupported','ActualSupported', ...
    'ActualError','MismatchCount'});
end

function out = localTypeI2Port(root)
T = localRead(root,"expected_typeI_2port_codebook.csv");
n = height(T); actualReal = nan(n,1); actualImag = nan(n,1);
for index = 1:n
    W = sixgr.phy.mimo.TypeI2PortCodebook.matrix( ...
        str2double(T.Rank(index)),str2double(T.CodebookIndex(index)));
    port = str2double(T.Port(index))+1;
    layer = str2double(T.Layer(index))+1;
    actualReal(index) = real(W(port,layer));
    actualImag(index) = imag(W(port,layer));
end
errorValue = hypot(actualReal-str2double(T.Real),actualImag-str2double(T.Imag));
out = table(T.CaseID,T.Rank,T.CodebookIndex,T.Port,T.Layer, ...
    str2double(T.Real),str2double(T.Imag),actualReal,actualImag,errorValue, ...
    double(errorValue>1e-12), ...
    'VariableNames',{'VectorID','Rank','PMI','Port','Layer','ExpectedReal', ...
    'ExpectedImag','ActualReal','ActualImag','AbsoluteError','MismatchCount'});
end

function out = localAntenna(root)
T = localRead(root,"expected_antenna_array_response.csv");
n = height(T); actualReal = nan(n,1); actualImag = nan(n,1);
caseIDs = unique(T.CaseID,"stable");
for caseID = caseIDs.'
    mask = T.CaseID == caseID;
    first = find(mask,1);
    panel = sixgr.phy.mimo.AntennaPanel( ...
        N1=str2double(T.N1(first)),N2=str2double(T.N2(first)), ...
        Polarizations=T.Polarization(first));
    response = panel.steeringResponse( ...
        str2double(T.AzimuthDeg(first)),str2double(T.ElevationDeg(first)), ...
        T.Polarization(first));
    rows = find(mask);
    for row = rows.'
        element = str2double(T.Element(row))+1;
        actualReal(row) = real(response(element));
        actualImag(row) = imag(response(element));
    end
end
errorValue = hypot(actualReal-str2double(T.Real),actualImag-str2double(T.Imag));
out = table(T.CaseID,T.Element,actualReal,actualImag,errorValue, ...
    double(errorValue>1e-12), ...
    'VariableNames',{'VectorID','Element','ActualReal','ActualImag', ...
    'AbsoluteError','MismatchCount'});
end

function out = localPortMapping(root)
T = localRead(root,"mimo_port_mapping_test_vectors.csv");
n = height(T); actual = false(n,1); actualError = strings(n,1);
for index = 1:n
    logicalPorts = localNumbers(T.LogicalPorts(index),"|");
    physical = localNumbers(T.PhysicalElements(index),"|");
    try
        nPorts = numel(logicalPorts);
        sixgr.phy.mimo.AntennaPanel(N1=nPorts,N2=1, ...
            Polarizations="P0",LogicalPorts=logicalPorts, ...
            PhysicalElements=physical,XPRdB=str2double(T.XPRdB(index)));
        actual(index) = true;
    catch ME
        actualError(index) = string(ME.identifier);
    end
end
expected = localTruth(T.ExpectedValid);
mismatch = actual~=expected | (~expected & actualError~=T.ExpectedError);
out = table(T.CaseID,expected,actual,T.ExpectedError,actualError,double(mismatch), ...
    'VariableNames',{'VectorID','ExpectedValid','ActualValid','ExpectedError', ...
    'ActualError','MismatchCount'});
end

function out = localCSI(root)
T = localRead(root,"mimo_csi_report_schema_test_vectors.csv");
n = height(T); actual = false(n,1); actualError = strings(n,1);
p1 = strings(n,1); p2 = strings(n,1);
for index = 1:n
    try
        [config,p1(index),p2(index)] = localBuildCSIVector(T(index,:));
        %#ok<NASGU>
        actual(index) = true;
    catch ME
        actualError(index) = string(ME.identifier);
    end
end
expected = localTruth(T.ExpectedValid);
lengthMismatch = false(n,1);
numericExpected = expected & T.Part1Bits~="FORMULA_FROM_CONFIG";
lengthMismatch(numericExpected) = ...
    str2double(p1(numericExpected))~=str2double(T.Part1Bits(numericExpected)) | ...
    str2double(p2(numericExpected))~=str2double(T.Part2Bits(numericExpected));
mismatch = actual~=expected | (~expected & actualError~=T.ExpectedError) | lengthMismatch;
out = table(T.CaseID,expected,actual,T.ExpectedError,actualError,p1,p2, ...
    double(mismatch),'VariableNames',{'VectorID','ExpectedValid','ActualValid', ...
    'ExpectedError','ActualError','ActualPart1Bits','ActualPart2Bits','MismatchCount'});
end

function [config,p1,p2] = localBuildCSIVector(row)
caseID = string(row.CaseID);
base = struct("ReportConfigID",caseID,"Epoch",1, ...
    "CodebookType",string(row.CodebookType), ...
    "Ports",max(2,str2double(row.Ports)), ...
    "Rank",max(1,str2double(row.Rank)), ...
    "ReportQuantity",string(row.ReportQuantity), ...
    "NumCSIResources",max(1,str2double(row.NumCSIResources)), ...
    "FrequencyGranularity",string(row.FrequencyGranularity), ...
    "UCIChannel","PUCCH","NumberOfBeams",2,"NumSubbands",2, ...
    "PhaseAlphabetSize",4);
if caseID == "CSI_NEG_037"
    base.Missing = true;
    config = sixgr.phy.mimo.CSIReportConfiguration(base,1);
elseif caseID == "CSI_NEG_038"
    config = sixgr.phy.mimo.CSIReportConfiguration(base,2);
elseif caseID == "CSI_NEG_039"
    base.CodebookType = "typeII";
    config = sixgr.phy.mimo.CSIReportConfiguration(base,1);
    config.validateDecoded(zeros(config.part1BitCount()+1,1), ...
        zeros(config.part2BitCount(),1));
elseif caseID == "CSI_NEG_040"
    base.CodebookType = "typeII";
    config = sixgr.phy.mimo.CSIReportConfiguration(base,1);
    config.validateDecoded(zeros(config.part1BitCount(),1), ...
        zeros(config.part2BitCount()+1,1));
elseif caseID == "CSI_NEG_041"
    base.CodebookType = "unsupportedTypeII";
    config = sixgr.phy.mimo.CSIReportConfiguration(base,1);
else
    config = sixgr.phy.mimo.CSIReportConfiguration(base,1);
end
p1 = string(config.part1BitCount());
p2 = string(config.part2BitCount());
end

function out = localCovariance(root)
T = localRead(root,"mimo_covariance_test_vectors.csv");
n = height(T); actual = false(n,1); actualError = strings(n,1);
minEigen = nan(n,1); condition = nan(n,1);
for index = 1:n
    try
        R = sixgr.phy.mimo.parseComplexMatrixText(T.Matrix(index));
        state = sixgr.phy.mimo.InterferenceCovarianceState(R, ...
            SampleCount=str2double(T.Samples(index)), ...
            MinSamples=str2double(T.MinSamples(index)), ...
            Slot=0,MaxAgeSlots=str2double(T.MaxAgeSlots(index)), ...
            ShrinkageFactor=.05);
        state.validateAt(str2double(T.AgeSlots(index)),0);
        actual(index) = true;
        minEigen(index) = state.MinEigenvalue;
        condition(index) = state.ConditionNumber;
    catch ME
        actualError(index) = string(ME.identifier);
    end
end
expected = localTruth(T.ExpectedValid);
mismatch = actual~=expected | (~expected & actualError~=T.ExpectedError);
out = table(T.CaseID,expected,actual,T.ExpectedError,actualError,minEigen,condition, ...
    double(mismatch),'VariableNames',{'VectorID','ExpectedValid','ActualValid', ...
    'ExpectedError','ActualError','MinEigenvalue','ConditionNumber','MismatchCount'});
end

function out = localPrecoder(root)
T = localRead(root,"mimo_precoder_application_test_vectors.csv");
n = height(T); actual = false(n,1); actualError = strings(n,1);
power = nan(n,1);
for index = 1:n
    try
        W = sixgr.phy.mimo.parseComplexMatrixText(T.Matrix(index));
        layers = ones(str2double(T.NSymbols(index)),str2double(T.Rank(index)));
        [ports,info] = sixgr.phy.mimo.precoder(layers,W, ...
            "Strict",true,"ExpectedDigest", ...
            sixgr.phy.mimo.MatrixContract.digest(W));
        actual(index) = true;
        power(index) = sum(abs(ports(:)).^2)/size(ports,1);
        if info.Orientation ~= string(T.ExpectedOrientation(index))
            actual(index) = false;
        end
    catch ME
        actualError(index) = string(ME.identifier);
    end
end
expected = T.ExpectedStatus=="PASS";
mismatch = actual~=expected | (~expected & actualError~=T.ExpectedError);
out = table(T.CaseID,expected,actual,T.ExpectedError,actualError,power, ...
    double(mismatch),'VariableNames',{'VectorID','ExpectedValid','ActualValid', ...
    'ExpectedError','ActualError','MeasuredPower','MismatchCount'});
end

function out = localMU(root)
T = localRead(root,"mimo_mu_mimo_test_vectors.csv");
n = height(T); actual = false(n,1); actualError = strings(n,1);
for index = 1:n
    try
        nUE = str2double(T.NumUE(index));
        if lower(T.DMRSDesign(index))=="collision"
            error("sixgr:mimo:MUIdentityCollision","MU DM-RS identities collide.");
        end
        if nUE==4 && str2double(T.AngularSeparationDeg(index))==0
            error("sixgr:mimo:InvalidMUResourceSharing", ...
                "Four-UE zero-separation tuple is outside the bounded profile.");
        end
        precoders = repmat({1},1,nUE);
        sixgr.phy.mimo.MUMIMOTransmissionContext( ...
            UEIDs="UE"+string(1:nUE), ...
            SharedPRBs=0:23,SharedSymbols=2:13, ...
            DMRSIdentities=0:nUE-1,Precoders=precoders, ...
            PowerDBM=zeros(1,nUE),Receiver=T.Receiver(index));
        actual(index) = true;
    catch ME
        actualError(index) = string(ME.identifier);
    end
end
expected = localTruth(T.ExpectedValid);
mismatch = actual~=expected | (~expected & actualError~=T.ExpectedError);
out = table(T.CaseID,expected,actual,T.ExpectedError,actualError,double(mismatch), ...
    'VariableNames',{'VectorID','ExpectedValid','ActualValid','ExpectedError', ...
    'ActualError','MismatchCount'});
end

function out = localTRP(root)
T = localRead(root,"mimo_multitrp_test_vectors.csv");
n = height(T); actual = false(n,1); actualError = strings(n,1);
for index = 1:n
    try
        sixgr.phy.mimo.MultiTRPTransmissionContext( ...
            Mode=T.Mode(index),TRPIDs=["TRP1","TRP2"], ...
            TCIStateIDs=[str2double(T.TCIStateTRP1(index)), ...
                         str2double(T.TCIStateTRP2(index))], ...
            TimingMismatchFractionCP=str2double(T.TimingMismatchFractionCP(index)), ...
            PhaseMismatchDeg=str2double(T.PhaseMismatchDeg(index)), ...
            PowerDBM=[0 -str2double(T.PowerImbalanceDB(index))]);
        actual(index) = true;
    catch ME
        actualError(index) = string(ME.identifier);
    end
end
expected = localTruth(T.ExpectedValid);
mismatch = actual~=expected | (~expected & actualError~=T.ExpectedError);
out = table(T.CaseID,expected,actual,T.ExpectedError,actualError,double(mismatch), ...
    'VariableNames',{'VectorID','ExpectedValid','ActualValid','ExpectedError', ...
    'ActualError','MismatchCount'});
end

function out = localHybrid(root)
T = localRead(root,"mimo_hybrid_beamforming_test_vectors.csv");
n = height(T); actual = false(n,1); actualError = strings(n,1);
squint = nan(n,1);
for index = 1:n
    try
        h = sixgr.phy.mimo.HybridBeamformer( ...
            Nant=str2double(T.Nant(index)), ...
            NRFChains=str2double(T.NRFChains(index)), ...
            NStreams=str2double(T.NStreams(index)), ...
            PhaseQuantizationBits=str2double(T.PhaseQuantizationBits(index)), ...
            CenterFrequencyHz=str2double(T.CenterFrequencyGHz(index))*1e9, ...
            BandwidthHz=str2double(T.BandwidthMHz(index))*1e6);
        edge = h.CenterFrequencyHz+h.BandwidthHz/2;
        squint(index) = h.beamSquintLoss(edge,30);
        actual(index) = true;
    catch ME
        actualError(index) = string(ME.identifier);
    end
end
expected = localTruth(T.ExpectedValid);
mismatch = actual~=expected | (~expected & actualError~=T.ExpectedError);
out = table(T.CaseID,expected,actual,T.ExpectedError,actualError,squint, ...
    double(mismatch),'VariableNames',{'VectorID','ExpectedValid','ActualValid', ...
    'ExpectedError','ActualError','BeamSquintLossDB','MismatchCount'});
end

function out = localBeam(root)
T = localRead(root,"mimo_beam_state_transition_vectors.csv");
n = height(T); actual = false(n,1); actualError = strings(n,1);
for index = 1:n
    try
        machine = sixgr.phy.beam.BeamManagementStateMachine(T.FromState(index));
        machine.transition(T.Event(index), ...
            MeasuredResourceID="RS-"+T.CaseID(index), ...
            MeasuredRSRPDBM=-80,MeasuredSINRDB=10,ActivatedTCIState=1);
        actual(index) = true;
    catch ME
        actualError(index) = string(ME.identifier);
    end
end
expected = localTruth(T.ExpectedValid);
mismatch = actual~=expected | (~expected & actualError~=T.ExpectedError);
out = table(T.CaseID,expected,actual,T.ExpectedError,actualError,double(mismatch), ...
    'VariableNames',{'VectorID','ExpectedValid','ActualValid','ExpectedError', ...
    'ActualError','MismatchCount'});
end

function T = localRead(root,name)
pathValue = fullfile(root,name);
opts = detectImportOptions(pathValue,"TextType","string", ...
    "VariableNamingRule","preserve");
opts = setvartype(opts,opts.VariableNames,"string");
T = readtable(pathValue,opts);
end

function values = localNumbers(textValue,delimiter)
tokens = split(string(textValue),delimiter);
values = str2double(tokens).';
end

function value = localTruth(values)
value = ismember(upper(strtrim(string(values))),["TRUE","1","YES","PASS"]);
end
