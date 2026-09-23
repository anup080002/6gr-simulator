function ok = testNRCSIReportEngineFourPort()
%TESTNRCSIREPORTENGINEFOURPORT Bind the adapter to R2026a TS 38.214 CSI.

setup6GRSimToolkit("Verbose",false);
rng(47219,"twister");
carrier = nrCarrierConfig;
carrier.SubcarrierSpacing = 30;
carrier.NSizeGrid = 24;
carrier.NCellID = 17;
carrier.NSlot = 0;

csirs = nrCSIRSConfig;
csirs.CSIRSType = "nzp";
csirs.RowNumber = 4;
csirs.Density = "one";
csirs.SymbolLocations = 5;
csirs.SubcarrierLocations = 0;
csirs.NumRB = carrier.NSizeGrid;
csirs.RBOffset = 0;
assert(double(csirs.NumCSIRSPorts) == 4, ...
    "CSI-RS row 4 must expose four measured ports.");

dmrs = nrPDSCHDMRSConfig;
K = 12*carrier.NSizeGrid;
L = carrier.SymbolsPerSlot;
nRx = 4;
nPorts = 4;
baseChannel = [1 .12 .03 .01; .08 .83 .07 .02; ...
    .02 .06 .57 .09; .01 .03 .08 .31];
H = complex(zeros(K,L,nRx,nPorts));
for k = 1:K
    for l = 1:L
        phase = exp(1i*(.0017*k+.013*l));
        H(k,l,:,:) = reshape(phase*baseChannel,nRx,nPorts);
    end
end
nVar = .01;
snapshots = repmat(baseChannel,1,1,carrier.NSizeGrid);
measurement = sixgr.phy.mimo.CSIMeasurementState( ...
    MeasurementID="four-port-csirs-runtime",UEID="UE-1", ...
    ResourceType="NZP-CSI-RS",ResourceID="CSI-RS-0", ...
    ResourceOrdinal=0,Slot=0,MaxAgeSlots=4, ...
    ChannelEstimate=snapshots,NoiseVariance=nVar, ...
    Provenance="measured_runtime_csirs_four_port_test");
request = struct( ...
    "ReportConfigID","four-port-type1", "Epoch",0, ...
    "CodebookType","typeI-SinglePanel", "CodebookMode",1, ...
    "Panels",1,"N1",2,"N2",1,"O1",4,"O2",1, ...
    "Ports",4,"Rank",2,"MaxRank",2, ...
    "ReportQuantity","cri-RI-PMI-CQI", ...
    "NumCSIResources",1,"FrequencyGranularity","wideband", ...
    "UCIChannel","PUSCH","NumSubbands",1, ...
    "NumberOfBeams",1,"PhaseAlphabetSize",4);
cfg = struct("Strict",true,"RankDomain",[1 2],"MaxRank",2, ...
    "CQITable","table1","ReportConfiguration",request, ...
    "ReportConfigurationEpoch",0,"CurrentSlot",0);

actual = sixgr.phy.mimo.NRCSIReportEngine.run( ...
    carrier,csirs,dmrs,H,nVar,cfg,measurement);

reference = nrCSIReportConfig;
reference.NStartBWP = carrier.NStartGrid;
reference.NSizeBWP = carrier.NSizeGrid;
reference.CQITable = "table1";
reference.CodebookType = "type1SinglePanel";
reference.PanelDimensions = [1 2 1];
reference.CodebookMode = 1;
reference.CQIFormatIndicator = "wideband";
reference.PMIFormatIndicator = "wideband";
reference.RIRestriction = [1 1 0 0 0 0 0 0];
[expectedRI,~,~] = nr5g.internal.nrRISelect( ...
    carrier,csirs,reference,H,nVar,"MaxSE");
[expectedCQI,expectedPMI,expectedCQIInfo,expectedPMIInfo] = ...
    nr5g.internal.nrCQIReport( ...
    carrier,csirs,reference,dmrs,expectedRI,H,nVar);
