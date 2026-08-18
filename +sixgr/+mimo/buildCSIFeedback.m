function csi = buildCSIFeedback(H, noiseVar, cfg, varargin)
%BUILDCSIFEEDBACK Build measured, report-configured CSI Part 1 and Part 2.

ip = inputParser;
ip.addParameter("Direction","DL",@(x)ischar(x)||isstring(x));
ip.addParameter("NominalRank",[],@(x)isempty(x)||(isnumeric(x)&&isscalar(x)));
ip.addParameter("MeasurementState",[],@(x)isempty(x)||isa(x, ...
    "sixgr.phy.mimo.CSIMeasurementState"));
ip.parse(varargin{:});
if nargin < 3 || ~isstruct(cfg)
    cfg = struct();
end
strict = logical(sixgr.util.structGet(cfg,"Strict", ...
    sixgr.util.structGet(cfg,"mimo.strict",false)));
if isempty(H) || ~isnumeric(H)
    error("sixgr:mimo:MissingMeasurementState", ...
        "CSI feedback requires a measured channel.");
end
if ~(isscalar(noiseVar)&&isnumeric(noiseVar)&&isfinite(noiseVar)&&noiseVar>=0)
    error("sixgr:mimo:MissingMeasurementState", ...
        "CSI feedback requires measured finite noise variance.");
end
measurement = ip.Results.MeasurementState;
if strict && isempty(measurement)
    error("sixgr:mimo:MissingMeasurementState", ...
        "Strict CSI feedback requires an immutable measured reference-signal state.");
end
if ~isempty(measurement)
    currentSlot = double(sixgr.util.structGet(cfg,"CurrentSlot",measurement.Slot));
    measurement.validateAt(currentSlot);
    if sixgr.phy.mimo.MatrixContract.digest(H) ~= measurement.Digest
        error("sixgr:mimo:MeasurementIdentityMismatch", ...
            "CSI input channel differs from the immutable measured state.");
    end
    if ~(isscalar(measurement.NoiseVariance) && ...
            isfinite(double(measurement.NoiseVariance)) && ...
            double(measurement.NoiseVariance) >= 0)
        error("sixgr:mimo:MissingMeasurementState", ...
            "Measured CSI state contains invalid noise variance.");
    end
    if abs(double(noiseVar)-double(measurement.NoiseVariance)) > ...
            1e-12*max(1,abs(double(noiseVar)))
        error("sixgr:mimo:MeasurementIdentityMismatch", ...
            "CSI input noise variance differs from the immutable measured state.");
    end
    if ~isempty(measurement.InterferenceCovariance)
        cfg.InterferenceCovariance = measurement.InterferenceCovariance;
    end
end

nTx = size(H,2);
nRx = size(H,1);
if nTx > 2
    error("sixgr:mimo:HighPortCSIRequiresNRGrid", ...
        "CSI reporting for more than two ports requires the release-pinned " + ...
        "NR CSI engine with carrier, CSI-RS, DM-RS and per-resource channel " + ...
        "estimates; a wideband matrix cannot establish a standards-valid PMI.");
end
maxRank = ip.Results.NominalRank;
if isempty(maxRank)
    maxRank = double(sixgr.util.structGet(cfg,"MaxRank", ...
        sixgr.util.structGet(cfg,"mimo.maxRank",min(nTx,nRx))));
end
maxRank = min([double(maxRank),nTx,nRx]);
if maxRank < 1 || maxRank ~= round(maxRank)
    error("sixgr:mimo:UnsupportedRank","CSI max rank must be a positive integer.");
end
rankDomain = double(sixgr.util.structGet(cfg,"RankDomain",1:maxRank));
rankDomain = rankDomain(:).';
if any(rankDomain<1 | rankDomain>maxRank | rankDomain~=round(rankDomain))
    error("sixgr:mimo:InvalidRI","RankDomain contains an invalid RI.");
end

