function [y, ctx] = applyPowerContext(x, cfg, direction, txInfo, varargin)
%APPLYPOWERCONTEXT Scale waveform samples to entity-specific Tx power.
%
% Output samples use the PowerContext convention: abs(sample)^2 is mW
% and mean(sum(abs(x_active).^2, ports)) equals total transmit power.

if nargin < 4
    txInfo = struct();
end
ip = inputParser;
ip.addParameter("PowerContext", struct(), @(v) isempty(v) || isstruct(v));
ip.parse(varargin{:});
ctx = ip.Results.PowerContext;
if ~(isstruct(ctx) && isfield(ctx, "ContractVersion"))
    ctx = sixgr.rf.PowerContext(cfg, direction, "NumPorts", size(x, 2));
end

[inputTotal_mW, inputPerPort_mW, refInfo] = localTotalActivePower_mW(x, txInfo);
scale = 1;
if isfinite(inputTotal_mW) && inputTotal_mW > 0 && ...
        isfinite(double(ctx.TotalTxPower_mW)) && double(ctx.TotalTxPower_mW) >= 0
    scale = sqrt(double(ctx.TotalTxPower_mW) / max(inputTotal_mW, realmin));
end
y = x .* cast(scale, "like", x);
[y, paInfo] = localApplyPAContext(y, cfg, ctx, txInfo);
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
ctx.PowerClosureError_dB = double(ctx.OutputTotalPower_dBm) - double(ctx.TotalTxPower_dBm);
ctx.PerPortPowerSum_mW = sum(double(outputPerPort_mW), "omitnan");
ctx.PerPortPowerSumError_mW = double(ctx.PerPortPowerSum_mW) - double(ctx.TotalTxPower_mW);
ctx.ConversionEquation = "x_scaled=x*sqrt(Ptx_mW/mean_sum_abs2_active_samples)";
paFields = fieldnames(paInfo);
for paIdx = 1:numel(paFields)
    ctx.(paFields{paIdx}) = paInfo.(paFields{paIdx});
end
end

function [y, info] = localApplyPAContext(x, cfg, ctx, txInfo)
y = x;
enabled = logical(sixgr.util.structGet(cfg, "rf.pa.enable", ...
    sixgr.util.structGet(cfg, "phy.impairments.paNonlinearityEnabled", false)));
info = struct( ...
    "PAEnabled", logical(enabled), ...
    "PAApplied", false, ...
    "PAModel", "disabled", ...
    "PABackoff_dB", double(sixgr.util.structGet(cfg, "rf.pa.backoff_dB", ...
        sixgr.util.structGet(cfg, "lls6g.impairments.pa_output_backoff_dB", 0))), ...
    "PAInputTotalPower_mW", NaN, ...
    "PAOutputTotalPower_mW", NaN, ...
    "PACompression_dB", NaN, ...
    "PAAmplitudeUnit", "sqrt_mW", ...
    "PAExecutionStatus", "disabled");
if ~enabled || isempty(x)
    return;
end
[inputTotal_mW, ~] = localTotalActivePower_mW(x, txInfo);
info.PAInputTotalPower_mW = double(inputTotal_mW);
if ~(isfinite(inputTotal_mW) && inputTotal_mW > 0)
    info.PAExecutionStatus = "configured_but_input_power_unavailable";
    return;
end
pa = sixgr.rf.PAModel(cfg);
normScale = sqrt(max(double(inputTotal_mW), realmin));
yn = pa.apply(x ./ cast(normScale, "like", x));
[normOutTotal, ~] = localTotalActivePower_mW(yn, txInfo);
if ~(isfinite(normOutTotal) && normOutTotal > 0)
    info.PAExecutionStatus = "configured_but_output_power_unavailable";
    return;
end
restoreScale = sqrt(max(double(inputTotal_mW), realmin) ./ max(double(normOutTotal), realmin));
y = yn .* cast(restoreScale, "like", x);
[outputTotal_mW, ~] = localTotalActivePower_mW(y, txInfo);
info.PAApplied = true;
info.PAModel = string(sixgr.util.structGet(cfg, "rf.pa.method", "memoryless"));
info.PAOutputTotalPower_mW = double(outputTotal_mW);
info.PACompression_dB = 10 * log10(max(double(outputTotal_mW), realmin) ./ max(double(inputTotal_mW), realmin));
info.PAExecutionStatus = "applied_memoryless_pa_in_physical_sample_units";
if isfield(ctx, "WaveformAmplitudeUnit")
    info.PAAmplitudeUnit = string(ctx.WaveformAmplitudeUnit);
end
end
function [total_mW, perPort_mW, info] = localTotalActivePower_mW(x, txInfo)
if isempty(x)
    total_mW = NaN;
    perPort_mW = zeros(1, 0);
    info = struct("ReferenceDomain", "empty", "SampleCount", 0);
    return;
end
idx = localUsefulSampleIndices(size(x, 1), sixgr.util.structGet(txInfo, "OFDM", struct()));
if isempty(idx)
    xRef = x;
    info = struct("ReferenceDomain", "all_waveform_samples_metadata_unavailable", ...
        "SampleCount", double(numel(x)));
else
    xRef = x(idx, :);
    info = struct("ReferenceDomain", "active_samples_excluding_cp", ...
        "SampleCount", double(numel(xRef)));
end
perPort_mW = mean(abs(double(xRef)).^2, 1, "omitnan");
total_mW = sum(perPort_mW, "omitnan");
end

function idx = localUsefulSampleIndices(nSamples, ofdmInfo)
idx = [];
if nargin < 2 || ~isstruct(ofdmInfo)
    return;
end
nfft = round(double(sixgr.util.structGet(ofdmInfo, "Nfft", NaN)));
cpLens = round(double(sixgr.util.structGet(ofdmInfo, "CyclicPrefixLengths", [])));
if ~(isfinite(nfft) && nfft > 0 && ~isempty(cpLens))
    return;
end
offset = 0;
while offset < nSamples
    for s = 1:numel(cpLens)
        cp = max(0, cpLens(s));
        useful = offset + cp + (1:nfft);
        useful = useful(useful <= nSamples);
        idx = [idx, useful]; %#ok<AGROW>
        offset = offset + cp + nfft;
        if offset >= nSamples
            break;
        end
    end
end
idx = idx(:);
end

function dbm = localmWToDbm(power_mW)
dbm = NaN(size(power_mW));
mask = isfinite(power_mW) & power_mW > 0;
dbm(mask) = 10 .* log10(double(power_mW(mask)));
end