expectedW = complex(double(expectedPMIInfo.W));
[~,expectedLayer]=max(mean(expectedPMIInfo.SINRPerREPMI,1));
assert(actual.LI==expectedLayer-1, ...
    'LI must identify the strongest measured layer of the reported precoder.');
if ndims(expectedW) == 3
    expectedW = expectedW(:,:,1);
end

assert(actual.RI == double(expectedRI), ...
    "Adapter RI must equal the release-pinned TS 38.214 engine.");
assert(actual.CQI == double(expectedCQI(1)), ...
    "Adapter CQI must equal the release-pinned TS 38.214 engine.");
assert(abs(actual.WidebandSINR_dB-double(expectedCQIInfo.EffectiveSINR(1)))<1e-12, ...
    'CSI effective SINR must retain the receiver engine''s dB units.');
assert(isequal(actual.PMISet,expectedPMI), ...
    "Adapter PMI indices must equal the release-pinned TS 38.214 engine.");
assert(norm(actual.Precoder_W-expectedW,"fro") < 1e-12, ...
    "Adapter precoder must equal the release-pinned Type-I codebook matrix.");
request.Rank=actual.RI;
schedulerW=sixgr.phy.mimo.TypeISinglePanelCodebook.matrix(request,actual.PMI);
assert(isequal(actual.Precoder_W,schedulerW) && ...
    actual.PrecoderMatrixSHA256==sixgr.phy.mimo.MatrixContract.digest(schedulerW), ...
    'Selected and applied precoder must share exact numeric and digest authority.');
assert(isequal(size(actual.Precoder_W),[4 actual.RI]), ...
    "Runtime CSI precoder must retain all four measured ports.");
assert(~isempty(actual.CSIPart1Bits) && ~isempty(actual.CSIPart2Bits), ...
    "Strict four-port PUSCH CSI must produce typed CSI Part 1 and Part 2 bits.");
% PUCCH wideband Type-I is a distinct installed reporting configuration.
% Moving an existing report to another transport does not reconfigure its
% payload. Build the PUCCH report from the same measured RI/PMI/CQI values.
pucchRequest=request;
pucchRequest.ReportConfigID="four-port-type1-pucch";
pucchRequest.UCIChannel="PUCCH";
pucchRequest.ConfiguredUCIChannel="PUCCH";
pucchSchema=sixgr.phy.mimo.CSIReportConfiguration(pucchRequest,0);
measuredValues=actual.CSIReportConfiguration.decode( ...
    actual.CSIPart1Bits,actual.CSIPart2Bits);
pucch=pucchSchema.build(measuredValues);
assert(~isempty(pucch.Part1Bits) && isempty(pucch.Part2Bits));
received=pucchSchema.encodeDecodeNoNoise(pucch);
decoded=pucchSchema.decode(received.Part1.Bits,received.Part2.Bits);
assert(received.CRCPassed && decoded.RI==actual.RI && ...
    decoded.PMI==actual.PMI && decoded.CQI_CW0==actual.CQI && decoded.CRI==actual.CRI);
% The independently installed gNB schema, not the TX's selected rank, must
% decode the same PUCCH-configured payload when carried on shared PUSCH.
[relocated,~]=pucchSchema.transcode(pucch.Part1Bits,pucch.Part2Bits,"PUSCH");
receiverRequest=pucchRequest; receiverRequest.UCIChannel="PUSCH"; receiverRequest.Rank=1;
receiverSchema=sixgr.phy.mimo.CSIReportConfiguration(receiverRequest,0);
assert(isequal(relocated.Part1Bits,pucch.Part1Bits) && isempty(relocated.Part2Bits));
recovered=receiverSchema.decode(relocated.Part1Bits,relocated.Part2Bits);
assert(recovered.RI==actual.RI && recovered.PMI==actual.PMI && ...
    recovered.CQI_CW0==actual.CQI && recovered.CRI==actual.CRI);
assert(~actual.ConfiguredSNRUsed && ~actual.SVDThresholdUsed && ...
    contains(actual.RuntimeEvidenceSource,"measured_csirs"), ...
    "Strict CSI evidence must be measured and must not use configured-SNR/SVD shortcuts.");
ok = true;
end