rankScores = -inf(size(rankDomain));
rankW = cell(size(rankDomain));
rankPMI = nan(size(rankDomain));
rankInfo = cell(size(rankDomain));
for index = 1:numel(rankDomain)
    rankValue = rankDomain(index);
    rankCfg = cfg;
    rankCfg.NoiseVariance = noiseVar;
    if isfield(cfg,"CandidateMatricesByRank")
        rankCfg.CandidateMatrices = cfg.CandidateMatricesByRank{rankValue};
    end
    [W,pmi,~,selection] = sixgr.mimo.selectPMI( ...
        H,rankValue,nTx,nRx,rankCfg);
    rankScores(index) = selection.SelectedMetric;
    rankW{index} = W;
    rankPMI(index) = double(pmi(1));
    rankInfo{index} = selection;
end
feedbackOverheadWeight = double(sixgr.util.structGet(cfg, ...
    "FeedbackOverheadWeight",0));
rankScores = rankScores - feedbackOverheadWeight.*rankDomain;
[selectedScore,selectedIndex] = max(rankScores);
selectedRank = rankDomain(selectedIndex);
W = rankW{selectedIndex};
pmi = rankPMI(selectedIndex);
selection = rankInfo{selectedIndex};
sinrDB = 10*log10(max(2^(selectedScore/selectedRank)-1,realmin));
cqi = localCQI(sinrDB,cfg,strict);
[singularValues,singularValueSource] = localSpatialSingularValues(H);
if numel(singularValues) >= selectedRank && singularValues(selectedRank) > 0
    conditionNumberDB = 20*log10(singularValues(1)/singularValues(selectedRank));
else
    conditionNumberDB = Inf;
end

reportRequest = sixgr.util.structGet(cfg,"ReportConfiguration", ...
    sixgr.util.structGet(cfg,"phy.csi.reportConfiguration",[]));
if isempty(reportRequest)
    if strict
        error("sixgr:mimo:MissingCSIReportConfig", ...
            "Strict CSI feedback requires decoded report configuration.");
    end
    reportRequest = struct( ...
        "ReportConfigID","compat-wideband-0", ...
        "Epoch",0, ...
        "CodebookType","typeI-SinglePanel", ...
        "Ports",nTx, ...
        "Rank",selectedRank, ...
        "ReportQuantity","cri-RI-PMI-CQI", ...
        "NumCSIResources",1, ...
        "FrequencyGranularity","wideband", ...
        "UCIChannel","PUCCH");
end
reportRequest.Rank = selectedRank;
currentEpoch = double(sixgr.util.structGet(cfg,"ReportConfigurationEpoch", ...
    sixgr.util.structGet(reportRequest,"Epoch",0)));
reportConfig = sixgr.phy.mimo.CSIReportConfiguration(reportRequest,currentEpoch);
cri = localMeasuredCRI(measurement, reportConfig.NumCSIResources, strict);
values = struct("CRI",cri,"RI",selectedRank,"CQI_CW0",cqi, ...
    "PMI",pmi,"LI",max(0,selectedRank-1));
report = reportConfig.build(values);

