function [y, ctx] = applyPowerContext(x, cfg, direction, txInfo, varargin)
%APPLYPOWERCONTEXT Scale waveform samples to entity-specific Tx power.
%
% Output samples use the PowerContext convention: abs(sample)^2 is mW
% and mean(sum(abs(x_active).^2, ports)) equals total transmit power.
% ApplyPA=false defers the configured nonlinear device to the transmitter's
% composed waveform owner. It does not disable PA in the resolved config.

if nargin < 4
    txInfo = struct();
end
ip = inputParser;
ip.addParameter("PowerContext", struct(), @(v) isempty(v) || isstruct(v));
ip.addParameter("ApplyPA", true, @(v) islogical(v) && isscalar(v));
ip.parse(varargin{:});
ctx = ip.Results.PowerContext;
if ~(isstruct(ctx) && isfield(ctx, "ContractVersion"))
    ctx = sixgr.rf.PowerContext(cfg, direction, "NumPorts", size(x, 2));
end

[inputTotal_mW, inputPerPort_mW, refInfo] = localTotalActivePower_mW(x, txInfo);
fixedSNRNormalizedReference = ...
    upper(strtrim(string(sixgr.util.structGet(cfg, ...
        "integration.run_mode", "")))) == "FIXED_SNR_SWEEP" && ...
    logical(sixgr.util.structGet(cfg, ...
        "integration.configured_snr_is_link_authority", false));
if fixedSNRNormalizedReference
    % A configured-SNR LLS uses normalized baseband Es/N0.  Applying a
    % device EIRP, geometry pathloss, or 38.213 power-control result here
    % would silently replace that operating point.  Preserve the actual
    % IFFT samples and make the arbitrary-but-declared unit mapping
    % explicit: one unit-energy occupied RE is represented as 1 mW.
    % This branch is limited to the connected FIXED_SNR_SWEEP integration
    % mode; physical-link-budget runs retain the absolute-power path.
    if logical(sixgr.util.structGet(cfg, "rf.pa.enable", ...
            sixgr.util.structGet(cfg, "phy.impairments.paNonlinearityEnabled", false)))
        error("sixgr:rf:FixedSNRAbsolutePAReferenceUnsupported", ...
            ["The normalized occupied-RE fixed-SNR path cannot apply an " + ...
             "absolute-voltage PA model. Use a separately declared " + ...
             "normalized-EVM impairment or a physical-link-budget run."]);
    end
    y = x;
    [outputTotal_mW, outputPerPort_mW] = localTotalActivePower_mW(y, txInfo);
    ctx.ScaleApplied = false;
    ctx.AmplitudeScale = 1;
    ctx.InputTotalPower_mW = double(inputTotal_mW);
    ctx.InputTotalPower_dBm = localmWToDbm(inputTotal_mW);
    ctx.InputPerPortPower_mW = double(inputPerPort_mW);
    ctx.InputPerPortPower_dBm = localmWToDbm(inputPerPort_mW);
    ctx.OutputTotalPower_mW = double(outputTotal_mW);
    ctx.OutputTotalPower_dBm = localmWToDbm(outputTotal_mW);
    ctx.OutputPerPortPower_mW = double(outputPerPort_mW);
    ctx.OutputPerPortPower_dBm = localmWToDbm(outputPerPort_mW);
    ctx.TotalTxPower_mW = double(outputTotal_mW);
    ctx.TotalTxPower_dBm = localmWToDbm(outputTotal_mW);
    ctx.TotalTxPower_W = double(outputTotal_mW) * 1e-3;
    ctx.TotalTxPowerSource = ...
        "fixed_snr_unit_occupied_re_reference_not_device_power";
    ctx.ActivePortCount = double(nnz(outputPerPort_mW > ...
        eps(max([outputPerPort_mW(:); 1]))));
    ctx.ReferencePowerDomain = char(string(sixgr.util.structGet( ...
        refInfo, "ReferenceDomain", "")));
    ctx.ReferenceSampleCount = double(sixgr.util.structGet( ...
        refInfo, "SampleCount", numel(x)));
    ctx.PowerNormalizationPolicy = "unit_occupied_re_fixed_esn0";
    ctx.PowerNormalizationSource = ...
        "integration.configured_snr_is_link_authority";
    ctx.FullBWPActivityFactor = NaN;
    ctx.ReferenceInputPower_mW = double(inputTotal_mW);
    ctx.ReferenceInputPower_dBm = localmWToDbm(inputTotal_mW);
    ctx.ReferenceOutputPower_mW = double(outputTotal_mW);
    ctx.ReferenceOutputPower_dBm = localmWToDbm(outputTotal_mW);
    ctx.ActualEmittedPowerBackoffFromBudget_dB = NaN;
    ctx.PowerClosureError_dB = 0;
    ctx.PerPortPowerSum_mW = sum(double(outputPerPort_mW), "omitnan");
    ctx.ExpectedEmittedPower_mW = double(outputTotal_mW);
    ctx.PerPortPowerSumError_mW = ctx.PerPortPowerSum_mW - double(outputTotal_mW);
    ctx.ConversionEquation = ...
        "x_out=x_ifft; occupied_RE_Es_reference=1_mW; no_absolute_power_scaling";
    ctx.FixedSNRNormalizedReference = true;
    ctx.FixedSNRReferenceEnergyPerOccupiedRE = 1;
    ctx.PhysicalDevicePowerClaim = false;
    ctx.PAEnabled = false;
    ctx.PAApplied = false;
    ctx.PAExecutionDeferred = false;
    ctx.PAModel = "disabled_for_normalized_fixed_snr_reference";
    ctx.PAExecutionStatus = "not_applicable_normalized_fixed_snr_reference";
    return;
