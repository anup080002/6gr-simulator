classdef NRCSIReportEngine
    %NRCSIREPORTENGINE Release-pinned TS 38.214 CSI reporting authority.
    %   R2026a ships the standardized RI/PMI/CQI implementation behind
    %   nr5g.internal while the public nrCSIReportCSIRS feature is disabled
    %   in some installations. This adapter calls the same MathWorks
    %   TS 38.214 engines directly and records that exact provenance.

    methods (Static)
        function csi = run(carrier,csirs,dmrs,H,nVar,cfg,measurement,options)
            arguments
                carrier (1,1) nrCarrierConfig
                csirs (1,1) nrCSIRSConfig
                dmrs (1,1) nrPDSCHDMRSConfig
                H {mustBeNumeric}
                nVar (1,1) double {mustBeNonnegative}
                cfg (1,1) struct
                measurement (1,1) sixgr.phy.mimo.CSIMeasurementState
                options.Direction (1,1) string = "DL"
            end
            localValidateInputs(carrier,csirs,H,cfg,measurement);
            reportRequest = sixgr.util.structGet(cfg,"ReportConfiguration",[]);
            if isempty(reportRequest)
                error("sixgr:mimo:MissingCSIReportConfig", ...
                    "Strict NR CSI execution requires ReportConfiguration.");
            end
            reportConfig = localToolboxReportConfig(carrier,reportRequest,cfg);
            rankDomain = double(sixgr.util.structGet(cfg,"RankDomain",[]));
            reportConfig.RIRestriction = localRIRestriction(rankDomain,reportConfig.CodebookType);

            [ri,~,~] = nr5g.internal.nrRISelect( ...
                carrier,csirs,reportConfig,H,nVar,"MaxSE");
            [cqiValue,pmiSet,cqiInfo,pmiInfo] = ...
                nr5g.internal.nrCQIReport( ...
                carrier,csirs,reportConfig,dmrs,ri,H,nVar);
            W = localWidebandPrecoder(pmiInfo.W,ri);
            cri = localMeasuredCRI(measurement, ...
                double(reportRequest.NumCSIResources));
            typedRequest = reportRequest;
            typedRequest.Rank = double(ri);
            % Verify the selected component tuple maps to the same matrix
            % the scheduler will apply; no analytic H or oracle selection.
            typeII=strcmpi(reportConfig.CodebookType,'type2');
            matrixAuthority="ts38214_single_panel_formula_from_measured_pmi";
            matrixBound=1e-12;
            if typeII
                pmiComponents=sixgr.phy.mimo.TypeIICodebook.fromToolboxPMI(typedRequest,pmiSet);
                schedulerW=sixgr.phy.mimo.TypeIICodebook.matrix(typedRequest,pmiComponents);
                % Type-II has coefficient fields, not a Type-I scalar index.
                pmi=struct('i11',NaN,'i12',NaN,'i13',NaN,'i2',NaN,'LinearIndex',NaN);
                matrixAuthority="ts38214_typeII_formula_from_measured_pmi_components";
                % R2026a stores rounded amplitudes. Bound only that known
                % representation difference; never relax the power contract.
                exact=sqrt([0 1/64 1/32 1/16 1/8 1/4 1/2 1]);
                rounded=[0 .125 .1768 .25 .3536 .5 .7071 1];
                matrixBound=2*sqrt(2*typedRequest.NumberOfBeams-1)*max(abs(exact-rounded))+1e-12;
            else
                pmi = localPMIValues(pmiSet,pmiInfo.Codebook);
                pmiComponents=struct("PMI_I11",pmi.i11,"PMI_I12",pmi.i12, ...
                    "PMI_I13",pmi.i13,"PMI_I2",pmi.i2);
                schedulerPMI=sixgr.phy.mimo.TypeISinglePanelCodebook.linearIndex(typedRequest,pmiComponents);
                schedulerW=sixgr.phy.mimo.TypeISinglePanelCodebook.matrix(typedRequest,schedulerPMI);
                assert(schedulerPMI==pmi.LinearIndex,'sixgr:mimo:PrecoderAuthorityMismatch', ...
                    'Measured Type-I PMI must retain its exact codebook index.');
            end
            assert(norm(schedulerW-W,'fro')<=matrixBound, ...
                'sixgr:mimo:PrecoderAuthorityMismatch', ...
                'Measured CSI PMI and scheduler codebook must identify the same matrix.');
            toolboxMatrixDigest=sixgr.phy.mimo.MatrixContract.digest(W);
            toolboxMatrixDifference=max(abs(W(:)-schedulerW(:)));
            % The receiver chooses PMI using measured H. Once selected,
            % UE report and scheduler use one deterministic formula matrix
            % so equivalent floating-point expressions cannot fork hashes.
            W=schedulerW;
            typedConfig = sixgr.phy.mimo.CSIReportConfiguration( ...
                typedRequest,double(reportRequest.Epoch));
            [li,liEvidence]=sixgr.phy.mimo.selectCSILayerIndicator( ...
                pmiInfo.SINRPerREPMI,cqiValue);
            values = struct("CRI",cri,"RI",double(ri), ...
                "CQI_CW0",double(cqiValue(1)),"PMI",pmi.LinearIndex, ...
                "PMI_I11",pmi.i11,"PMI_I12",pmi.i12, ...
                "PMI_I13",pmi.i13,"PMI_I2",pmi.i2, ...
                "LI",li);
            if typeII, values.PMIComponents=pmiComponents; end
            typedReport = typedConfig.build(values);
            [singularValues,conditionNumberDB] = ...
                localMeasuredSpatialCondition(measurement.ChannelEstimate,ri);
            objective = localSelectionObjective(pmiInfo);
            effectiveSINR = double(cqiInfo.EffectiveSINR(1));
            csi = struct( ...
                "Direction",upper(options.Direction), ...
                "RI",double(ri),"PMI",pmi.LinearIndex, ...
                "PMI_i1",[pmi.i11 pmi.i12 pmi.i13], ...
                "PMI_i2",pmi.i2,"PMISet",pmiSet, ...
                "PMI_I11",pmi.i11,"PMI_I12",pmi.i12,"PMI_I13",pmi.i13,"PMI_I2",pmi.i2, ...
                "CQI",double(cqiValue(1)),"LI",li, ...
                "CRI",cri,"WidebandSINR_dB",effectiveSINR, ...
                "Precoder_W",W, ...
                "PrecoderMatrixAuthority",matrixAuthority, ...
                "ToolboxPrecoderMatrixSHA256",toolboxMatrixDigest, ...
                "PrecoderMatrixMaxAbsToolboxDifference",toolboxMatrixDifference, ...
                "PrecoderMatrixSHA256",sixgr.phy.mimo.MatrixContract.digest(W), ...
                "ConditionNumber_dB",conditionNumberDB, ...
                "SingularValues",singularValues, ...
                "RankCandidateObjective",objective, ...
                "RankDomain",rankDomain, ...
                "RankDecisionReason","ts38214_maximum_spectral_efficiency", ...
                "RuntimeEvidenceSource", ...
                    "measured_csirs_nr5g_r2026a_ts38214_ri_pmi_cqi", ...
                "MeasurementID",measurement.MeasurementID, ...
                "MeasurementResourceID",measurement.ResourceID, ...
                "MeasurementResourceOrdinal",measurement.ResourceOrdinal, ...
                "MeasurementSlot",measurement.Slot, ...
                "MeasurementProvenance",measurement.Provenance, ...
                "ConfiguredOracleUsed",false, ...
                "ChannelStateInformationMode",typedConfig.ReportQuantity, ...
                "CSIReportConfiguration",typedConfig, ...
                "TypedReport",typedReport, ...
                "CSIPart1Bits",typedReport.Part1Bits, ...
                "CSIPart2Bits",typedReport.Part2Bits, ...
                "CSIPayloadBitLength",numel(typedReport.Part1Bits)+numel(typedReport.Part2Bits), ...
                "CustomContainerUsed",false, ...
                "ConfiguredSNRUsed",false, ...
                "SVDThresholdUsed",false, ...
                "SelectionInfo",struct( ...
                    "LayerIndicatorEvidence",liEvidence, ...
                    "SelectedSINRPerRELayer",pmiInfo.SINRPerREPMI, ...
                    "SelectedMetric",objective, ...
                    "SelectedRank",double(ri), ...
                    "SelectedPMI",pmi.LinearIndex, ...
                    "PMISet",pmiSet, ...
                    "MatrixSHA256",sixgr.phy.mimo.MatrixContract.digest(W), ...
                    "Specification","TS38.214_R18_via_MathWorks_R2026a", ...
                    "ExecutionEngine","nr5g.internal.nrRISelect+nrCQIReport", ...
                    "ConfiguredSNRUsed",false,"SVDThresholdUsed",false));
            if typeII
                csi.PMIComponents=pmiComponents;
                csi.PMIIndexRepresentation="typeII_coefficient_fields_no_scalar_index";
                csi.PrecoderMatrixToolboxFrobeniusBound=matrixBound;
            end
        end
    end
