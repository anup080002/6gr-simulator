function out = measureSSSINRFromSSBGrid(ssbGrid, nCellID, iBarSSB)
%MEASURESSSINRFROMSSBGRID Measure practical TS 38.215 SS-SINR evidence.
%   The desired-power term is the SSS RSRP returned by nrSSBMeasurements.
%   Noise plus interference is measured from genuinely unoccupied REs in
%   the same 240-by-4 SS/PBCH block bandwidth.  No configured SNR, PBCH
%   post-equalization SINR, or padded resource-grid samples are used.

if nargin < 3
    iBarSSB = NaN;
end
validateattributes(ssbGrid, {'single', 'double'}, ...
    {"nonempty", "finite"}, mfilename, "ssbGrid");
if size(ssbGrid, 1) ~= 240 || size(ssbGrid, 2) ~= 4
    error("sixgr:refsig:InvalidSSBGridDimensions", ...
        "SS-SINR requires an exact 240-by-4-by-NRx SS/PBCH grid.");
end
validateattributes(nCellID, {'numeric'}, ...
    {"scalar", "integer", ">=", 0, "<=", 1007}, mfilename, "nCellID");

out = struct( ...
    "Available", false, ...
    "SS_SINR_dB", NaN, ...
    "SS_SINRPerReceiveAntenna_dB", nan(1, size(ssbGrid, 3)), ...
    "RawObservedSS_RSRP_dBm", NaN, ...
    "RawObservedSS_RSRPPerReceiveAntenna_dBm", nan(1, size(ssbGrid, 3)), ...
    "NoiseDebiasedSS_RSRP_dBm", NaN, ...
    "NoiseDebiasedSS_RSRPPerReceiveAntenna_dBm", nan(1, size(ssbGrid, 3)), ...
    "RSRPPowerPerReceiveAntenna_W", nan(1, size(ssbGrid, 3)), ...
    "NoiseInterferencePowerPerReceiveAntenna_W", nan(1, size(ssbGrid, 3)), ...
    "DesiredPowerPerReceiveAntenna_W", nan(1, size(ssbGrid, 3)), ...
    "NoiseInterferenceRECount", 0, ...
    "MeasurementMethod", ...
        "ts38215_sss_rsrp_over_same_ssb_bandwidth_unoccupied_re_noise_interference", ...
    "ReferencePlane", "ue_antenna_connector_received_ssb_grid", ...
    "AntennaAggregation", "maximum_valid_receive_branch_ts38215_diversity_rule", ...
    "Status", "not_attempted", ...
    "FailureReason", "");

try
    if isfinite(iBarSSB) && iBarSSB >= 0 && iBarSSB <= 7 && iBarSSB == round(iBarSSB)
        measurements = nrSSBMeasurements(ssbGrid, nCellID, iBarSSB);
    else
        measurements = nrSSBMeasurements(ssbGrid, nCellID);
    end

    occupied = false(240, 4);
    occupied(nrPSSIndices) = true;
    occupied(nrSSSIndices) = true;
    occupied(nrPBCHIndices(nCellID)) = true;
    occupied(nrPBCHDMRSIndices(nCellID)) = true;
    noiseIndices = find(~occupied);
    out.NoiseInterferenceRECount = numel(noiseIndices);
    if isempty(noiseIndices)
        error("sixgr:refsig:NoSSBNoiseInterferenceREs", ...
            "The received SS/PBCH block has no unoccupied REs for noise/interference measurement.");
    end

    rsrp_dBm = double(measurements.RSRPPerAntenna(:).');
    nRx = size(ssbGrid, 3);
    if numel(rsrp_dBm) ~= nRx
        error("sixgr:refsig:SSBMeasurementAntennaMismatch", ...
            "nrSSBMeasurements returned %d branches for an NRx=%d grid.", ...
            numel(rsrp_dBm), nRx);
    end
    for rxIdx = 1:nRx
        branchGrid = double(ssbGrid(:, :, rxIdx));
        noiseInterference_W = mean(abs(branchGrid(noiseIndices)).^2, "omitnan");
        rsrp_W = 10 .^ ((rsrp_dBm(rxIdx) - 30) / 10);
        % nrSSBMeasurements observes noisy SSS REs.  Removing the measured
        % same-bandwidth noise contribution prevents a positive low-SNR
        % bias while preserving the TS 38.215 desired-power definition.
        desired_W = max(rsrp_W - noiseInterference_W, 0);
        out.RSRPPowerPerReceiveAntenna_W(rxIdx) = rsrp_W;
        out.NoiseInterferencePowerPerReceiveAntenna_W(rxIdx) = noiseInterference_W;
        out.DesiredPowerPerReceiveAntenna_W(rxIdx) = desired_W;
        out.RawObservedSS_RSRPPerReceiveAntenna_dBm(rxIdx) = rsrp_dBm(rxIdx);
        if isfinite(desired_W) && desired_W > 0
            out.NoiseDebiasedSS_RSRPPerReceiveAntenna_dBm(rxIdx) = ...
                10 * log10(desired_W) + 30;
        end
        if isfinite(desired_W) && desired_W > 0 && ...
                isfinite(noiseInterference_W) && noiseInterference_W > 0
            out.SS_SINRPerReceiveAntenna_dB(rxIdx) = ...
                10 * log10(desired_W / noiseInterference_W);
        end
    end
    finiteSINR = out.SS_SINRPerReceiveAntenna_dB( ...
        isfinite(out.SS_SINRPerReceiveAntenna_dB));
    finiteRawRSRP = out.RawObservedSS_RSRPPerReceiveAntenna_dBm( ...
        isfinite(out.RawObservedSS_RSRPPerReceiveAntenna_dBm));
    if ~isempty(finiteRawRSRP)
        out.RawObservedSS_RSRP_dBm = max(finiteRawRSRP);
    end
    finiteDesiredRSRP = out.NoiseDebiasedSS_RSRPPerReceiveAntenna_dBm( ...
        isfinite(out.NoiseDebiasedSS_RSRPPerReceiveAntenna_dBm));
    if ~isempty(finiteDesiredRSRP)
        out.NoiseDebiasedSS_RSRP_dBm = max(finiteDesiredRSRP);
    end
    if isempty(finiteSINR)
        out.Status = "unavailable_nonpositive_desired_power_or_noise";
        out.FailureReason = ...
            "No receive branch had finite positive desired and noise/interference power.";
        return;
    end
    out.SS_SINR_dB = max(finiteSINR);
    out.Available = true;
    out.Status = "available";
catch ME
    out.Status = "failed:" + string(ME.identifier);
    out.FailureReason = string(ME.message);
end
end