end
[normalization, normalizationInfo] = localResolveNormalizationReference( ...
    x, cfg, direction, txInfo, inputTotal_mW, refInfo);
scale = 1;
if isfinite(normalization.ReferenceInputPower_mW) && ...
        normalization.ReferenceInputPower_mW > 0 && ...
        isfinite(double(ctx.TotalTxPower_mW)) && double(ctx.TotalTxPower_mW) >= 0
    scale = sqrt(double(ctx.TotalTxPower_mW) / ...
        max(normalization.ReferenceInputPower_mW, realmin));
end
y = x .* cast(scale, "like", x);
[y, paInfo] = localApplyPAContext(y, cfg, ctx, txInfo, ip.Results.ApplyPA);
[outputTotal_mW, outputPerPort_mW] = localTotalActivePower_mW(y, txInfo);

ctx.ScaleApplied = true;
ctx.AmplitudeScale = double(scale);
ctx.InputTotalPower_mW = double(inputTotal_mW);
ctx.InputTotalPower_dBm = localmWToDbm(inputTotal_mW);
ctx.InputPerPortPower_mW = double(inputPerPort_mW);
ctx.InputPerPortPower_dBm = localmWToDbm(inputPerPort_mW);
ctx.OutputTotalPower_mW = double(outputTotal_mW);
ctx.OutputTotalPower_dBm = localmWToDbm(outputTotal_mW);
ctx.OutputPerPortPower_mW = double(outputPerPort_mW);
ctx.OutputPerPortPower_dBm = localmWToDbm(outputPerPort_mW);
ctx.ActivePortCount = double(nnz(outputPerPort_mW > eps(max([outputPerPort_mW(:); 1]))));
ctx.ReferencePowerDomain = char(string(sixgr.util.structGet(refInfo, "ReferenceDomain", "")));
ctx.ReferenceSampleCount = double(sixgr.util.structGet(refInfo, "SampleCount", numel(x)));
ctx.PowerNormalizationPolicy = char(normalization.Policy);
ctx.PowerNormalizationSource = char(normalization.Source);
ctx.FullBWPActivityFactor = double(normalization.FullBWPActivityFactor);
ctx.ReferenceInputPower_mW = double(normalization.ReferenceInputPower_mW);
ctx.ReferenceInputPower_dBm = localmWToDbm(normalization.ReferenceInputPower_mW);
ctx.ReferenceOutputPower_mW = double(outputTotal_mW) ./ ...
    max(double(normalization.FullBWPActivityFactor), realmin);
ctx.ReferenceOutputPower_dBm = localmWToDbm(ctx.ReferenceOutputPower_mW);
ctx.ActualEmittedPowerBackoffFromBudget_dB = ...
    double(ctx.OutputTotalPower_dBm) - double(ctx.TotalTxPower_dBm);
