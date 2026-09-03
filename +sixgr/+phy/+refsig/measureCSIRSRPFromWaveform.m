function evidence = measureCSIRSRPFromWaveform(carrier, csirsConfig, waveform, varargin)
%MEASURECSIRSRPFROMWAVEFORM Measure CSI-RS power on a physical waveform.
%
% The waveform must use the repository PowerContext convention where
% abs(sample)^2 is mW.  The routine demodulates the exact waveform that is
% passed to it, converts the unnormalised OFDM grid to sqrt(W), and delegates
% the resource measurement to nrCSIRSMeasurements.  It does not reconstruct
% a waveform from configuration and it does not use configured SNR.

ip = inputParser;
ip.addParameter("ReferencePlane", "", @(x) ischar(x) || isstring(x));
ip.addParameter("Source", "", @(x) ischar(x) || isstring(x));
ip.addParameter("AntennaAggregation", "sum_linear", @(x) ischar(x) || isstring(x));
ip.addParameter("PhysicalIndices", [], @isnumeric);
ip.parse(varargin{:});
o = ip.Results;

evidence = struct( ...
    "Available", false, ...
    "RSRP_dBm", NaN, ...
    "RSRPPerAntenna_dBm", "", ...
    "AntennaAggregation", "", ...
    "ReferencePlane", char(string(o.ReferencePlane)), ...
    "Source", char(string(o.Source)), ...
    "Status", "not_attempted", ...
    "ErrorIdentifier", "", ...
    "ErrorMessage", "", ...
    "Nfft", NaN, ...
    "GridScaleToSqrtW", NaN, ...
    "MeasurementMethod", "", ...
    "MappedREPerAntenna", "");

if isempty(waveform) || ~isnumeric(waveform) || ...
        any(~isfinite(real(waveform(:)))) || any(~isfinite(imag(waveform(:))))
    evidence.Status = "unavailable_invalid_physical_waveform";
    return;
end
configs = localConfigs(csirsConfig);
if isempty(configs)
    evidence.Status = "unavailable_missing_runtime_csirs_configuration";
    return;
end

try
    [grid, ofdmInfo] = sixgr.phy.waveform.ofdmDemodulate(carrier, waveform);
    nfft = double(sixgr.util.structGet(ofdmInfo, "Nfft", NaN));
    if ~(isscalar(nfft) && isfinite(nfft) && nfft >= 1 && nfft == round(nfft))
        info = nrOFDMInfo(carrier);
        nfft = double(info.Nfft);
    end
    scale = nfft * sqrt(1000); % sqrt(mW) FFT grid -> sqrt(W)
    physicalGrid = grid ./ cast(scale, "like", grid);

    physicalIndices = double(o.PhysicalIndices(:));
    if isempty(physicalIndices)
        [perAntennaW, mappedRE] = localReceiverMeasurement( ...
            carrier, configs, physicalGrid);
        method = "nrCSIRSMeasurements_receiver_branch_rsrp";
    else
        [perAntennaW, mappedRE] = localTransmitConnectorMeasurement( ...
            physicalGrid, physicalIndices);
        method = "exact_nonzero_transmitted_csirs_re_per_physical_connector";
    end
    if isempty(perAntennaW)
        evidence.Status = "unavailable_empty_csirs_power_measurement";
        return;
    end
    mode = lower(strtrim(string(o.AntennaAggregation)));
    switch mode
        case "sum_linear"
            powerW = sum(perAntennaW);
            aggregation = "sum_linear_across_physical_antenna_connectors";
        case "maximum"
            powerW = max(perAntennaW);
            aggregation = "maximum_receive_antenna_branch_ts_38_215";
        otherwise
            error("sixgr:phy:refsig:InvalidCSIRSAntennaAggregation", ...
                "CSI-RS waveform measurement aggregation must be sum_linear or maximum.");
    end
    evidence.Available = isfinite(powerW) && powerW > 0;
    evidence.RSRP_dBm = 10 * log10(powerW) + 30;
    evidence.RSRPPerAntenna_dBm = char(localVectorToken(10 .* log10(perAntennaW) + 30));
    evidence.AntennaAggregation = char(aggregation);
    evidence.Status = "available_exact_waveform_csirs_measurement";
    evidence.Nfft = nfft;
    evidence.GridScaleToSqrtW = scale;
    evidence.MeasurementMethod = char(method);
    evidence.MappedREPerAntenna = char(localVectorToken(mappedRE));