csi = struct( ...
    "Direction",upper(string(ip.Results.Direction)), ...
    "RI",selectedRank, ...
    "PMI",pmi, ...
    "PMI_i1",pmi, ...
    "PMI_i2",NaN, ...
    "CQI",cqi, ...
    "LI",max(0,selectedRank-1), ...
    "CRI",cri, ...
    "WidebandSINR_dB",sinrDB, ...
    "Precoder_W",W, ...
    "PrecoderMatrixSHA256",sixgr.phy.mimo.MatrixContract.digest(W), ...
    "ConditionNumber_dB",conditionNumberDB, ...
    "SingularValues",singularValues, ...
    "RankCandidateObjective",rankScores, ...
    "RankDomain",rankDomain, ...
    "RankDecisionReason","maximum_receiver_aware_goodput_objective", ...
    "RuntimeEvidenceSource","measured_channel_noise_and_covariance", ...
    "MeasurementID",localMeasurementField(measurement,"MeasurementID",""), ...
    "MeasurementResourceID",localMeasurementField(measurement,"ResourceID",""), ...
    "MeasurementResourceOrdinal",localMeasurementField(measurement,"ResourceOrdinal",NaN), ...
    "MeasurementSlot",localMeasurementField(measurement,"Slot",NaN), ...
    "MeasurementProvenance",localMeasurementField(measurement,"Provenance", ...
        "measured_runtime_compatibility"), ...
    "ConfiguredOracleUsed",false, ...
    "ChannelStateInformationMode",reportConfig.ReportQuantity, ...
    "CSIReportConfiguration",reportConfig, ...
    "TypedReport",report, ...
    "CSIPart1Bits",report.Part1Bits, ...
    "CSIPart2Bits",report.Part2Bits, ...
    "CSIPayloadBitLength",numel(report.Part1Bits)+numel(report.Part2Bits), ...
    "CustomContainerUsed",false, ...
    "ConfiguredSNRUsed",false, ...
    "SVDThresholdUsed",false, ...
    "SingularValueSource",singularValueSource, ...
    "SelectionInfo",selection);
end

function [singularValues,source] = localSpatialSingularValues(H)
H = double(H);
if ismatrix(H)
    singularValues = svd(H);
    source = "measured_channel_matrix_svd";
    return;
end
% Preserve frequency-selective energy and spatial modes through the
% average transmit-side covariance.  This is invariant to arbitrary phase
% rotation between resource snapshots, unlike mean(H,3).
snapshotCount = size(H,3);
covariance = complex(zeros(size(H,2)));
for snapshot = 1:snapshotCount
    Hs = H(:,:,snapshot);
    covariance = covariance + Hs' * Hs;
end
covariance = covariance ./ max(snapshotCount,1);
eigenvalues = sort(real(eig((covariance + covariance') ./ 2)),"descend");
singularValues = sqrt(max(eigenvalues,0));
source = "frequency_snapshot_average_transmit_covariance";
end

function cri = localMeasuredCRI(measurement, numResources, strict)
if isempty(measurement)
    if strict && numResources > 1
        error("sixgr:mimo:MissingMeasurementState", ...
            "A strict multi-resource CSI report requires a measured resource identity.");
    end
    cri = 0;
    return;
end
token = char(string(measurement.ResourceID));
if isfinite(double(measurement.ResourceOrdinal))
    cri = double(measurement.ResourceOrdinal);
else
match = regexp(token, '(\d+)$', 'tokens', 'once');
if isempty(match)
    error("sixgr:mimo:BeamReportMismatch", ...
        "Measured CSI-RS resource identity '%s' has no numeric CRI.", token);
end
cri = str2double(match{1});
end
if ~(isscalar(cri) && isfinite(cri) && cri >= 0 && ...
        cri == round(cri) && cri < numResources)
    error("sixgr:mimo:BeamReportMismatch", ...
        "Measured CRI %g is outside the report configuration range [0,%d].", ...
        cri, numResources - 1);
end
end

function value = localMeasurementField(measurement,name,defaultValue)
if isempty(measurement)
    value = defaultValue;
else
    value = measurement.(name);
end
end

function cqi = localCQI(sinrDB,cfg,strict)
thresholds = double(sixgr.util.structGet(cfg,"CQISINRThresholdsDB", ...
    [-Inf -6.7 -4.7 -2.3 0.2 2.4 4.3 5.9 8.1 10.3 11.7 14.1 16.3 18.7 21 22.7]));
if numel(thresholds) ~= 16 || any(diff(thresholds)<0)
    if strict
        error("sixgr:mimo:InvalidCQI", ...
            "Strict CQI selection requires 16 ordered calibrated thresholds.");
    end
    thresholds = [-Inf -6.7 -4.7 -2.3 0.2 2.4 4.3 5.9 8.1 10.3 11.7 14.1 16.3 18.7 21 22.7];
end
cqi = find(sinrDB>=thresholds,1,"last")-1;
cqi = max(0,min(15,cqi));
end