ctx.PowerClosureError_dB = double(ctx.ReferenceOutputPower_dBm) - ...
    double(ctx.TotalTxPower_dBm);
ctx.PerPortPowerSum_mW = sum(double(outputPerPort_mW), "omitnan");
ctx.ExpectedEmittedPower_mW = double(ctx.TotalTxPower_mW) .* ...
    double(normalization.FullBWPActivityFactor);
ctx.PerPortPowerSumError_mW = double(ctx.PerPortPowerSum_mW) - ...
    double(ctx.ExpectedEmittedPower_mW);
ctx.ConversionEquation = char(normalization.Equation);
normalizationFields = fieldnames(normalizationInfo);
for normalizationIdx = 1:numel(normalizationFields)
    ctx.(normalizationFields{normalizationIdx}) = ...
        normalizationInfo.(normalizationFields{normalizationIdx});
end
paFields = fieldnames(paInfo);
for paIdx = 1:numel(paFields)
    ctx.(paFields{paIdx}) = paInfo.(paFields{paIdx});
end

function [normalization, info] = localResolveNormalizationReference( ...
        x, cfg, direction, txInfo, inputTotal_mW, refInfo)
% Resolve the physical reference plane used by the amplitude scaler.
%
% A gNB cell-power setting is a maximum full-band budget.  It must not be
% concentrated into a sparse PDSCH/CSI-RS allocation, because that makes
% reference-signal EPRE depend on the number of scheduled PRBs.  Under the
% full-BWP policy the exact transmitted port grid supplies the occupancy
% factor and the emitted power falls with occupied bandwidth.  UL remains
% allocation-aware because PUSCH/PUCCH/SRS power is resolved by 38.213
% signal-specific power control before this common scaling stage.

direction = upper(strtrim(string(direction)));
[policy, source] = localConfiguredNormalizationPolicy(cfg, direction);
normalization = struct( ...
    "Policy", policy, ...
    "Source", source, ...
    "FullBWPActivityFactor", 1, ...
    "ReferenceInputPower_mW", double(inputTotal_mW), ...
    "Equation", "x_scaled=x*sqrt(Ptx_mW/mean_sum_abs2_active_samples)");
info = struct( ...
    "NormalizationGridSource", "not_required", ...
    "NormalizationGridSubcarrierCount", NaN, ...
    "NormalizationGridActiveSymbolCount", NaN, ...
    "NormalizationGridMeanEnergyPerRE", NaN);

if policy == "active_ofdm_total_power"
    return;
end
if direction ~= "DL" || policy ~= "fixed_epre_over_configured_bwp"
    error("sixgr:rf:UnsupportedPowerNormalizationPolicy", ...
        "Unsupported %s waveform-power normalization policy '%s'.", ...
        direction, policy);
end

[portGrid, gridSource] = localExactTransmitPortGrid(txInfo);
if isempty(portGrid) || ndims(portGrid) < 2
    error("sixgr:rf:DLFullBWPReferenceGridUnavailable", ...
        "DL fixed-EPRE normalization requires the exact transmitted " + ...
        "port-domain resource grid. The waveform must not be normalized " + ...
        "from scheduled occupancy or reconstructed configuration.");
end
nSubcarriers = size(portGrid, 1);
nSymbols = size(portGrid, 2);
activeSymbols0 = double(sixgr.util.structGet( ...
    refInfo, "ActiveSymbolIndices", zeros(0, 1)));
activeSymbols = unique(activeSymbols0(:) + 1, "stable");
activeSymbols = activeSymbols(isfinite(activeSymbols) & ...
    activeSymbols >= 1 & activeSymbols <= nSymbols & ...
    activeSymbols == fix(activeSymbols));
if isempty(activeSymbols)
    error("sixgr:rf:DLFullBWPActiveSymbolsUnavailable", ...
        "DL fixed-EPRE normalization could not bind the waveform's " + ...
        "active OFDM symbols to the exact transmitted port grid.");
end

grid = double(portGrid(:, activeSymbols, :));
totalGridEnergy = sum(abs(grid).^2, "all", "omitnan");
meanEnergyPerRE = totalGridEnergy / ...
    max(1, nSubcarriers * numel(activeSymbols));