catch ME
    evidence.Status = "unavailable_csirs_waveform_measurement_failed";
    evidence.ErrorIdentifier = char(string(ME.identifier));
    evidence.ErrorMessage = char(string(ME.message));
end

function [perAntennaW, mappedRE] = localReceiverMeasurement( ...
        carrier, configs, physicalGrid)
perAntennaW = zeros(0, 1);
mappedRE = zeros(0, 1);
for idx = 1:numel(configs)
    measured = nrCSIRSMeasurements(carrier, configs{idx}, physicalGrid);
    branchdBm = double(measured.RSRPPerAntenna(:));
    valid = isfinite(branchdBm);
    if any(valid)
        perAntennaW = [perAntennaW; ...
            10 .^ ((branchdBm(valid) - 30) ./ 10)]; %#ok<AGROW>
        mappedRE = [mappedRE; repmat(NaN, nnz(valid), 1)]; %#ok<AGROW>
    end
end
end

function [perAntennaW, mappedRE] = localTransmitConnectorMeasurement( ...
        physicalGrid, physicalIndices)
% PDSCH_Tx exports the exact nonzero CSI-RS indices after logical-port
% CDM and the configured port/element precoder have been applied. Those
% indices, rather than receive-port despreading, define connector EPRE.
gridSize = numel(physicalGrid);
if any(~isfinite(physicalIndices) | physicalIndices < 1 | ...
        physicalIndices ~= round(physicalIndices) | ...
        physicalIndices > gridSize)
    error("sixgr:phy:refsig:InvalidCSIRSPhysicalIndices", ...
        "Physical CSI-RS indices must address finite one-based entries of the transmitted grid.");
end
if numel(unique(physicalIndices)) ~= numel(physicalIndices)
    error("sixgr:phy:refsig:DuplicateCSIRSPhysicalIndices", ...
        "Physical CSI-RS indices must be unique exact transmitted REs.");
end
K = size(physicalGrid, 1);
L = size(physicalGrid, 2);
P = size(physicalGrid, 3);
plane = K * L;
port = floor((physicalIndices - 1) ./ plane) + 1;
if any(port < 1 | port > P)
    error("sixgr:phy:refsig:InvalidCSIRSPhysicalPort", ...
        "Physical CSI-RS indices address a nonexistent waveform connector.");
end
perAntennaW = nan(P, 1);
mappedRE = zeros(P, 1);
for p = 1:P
    idx = physicalIndices(port == p);
    mappedRE(p) = numel(idx);
    if isempty(idx)
        continue;
    end
    powerW = mean(abs(physicalGrid(idx)).^2);
    if isfinite(powerW) && powerW > 0
        perAntennaW(p) = powerW;
    end
end
valid = isfinite(perAntennaW) & perAntennaW > 0;
if ~all(valid)
    error("sixgr:phy:refsig:MissingCSIRSPhysicalConnectorEvidence", ...
        ["The configured %d-connector CSI-RS waveform has exact nonzero " + ...
         "runtime evidence on only %d connectors; mapped RE counts are %s."], ...
        P, nnz(valid), char(localVectorToken(mappedRE)));
end
end
end

function configs = localConfigs(value)
configs = cell(0, 1);
if isa(value, "nrCSIRSConfig")
    for idx = 1:numel(value)
        configs{end + 1, 1} = value(idx); %#ok<AGROW>
    end
elseif iscell(value)
    for idx = 1:numel(value)
        if isa(value{idx}, "nrCSIRSConfig")
            configs{end + 1, 1} = value{idx}; %#ok<AGROW>
        end
    end
end
end

function token = localVectorToken(values)
values = double(values(:).');
token = "[" + strjoin(compose("%.15g", values), " ") + "]";
end