end

function localValidateInputs(carrier,csirs,H,cfg,measurement)
if isempty(H) || ndims(H) ~= 4 || ...
        size(H,1) ~= 12*double(carrier.NSizeGrid) || ...
        size(H,2) ~= double(carrier.SymbolsPerSlot) || ...
        size(H,4) ~= double(max(csirs.NumCSIRSPorts)) || ...
        any(~isfinite(real(H(:))) | ~isfinite(imag(H(:))))
    error("sixgr:mimo:MissingMeasurementState", ...
        "Strict NR CSI requires finite K-by-L-by-Nrx-by-P runtime CSI-RS Hest.");
end
if size(H,4) ~= size(measurement.ChannelEstimate,2)
    error("sixgr:mimo:MeasurementIdentityMismatch", ...
        "Full CSI-RS Hest and immutable wideband measurement have different port counts.");
end
if string(version("-release")) ~= "2026a" || ...
        isempty(which("nr5g.internal.nrRISelect")) || ...
        isempty(which("nr5g.internal.nrCQIReport"))
    error("sixgr:mimo:UnsupportedToolboxRelease", ...
        "Strict high-port CSI is release-pinned to MATLAB 5G Toolbox R2026a.");
end
if ~logical(sixgr.util.structGet(cfg,"Strict",false))
    error("sixgr:mimo:StrictModeRequired", ...
        "NRCSIReportEngine is reserved for strict runtime CSI evidence.");