if ~(isfinite(meanEnergyPerRE) && meanEnergyPerRE > 0)
    error("sixgr:rf:DLFullBWPReferenceEnergyInvalid", ...
        "The exact DL transmit grid has no finite positive active-RE energy.");
end

normalization.FullBWPActivityFactor = double(meanEnergyPerRE);
normalization.ReferenceInputPower_mW = double(inputTotal_mW) ./ ...
    double(meanEnergyPerRE);
normalization.Equation = ...
    "x_scaled=x*sqrt(Pcell_full_bwp_mW/(Pactive_mW/grid_mean_energy_per_re))";
info.NormalizationGridSource = char(gridSource);
info.NormalizationGridSubcarrierCount = double(nSubcarriers);
info.NormalizationGridActiveSymbolCount = double(numel(activeSymbols));
info.NormalizationGridMeanEnergyPerRE = double(meanEnergyPerRE);
end

function [policy, source] = localConfiguredNormalizationPolicy(cfg, direction)
direction = upper(strtrim(string(direction)));
if direction == "DL"
    candidates = {
        sixgr.util.structGet(cfg, ...
            "lls6g.resolvedConfig.power_and_rf_frontend.downlink_power_normalization_policy", []), ...
            "resolved_config.power_and_rf_frontend.downlink_power_normalization_policy";
        sixgr.util.structGet(cfg, ...
            "powerAndRF.downlinkPowerNormalizationPolicy", []), ...
            "cfg.powerAndRF.downlinkPowerNormalizationPolicy";
        sixgr.util.structGet(cfg, ...
            "rf.downlinkPowerNormalizationPolicy", []), ...
            "cfg.rf.downlinkPowerNormalizationPolicy"};
else
    candidates = {
        sixgr.util.structGet(cfg, ...
            "lls6g.resolvedConfig.power_and_rf_frontend.uplink_power_normalization_policy", []), ...
            "resolved_config.power_and_rf_frontend.uplink_power_normalization_policy";
        sixgr.util.structGet(cfg, ...
            "powerAndRF.uplinkPowerNormalizationPolicy", []), ...
            "cfg.powerAndRF.uplinkPowerNormalizationPolicy";
        sixgr.util.structGet(cfg, ...
            "rf.uplinkPowerNormalizationPolicy", []), ...
            "cfg.rf.uplinkPowerNormalizationPolicy"};
end
policy = "active_ofdm_total_power";
source = "legacy_active_ofdm_total_power_default";
for idx = 1:size(candidates, 1)
    raw = lower(strtrim(string(candidates{idx, 1})));
    raw = raw(strlength(raw) > 0 & ~ismissing(raw));
    if ~isempty(raw)
        policy = raw(1);
        source = string(candidates{idx, 2});
        break;
    end
end
aliases = struct( ...
    "full_bwp_reference_epre", "fixed_epre_over_configured_bwp", ...
    "fixed_full_bwp_epre", "fixed_epre_over_configured_bwp", ...
    "scheduled_active_power", "active_ofdm_total_power");
key = matlab.lang.makeValidName(char(policy));
if isfield(aliases, key)
    policy = string(aliases.(key));
end
end

function [portGrid, source] = localExactTransmitPortGrid(txInfo)
portGrid = sixgr.util.structGet(txInfo, "PortGrid", []);
source = string(sixgr.util.structGet(txInfo, ...
    "PowerNormalizationGridSource", "tx_info.PortGrid"));
if isempty(portGrid)
    portGrid = sixgr.util.structGet(txInfo, "TxContext.PortGrid", []);
    source = "tx_info.TxContext.PortGrid";
end
if isempty(portGrid)
    portGrid = sixgr.util.structGet(txInfo, "ResourceGrid", []);
    source = "tx_info.ResourceGrid";
end
end
end

function [y, info] = localApplyPAContext(x, cfg, ctx, txInfo, applyPA)
y = x;
enabled = logical(sixgr.util.structGet(cfg, "rf.pa.enable", ...
    sixgr.util.structGet(cfg, "phy.impairments.paNonlinearityEnabled", false)));
