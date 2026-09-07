function out = measureSSSINRFromSSBGrid(ssbGrid, nCellID, iBarSSB)
%MEASURESSSINRFROMSSBGRID Measure practical TS 38.215 SS-SINR evidence.
%   Linear per-RE SSS power (38.215 5.1.1/5.1.5), not squared coherent
%   frequency averaging. Disturbance is estimated on the received SSS
%   reference REs by nrChannelEstimate, separately per receive branch.
%   No unconfigured null-RE interference resource, oracle channel, fixed
%   SNR or padded receive samples are substituted for that measurement.

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
        "ts38215_sss_linear_re_power_received_reference_disturbance_same_ssb_bandwidth", ...
    "NoiseInterferenceEstimator", "nrChannelEstimate_on_SSS_reference_REs_per_receive_branch", ...
    "ReferenceSignals", "SSS_only", ...
    "ReferencePlane", "ue_antenna_connector_received_ssb_grid", ...
    "AntennaAggregation", "maximum_valid_receive_branch_ts38215_diversity_rule", ...
    "Status", "not_attempted", ...
    "FailureReason", "");

try
    % PBCH DM-RS is optional for these measurements. Use the mandatory SSS
    % set only, avoiding an implicit equal-EPRE assumption for mixed RSs.
    sssIndices=nrSSSIndices;
    reference=complex(zeros(240,4,'like',real(ssbGrid)));
    reference(sssIndices)=nrSSS(nCellID);
    out.NoiseInterferenceRECount=numel(sssIndices);
    nRx = size(ssbGrid, 3);
    for rxIdx = 1:nRx
        branchGrid = double(ssbGrid(:, :, rxIdx));
        rsrp_W=mean(abs(branchGrid(sssIndices)).^2);
        [~,noiseInterference_W]=nrChannelEstimate(branchGrid,double(reference),'CDMLengths',[1 1]);
        if ~isscalar(noiseInterference_W) || ~isfinite(noiseInterference_W) || noiseInterference_W<0
            error('sixgr:refsig:InvalidSSSReceivedDisturbance','SSS reference estimation did not produce a finite nonnegative variance.');
        end
        % The full per-RE disturbance belongs to a linear per-RE power
        % estimator. Subtracting it from squared coherent-mean power was
        % inconsistent and erased valid frequency-selective received power.
        desired_W = max(rsrp_W - noiseInterference_W, 0);
        out.RSRPPowerPerReceiveAntenna_W(rxIdx) = rsrp_W;
        out.NoiseInterferencePowerPerReceiveAntenna_W(rxIdx) = noiseInterference_W;
        out.DesiredPowerPerReceiveAntenna_W(rxIdx) = desired_W;
        out.RawObservedSS_RSRPPerReceiveAntenna_dBm(rxIdx) = 10*log10(rsrp_W)+30;
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