end
end

function reportConfig = localToolboxReportConfig(carrier,request,cfg)
reportConfig = nrCSIReportConfig;
reportConfig.NStartBWP = double(carrier.NStartGrid);
reportConfig.NSizeBWP = double(carrier.NSizeGrid);
reportConfig.CQITable = string(sixgr.util.structGet(cfg,"CQITable", ...
    sixgr.util.structGet(cfg,"cqiTable","table1")));
reportConfig.CodebookType = localCodebookType(request.CodebookType);
reportConfig.PanelDimensions = [double(sixgr.util.structGet(request,"Panels",1)), ...
    double(request.N1),double(request.N2)];
if strcmpi(reportConfig.CodebookType,'type2')
    % Validate the same installed subset as the independent wire decoder
    % before running any selection. Unsupported restrictions are not ignored.
    wire=sixgr.phy.mimo.CSIReportConfiguration(request,double(request.Epoch));
    wire.assertQualifiedWireLayout();
    reportConfig.NumberOfBeams=double(request.NumberOfBeams);
    reportConfig.PhaseAlphabetSize=double(request.PhaseAlphabetSize);
    reportConfig.SubbandAmplitude=false; % Wideband-only qualified subset.
else
    reportConfig.CodebookMode = double(request.CodebookMode);
end
granularity = lower(string(request.FrequencyGranularity));
reportConfig.CQIFormatIndicator = granularity;
reportConfig.PMIFormatIndicator = granularity;
if granularity == "subband"
    reportConfig.SubbandSize = double(sixgr.util.structGet(request,"SubbandSize",4));
end
reportConfig.CodebookSubsetRestriction = double(sixgr.util.structGet( ...
    request,"CodebookSubsetRestriction",[]));
