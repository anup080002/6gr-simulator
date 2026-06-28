function result = runCSIRSOracleValidation(cfg, varargin)
%RUNCSIRSORACLEVALIDATION CSI-RS practical-estimator validation with oracle NMSE.
%
% The runtime estimator remains pilot-only. The true effective channel is
% supplied only to channelEstimate with OracleTestMode=true so validation can
% compute NMSE against a known channel without using it to produce Hest.

p = inputParser;
p.addRequired("cfg", @isstruct);
p.addParameter("Carrier", [], @(x) isempty(x) || isobject(x));
p.addParameter("PortCounts", [1 2 4], @(x) isnumeric(x) && isvector(x));
p.addParameter("NSizeGrid", [], @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
p.addParameter("SNRdB", Inf, @(x) isnumeric(x) && isscalar(x));
p.addParameter("RunId", "csirs_oracle_validation", @(x) ischar(x) || isstring(x));
p.parse(cfg, varargin{:});
opt = p.Results;

if isempty(opt.Carrier)
    cfgCarrier = cfg;
    if ~isempty(opt.NSizeGrid)
        cfgCarrier = sixgr.util.structSet(cfgCarrier, "phy.carrier.NSizeGrid", double(opt.NSizeGrid));
    end
    [carrier, ~] = sixgr.phy.grid.makeCarrier(cfgCarrier);
else
    carrier = opt.Carrier;
end

portCounts = unique(max(1, round(double(opt.PortCounts(:).'))), "stable");
rows = repmat(localTrialRow(), 0, 1);
mappingTables = cell(numel(portCounts), 1);
for ii = 1:numel(portCounts)
    cfgCase = cfg;
    cfgCase = sixgr.util.structSet(cfgCase, "phy.csirs.enable", true);
    cfgCase = sixgr.util.structSet(cfgCase, "phy.csirs.nPorts", double(portCounts(ii)));
    cfgCase = sixgr.util.structSet(cfgCase, "phy.csirs.numRB", double(carrier.NSizeGrid));
    cfgCase = sixgr.util.structSet(cfgCase, "phy.csirs.rbOffset", 0);
    if ~isfield(sixgr.util.structGet(cfgCase, "phy.csirs", struct()), "symbolLocations")
        cfgCase = sixgr.util.structSet(cfgCase, "phy.csirs.symbolLocations", 4);
    end

    [csirsInd, csirsSym, csirsInfo] = sixgr.phy.refsig.csirs(carrier, cfgCase);
    [rxGrid, trueChannel] = localBuildObservedCSIRSGrid(carrier, csirsInd, csirsSym, csirsInfo, double(opt.SNRdB));
    cdmLengths = localCSIRSCDMLengths(csirsInfo);
    [~, ~, estInfo] = sixgr.phy.rx.channelEstimate(carrier, rxGrid, csirsInd, csirsSym, ...
        "CDMLengths", cdmLengths, ...
        "ExpectedTxPorts", double(csirsInfo.NumCSIRSPorts), ...
        "TrueChannel", trueChannel, ...
        "OracleTestMode", true, ...
        "EffectiveChannelConvention", "csirs_effective_channel_grid_validation_only", ...
        "ContextLabel", "runCSIRSOracleValidation");

    row = localTrialRow();
    row.RunId = string(opt.RunId);
    row.TrialIndex = double(ii);
    row.NSizeGrid = double(carrier.NSizeGrid);
    row.SubcarrierSpacing_kHz = double(carrier.SubcarrierSpacing);
    row.RowNumber = double(csirsInfo.RowNumber);
    row.NumPortsRequested = double(portCounts(ii));
    row.NumPortsResolved = double(csirsInfo.NumCSIRSPorts);
    row.CDMType = string(csirsInfo.CDMType);
    row.Density = string(csirsInfo.Density);
    row.CDMLengthFrequency = double(cdmLengths(1));
    row.CDMLengthTime = double(cdmLengths(2));
    row.NRE = double(numel(csirsSym));
    row.Estimator = string(estInfo.EngineUsed);
    row.EstimatorUsesTrueChannel = logical(estInfo.EstimatorUsesTrueChannel);
    row.OracleTestMode = logical(estInfo.OracleTestMode);
    row.OracleAvailable = logical(estInfo.OracleAvailable);
    row.UsedOracleFields = string(estInfo.UsedOracleFields);
    row.OracleNMSE_dB = double(estInfo.OracleNMSE_dB);
    row.PilotResidualNMSE_dB = double(estInfo.PilotResidualNMSE_dB);
    row.EffectiveChannelConvention = string(estInfo.EffectiveChannelConvention);
    row.ValidationStatus = string(localValidationStatus(row));
    rows(end + 1, 1) = row; %#ok<AGROW>
    mappingTables{ii} = csirsInfo.ResourceMappingTable;
end

trialTable = struct2table(rows, "AsArray", true);
result = struct();
result.RunId = string(opt.RunId);
result.TrialTable = trialTable;
result.ResourceMappingTables = mappingTables;
result.StrictOk = ~isempty(trialTable) && all(string(trialTable.ValidationStatus) == "OK");
result.ValidationSource = "sixgr.phy.refsig.runCSIRSOracleValidation";
result.RuntimeEstimatorPolicy = "pilot_only_true_channel_oracle_validation_diagnostic";
end

function [rxGrid, trueChannel] = localBuildObservedCSIRSGrid(carrier, csirsInd, csirsSym, csirsInfo, snrDb)
K = double(carrier.NSizeGrid) * 12;
L = double(carrier.SymbolsPerSlot);
P = max(1, round(double(csirsInfo.NumCSIRSPorts)));
R = 1;
trueChannel = complex(zeros(K, L, R, P));
for pp = 1:P
    trueChannel(:, :, 1, pp) = complex(0.35 + 0.07 * pp, 0.45 - 0.03 * pp);
end
rxGrid = complex(zeros(K, L, R));
for nn = 1:numel(csirsInd)
    [kk, ll, pp] = ind2sub([K L P], double(csirsInd(nn)));
    rxGrid(kk, ll, 1) = rxGrid(kk, ll, 1) + trueChannel(kk, ll, 1, pp) .* csirsSym(nn);
end
if isfinite(double(snrDb))
    sigPow = mean(abs(rxGrid(:)).^2, "omitnan");
    if ~(isfinite(sigPow) && sigPow > 0)
        sigPow = 1;
    end
    [rxGrid, ~] = sixgr.util.addAwgnComplex(rxGrid, double(snrDb), "SignalPower", sigPow);
end
end

function cdmLengths = localCSIRSCDMLengths(info)
token = upper(strtrim(string(sixgr.util.structGet(info, "CDMType", ""))));
if contains(token, "CDM8")
    cdmLengths = [2 4];
elseif contains(token, "CDM4")
    cdmLengths = [2 2];
elseif contains(token, "FD-CDM2") || contains(token, "FD_CDM2")
    cdmLengths = [2 1];
else
    cdmLengths = [1 1];
end
end

function status = localValidationStatus(row)
if logical(row.EstimatorUsesTrueChannel) || strlength(strtrim(string(row.UsedOracleFields))) > 0
    status = "estimator_used_oracle";
elseif ~logical(row.OracleAvailable) || ~isfinite(double(row.OracleNMSE_dB))
    status = "oracle_nmse_unavailable";
elseif double(row.OracleNMSE_dB) > -90
    status = "oracle_nmse_above_tolerance";
else
    status = "OK";
end
end

function row = localTrialRow()
row = struct("RunId", "", "TrialIndex", NaN, "NSizeGrid", NaN, ...
    "SubcarrierSpacing_kHz", NaN, "RowNumber", NaN, ...
    "NumPortsRequested", NaN, "NumPortsResolved", NaN, ...
    "CDMType", "", "Density", "", "CDMLengthFrequency", NaN, ...
    "CDMLengthTime", NaN, "NRE", NaN, "Estimator", "", ...
    "EstimatorUsesTrueChannel", false, "OracleTestMode", false, ...
    "OracleAvailable", false, "UsedOracleFields", "", ...
    "OracleNMSE_dB", NaN, "PilotResidualNMSE_dB", NaN, ...
    "EffectiveChannelConvention", "", "ValidationStatus", "");
end