info = struct( ...
    "PAEnabled", logical(enabled), ...
    "PAApplied", false, ...
    "PAExecutionDeferred", enabled && ~applyPA, ...
    "PAModel", "disabled", ...
    "PABackoff_dB", double(sixgr.util.structGet(cfg, "rf.pa.backoff_dB", ...
        sixgr.util.structGet(cfg, "lls6g.impairments.pa_output_backoff_dB", 0))), ...
    "PAInputTotalPower_mW", NaN, ...
    "PAOutputBeforeRestoration_mW", NaN, ...
    "PAOutputTotalPower_mW", NaN, ...
    "PACompression_dB", NaN, ...
    "PAPowerRestorationScale", 1, ...
    "PAPowerRestorationApplied", false, ...
    "PAAmplitudeUnit", "sqrt_mW", ...
    "PAExecutionStatus", "disabled");
if enabled && ~applyPA
    info.PAModel = "configured_not_executed";
    info.PAExecutionStatus = "deferred_until_transmitter_waveform_composition";
    return;
end
if ~enabled || isempty(x)
    return;
end
[inputTotal_mW, ~] = localTotalActivePower_mW(x, txInfo);
info.PAInputTotalPower_mW = double(inputTotal_mW);
if ~(isfinite(inputTotal_mW) && inputTotal_mW > 0)
    info.PAExecutionStatus = "configured_but_input_power_unavailable";
    return;
end
normScale = sqrt(max(double(inputTotal_mW), realmin));
[runtimeProfile,canonical] = sixgr.rf.runtime.PAProfile.fromConfiguration(cfg);
if canonical
    [yn,paEvidence] = sixgr.rf.runtime.PAProfile.apply( ...
        x ./ cast(normScale, "like", x),runtimeProfile);
    paModel = string(paEvidence.Model);
else
    pa = sixgr.rf.PAModel(cfg);
    paModel = string(sixgr.util.structGet(cfg, "rf.pa.method", "memoryless"));
    yn = pa.apply(x ./ cast(normScale, "like", x));
end
[normOutTotal, ~] = localTotalActivePower_mW(yn, txInfo);
if ~(isfinite(normOutTotal) && normOutTotal > 0)
    info.PAExecutionStatus = "configured_but_output_power_unavailable";
    return;
end
% The configured transmit power defines the PA input reference plane for
% this operation.  Do not renormalize after the nonlinear device: doing so
% erases compression and makes the emitted waveform inconsistent with its
% AM/AM response.  PA output power is measured from the actual samples and
% remains distinct from the configured pre-PA target.
rawY = yn .* cast(normScale, "like", x);
[rawOutputTotal_mW, ~] = localTotalActivePower_mW(rawY, txInfo);
y = rawY;
[outputTotal_mW, ~] = localTotalActivePower_mW(y, txInfo);
info.PAApplied = true;
info.PAModel = paModel;
info.PAOutputBeforeRestoration_mW = double(rawOutputTotal_mW);
info.PAOutputTotalPower_mW = double(outputTotal_mW);
info.PACompression_dB = 10 * log10(max(double(rawOutputTotal_mW), realmin) ./ max(double(inputTotal_mW), realmin));
info.PAPowerRestorationScale = 1;
info.PAPowerRestorationApplied = false;
info.PAExecutionStatus = localPAExecutionStatus(paModel);
if isfield(ctx, "WaveformAmplitudeUnit")
    info.PAAmplitudeUnit = string(ctx.WaveformAmplitudeUnit);
end
end

function status = localPAExecutionStatus(paModel)
token = lower(strtrim(string(paModel)));
if any(token == ["memorypolynomial","memory_polynomial"])
    status = "applied_memory_polynomial_pa_in_physical_sample_units";
elseif contains(token, "soft")
    status = "applied_soft_limiter_pa_in_physical_sample_units";
else
    status = "applied_memoryless_pa_in_physical_sample_units";
end
end
function [total_mW, perPort_mW, info] = localTotalActivePower_mW(x, txInfo)
[total_mW, perPort_mW, info] = ...
    sixgr.rf.measureActiveOFDMTotalPower(x, txInfo);
end

function dbm = localmWToDbm(power_mW)
dbm = NaN(size(power_mW));
mask = isfinite(power_mW) & power_mW > 0;
dbm(mask) = 10 .* log10(double(power_mW(mask)));
end