reportConfig.I2Restriction = double(sixgr.util.structGet(request,"I2Restriction",[]));
end

function token = localCodebookType(raw)
token = lower(regexprep(string(raw),'[^a-zA-Z0-9]',''));
if token == "typeisinglepanel" || token == "type1singlepanel"
    token = "type1SinglePanel";
elseif token == "typeii"
    token = "type2";
else
    error("sixgr:mimo:UnsupportedProfile", ...
        "High-port NR CSI enables Type-I single-panel and qualified wideband Type-II PUSCH reporting.");
end
end

function restriction = localRIRestriction(rankDomain,codebookType)
maximum=8;
if strcmpi(codebookType,'type2'), maximum=2; end
if isempty(rankDomain) || ~isvector(rankDomain) || any(~ismember(rankDomain,1:maximum))
    error("sixgr:mimo:InvalidRI", ...
        "Strict %s RankDomain must contain explicit values in [1,%d].",codebookType,maximum);
end
restriction = zeros(1,maximum);
restriction(rankDomain) = 1;
end

function W = localWidebandPrecoder(raw,rankValue)
W = complex(double(raw));
if ndims(W) == 3
    if size(W,3) ~= 1
        error("sixgr:mimo:UnsupportedSubbandPMI", ...
            "Wideband strict CSI expected one precoder, observed %d.",size(W,3));
    end
    W = W(:,:,1);
end
sixgr.phy.mimo.MatrixContract.validate(W,size(W,1),rankValue);
end

function out = localPMIValues(pmiSet,codebook)
i1 = double(pmiSet.i1(:).');
i2 = double(pmiSet.i2(:).');
if numel(i1) ~= 3 || numel(i2) ~= 1 || ...
        any(~isfinite([i1 i2])) || any([i1 i2] < 1)
    error("sixgr:mimo:InvalidPMI", ...
        "Type-I wideband PMI must contain one-based i1=[i11 i12 i13] and scalar i2.");
end
dims = [size(codebook,3),size(codebook,4), ...
    size(codebook,5),size(codebook,6)];
subscripts = [i2 i1];
if any(subscripts > dims)
    error("sixgr:mimo:InvalidPMI", ...
        "Reported PMI indices exceed the release-pinned codebook dimensions.");
end
linearIndex = sub2ind(dims,subscripts(1),subscripts(2), ...
    subscripts(3),subscripts(4)) - 1;
out = struct("i11",i1(1)-1,"i12",i1(2)-1, ...
    "i13",i1(3)-1,"i2",i2(1)-1,"LinearIndex",double(linearIndex));
end

function cri = localMeasuredCRI(measurement,numResources)
cri = double(measurement.ResourceOrdinal);
if ~(isscalar(cri) && isfinite(cri) && cri >= 0 && ...
        cri == round(cri) && cri < numResources)
    error("sixgr:mimo:BeamReportMismatch", ...
        "Measured CRI %g is outside [0,%d].",cri,numResources-1);
end
end

function [singularValues,conditionNumberDB] = localMeasuredSpatialCondition(H,rankValue)
H = double(H);
if ismatrix(H)
    covariance = H' * H;
else
    covariance = complex(zeros(size(H,2)));
    for k = 1:size(H,3)
        covariance = covariance + H(:,:,k)'*H(:,:,k);
    end
    covariance = covariance/max(1,size(H,3));
end
singularValues = sqrt(max(sort(real(eig((covariance+covariance')/2)),"descend"),0));
if numel(singularValues) >= rankValue && singularValues(rankValue) > 0
    conditionNumberDB = 20*log10(singularValues(1)/singularValues(rankValue));
else
    conditionNumberDB = Inf;
end
end

function objective = localSelectionObjective(info)
sinr = double(sixgr.util.structGet(info,"SINRPerSubbandPMI",[]));
if isempty(sinr) || any(~isfinite(sinr(:))) || any(sinr(:) < 0)
    error("sixgr:mimo:MissingMeasurementState", ...
        "Release-pinned PMI engine returned no finite measured SINR objective.");
end
objective = mean(sum(log2(1+sinr),2),"omitnan");
end
