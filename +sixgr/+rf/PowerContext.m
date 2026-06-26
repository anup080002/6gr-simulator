function ctx = PowerContext(cfg, direction, varargin)
%POWERCONTEXT Resolve entity-specific RF power and amplitude units.
%
% The simulator convention is:
%   mean(sum(abs(x_active).^2, ports)) == total power in mW
% over useful OFDM samples. Complex sample amplitude is therefore sqrt(mW).

if nargin < 1 || ~isstruct(cfg)
    cfg = struct();
end
if nargin < 2
    direction = "DL";
end

ip = inputParser;
ip.addParameter("NumPorts", NaN, @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter("State", "active_tx", @(x) ischar(x) || isstring(x));
ip.parse(varargin{:});
opt = ip.Results;

direction = upper(strtrim(string(direction)));
if direction ~= "UL"
    direction = "DL";
end

if direction == "UL"
    txEntity = "UE";
    rxEntity = "gNB";
else
    txEntity = "gNB";
    rxEntity = "UE";
end

[txPower_dBm, txPowerSource] = localResolveTxPower(cfg, direction);
[txGain_dB, txGainSource] = localResolveGain(cfg, direction, "tx");
[rxGain_dB, rxGainSource] = localResolveGain(cfg, direction, "rx");
[extraLoss_dB, extraLossSource] = localResolveExtraLoss(cfg, direction);
[noiseFigure_dB, noiseFigureSource] = localResolveNoiseFigure(cfg, direction);
[paEfficiency, paEfficiencySource] = localResolvePAEfficiency(cfg, txEntity);
[rfChains, rfChainSource] = localResolveRFChains(cfg, txEntity, direction, opt.NumPorts);

txPower_mW = 10 .^ (double(txPower_dBm) / 10);
txPower_W = txPower_mW * 1e-3;
r0 = localFirstFinite( ...
    sixgr.util.structGet(cfg, "powerAndRF.referenceImpedance_Ohm", []), ...
    sixgr.util.structGet(cfg, "rf.referenceImpedance_Ohm", []), ...
    50);
r0 = max(double(r0), eps);

ctx = struct();
ctx.ContractVersion = "sixgr.rf.PowerContext/v1";
ctx.Direction = char(direction);
ctx.TxEntity = char(txEntity);
ctx.RxEntity = char(rxEntity);
ctx.State = char(string(opt.State));
ctx.ReferenceImpedance_Ohm = double(r0);
ctx.WaveformAmplitudeUnit = "sqrt_mW";
ctx.SamplePowerConvention = "mean_sum_abs2_over_active_ofdm_samples_equals_total_mW";
ctx.TotalTxPower_dBm = double(txPower_dBm);
ctx.TotalTxPower_mW = double(txPower_mW);
ctx.TotalTxPower_W = double(txPower_W);
ctx.TotalTxPowerSource = char(txPowerSource);
ctx.TxGain_dB = double(txGain_dB);
ctx.TxGainSource = char(txGainSource);
ctx.RxGain_dB = double(rxGain_dB);
ctx.RxGainSource = char(rxGainSource);
ctx.AdditionalLoss_dB = double(extraLoss_dB);
ctx.AdditionalLossSource = char(extraLossSource);
ctx.NoiseFigure_dB = double(noiseFigure_dB);
ctx.NoiseFigureSource = char(noiseFigureSource);
ctx.PAEfficiency = double(paEfficiency);
ctx.PAEfficiencySource = char(paEfficiencySource);
ctx.RFChainCount = double(rfChains);
ctx.RFChainCountSource = char(rfChainSource);
ctx.NumPorts = double(localPositiveInteger(opt.NumPorts, max(1, rfChains)));
ctx.TargetPerPortPower_mW = double(txPower_mW) / max(1, ctx.NumPorts);
ctx.TargetPerPortPower_dBm = 10 * log10(max(ctx.TargetPerPortPower_mW, realmin));
ctx.TotalTxRMSVoltage_V = sqrt(double(txPower_W) * r0);
ctx.Equation = "P_rx_dBm=P_tx_dBm+G_tx_dB+G_rx_dB-Pathloss_dB-AdditionalLoss_dB";
ctx.ScaleApplied = false;
ctx.AmplitudeScale = 1;
ctx.InputTotalPower_mW = NaN;
ctx.OutputTotalPower_mW = NaN;
ctx.OutputTotalPower_dBm = NaN;
ctx.OutputPerPortPower_mW = [];
ctx.OutputPerPortPower_dBm = [];
ctx.ActivePortCount = NaN;
end

function [txPower_dBm, source] = localResolveTxPower(cfg, direction)
resolved = sixgr.util.structGet(cfg, "lls6g.resolvedConfig", struct());
if direction == "UL"
    [txPower_dBm, source] = localFirstFiniteWithSource( ...
        sixgr.util.structGet(resolved, "power_and_rf_frontend.ue_tx_power_dbm", []), "resolved_config.power_and_rf_frontend.ue_tx_power_dbm", ...
        sixgr.util.structGet(cfg, "powerAndRF.ueTxPower_dBm", []), "cfg.powerAndRF.ueTxPower_dBm", ...
        sixgr.util.structGet(cfg, "phy.pusch.powerControl.pcmax_dBm", []), "cfg.phy.pusch.powerControl.pcmax_dBm", ...
        sixgr.util.structGet(cfg, "power_control.ue_max_power_dBm", []), "cfg.power_control.ue_max_power_dBm", ...
        23, "default_ue_23_dBm");
else
    [txPower_dBm, source] = localFirstFiniteWithSource( ...
        sixgr.util.structGet(resolved, "power_and_rf_frontend.bs_tx_power_dbm", []), "resolved_config.power_and_rf_frontend.bs_tx_power_dbm", ...
        sixgr.util.structGet(cfg, "powerAndRF.bsTxPower_dBm", []), "cfg.powerAndRF.bsTxPower_dBm", ...
        sixgr.util.structGet(cfg, "scenario.bs.txPower_dBm", []), "cfg.scenario.bs.txPower_dBm", ...
        sixgr.util.structGet(cfg, "lls6g.energy_efficiency.bs_tx_power_dbm", []), "cfg.lls6g.energy_efficiency.bs_tx_power_dbm", ...
        sixgr.util.structGet(cfg, "lls6g.energy_efficiency.tx_power_dbm", []), "cfg.lls6g.energy_efficiency.tx_power_dbm", ...
        46, "default_gnb_46_dBm");
end
end

function [gain_dB, source] = localResolveGain(cfg, direction, endpoint)
endpoint = lower(strtrim(string(endpoint)));
if direction == "UL"
    if endpoint == "tx"
        [gain_dB, source] = localFirstFiniteWithSource( ...
            sixgr.util.structGet(cfg, "scenario.ue.txGain_dBi", []), "cfg.scenario.ue.txGain_dBi", ...
            sixgr.util.structGet(cfg, "powerAndRF.ueTxGain_dB", []), "cfg.powerAndRF.ueTxGain_dB", ...
            0, "default_0_dB");
    else
        [gain_dB, source] = localFirstFiniteWithSource( ...
            sixgr.util.structGet(cfg, "scenario.bs.rxGain_dBi", []), "cfg.scenario.bs.rxGain_dBi", ...
            sixgr.util.structGet(cfg, "powerAndRF.bsRxGain_dB", []), "cfg.powerAndRF.bsRxGain_dB", ...
            0, "default_0_dB");
    end
else
    if endpoint == "tx"
        [gain_dB, source] = localFirstFiniteWithSource( ...
            sixgr.util.structGet(cfg, "scenario.bs.txGain_dBi", []), "cfg.scenario.bs.txGain_dBi", ...
            sixgr.util.structGet(cfg, "powerAndRF.bsTxGain_dB", []), "cfg.powerAndRF.bsTxGain_dB", ...
            0, "default_0_dB");
    else
        [gain_dB, source] = localFirstFiniteWithSource( ...
            sixgr.util.structGet(cfg, "scenario.ue.rxGain_dBi", []), "cfg.scenario.ue.rxGain_dBi", ...
            sixgr.util.structGet(cfg, "powerAndRF.ueRxGain_dB", []), "cfg.powerAndRF.ueRxGain_dB", ...
            0, "default_0_dB");
    end
end
end

function [loss_dB, source] = localResolveExtraLoss(cfg, direction)
if direction == "UL"
    [loss_dB, source] = localFirstFiniteWithSource( ...
        sixgr.util.structGet(cfg, "powerAndRF.ulImplementationLoss_dB", []), "cfg.powerAndRF.ulImplementationLoss_dB", ...
        sixgr.util.structGet(cfg, "channel.ul.additionalLoss_dB", []), "cfg.channel.ul.additionalLoss_dB", ...
        0, "default_0_dB");
else
    [loss_dB, source] = localFirstFiniteWithSource( ...
        sixgr.util.structGet(cfg, "powerAndRF.dlImplementationLoss_dB", []), "cfg.powerAndRF.dlImplementationLoss_dB", ...
        sixgr.util.structGet(cfg, "channel.dl.additionalLoss_dB", []), "cfg.channel.dl.additionalLoss_dB", ...
        0, "default_0_dB");
end
end

function [nf_dB, source] = localResolveNoiseFigure(cfg, direction)
resolved = sixgr.util.structGet(cfg, "lls6g.resolvedConfig", struct());
if direction == "UL"
    [nf_dB, source] = localFirstFiniteWithSource( ...
        sixgr.util.structGet(resolved, "power_and_rf_frontend.bs_noise_figure_db", []), "resolved_config.power_and_rf_frontend.bs_noise_figure_db", ...
        sixgr.util.structGet(cfg, "scenario.bs.noiseFigure_dB", []), "cfg.scenario.bs.noiseFigure_dB", ...
        sixgr.util.structGet(cfg, "powerAndRF.bsNoiseFigure_dB", []), "cfg.powerAndRF.bsNoiseFigure_dB", ...
        sixgr.util.structGet(cfg, "channel.bsReceiverNoiseFigure_dB", []), "cfg.channel.bsReceiverNoiseFigure_dB", ...
        sixgr.util.structGet(cfg, "channel.receiverNoiseFigure_dB", []), "cfg.channel.receiverNoiseFigure_dB", ...
        5, "default_bs_5_dB");
else
    [nf_dB, source] = localFirstFiniteWithSource( ...
        sixgr.util.structGet(resolved, "power_and_rf_frontend.ue_noise_figure_db", []), "resolved_config.power_and_rf_frontend.ue_noise_figure_db", ...
        sixgr.util.structGet(cfg, "scenario.ue.noiseFigure_dB", []), "cfg.scenario.ue.noiseFigure_dB", ...
        sixgr.util.structGet(cfg, "powerAndRF.ueNoiseFigure_dB", []), "cfg.powerAndRF.ueNoiseFigure_dB", ...
        sixgr.util.structGet(cfg, "channel.ueReceiverNoiseFigure_dB", []), "cfg.channel.ueReceiverNoiseFigure_dB", ...
        sixgr.util.structGet(cfg, "channel.receiverNoiseFigure_dB", []), "cfg.channel.receiverNoiseFigure_dB", ...
        9, "default_ue_9_dB");
end
end

function [eta, source] = localResolvePAEfficiency(cfg, entity)
entity = upper(string(entity));
if entity == "UE"
    [eta, source] = localFirstFiniteWithSource( ...
        sixgr.util.structGet(cfg, "energy.ue.efficiencyPA", []), "cfg.energy.ue.efficiencyPA", ...
        sixgr.util.structGet(cfg, "powerAndRF.uePAEfficiency", []), "cfg.powerAndRF.uePAEfficiency", ...
        sixgr.util.structGet(cfg, "lls6g.energy_efficiency.pa_efficiency", []), "cfg.lls6g.energy_efficiency.pa_efficiency", ...
        0.35, "default_0p35");
else
    [eta, source] = localFirstFiniteWithSource( ...
        sixgr.util.structGet(cfg, "energy.bs.efficiencyPA", []), "cfg.energy.bs.efficiencyPA", ...
        sixgr.util.structGet(cfg, "powerAndRF.bsPAEfficiency", []), "cfg.powerAndRF.bsPAEfficiency", ...
        sixgr.util.structGet(cfg, "lls6g.energy_efficiency.pa_efficiency", []), "cfg.lls6g.energy_efficiency.pa_efficiency", ...
        0.35, "default_0p35");
end
eta = min(max(double(eta), 1e-3), 1);
end

function [n, source] = localResolveRFChains(cfg, entity, direction, fallbackPorts)
entity = upper(string(entity));
if entity == "UE"
    [n, source] = localFirstFiniteWithSource( ...
        sixgr.util.structGet(cfg, "powerAndRF.ueRFChainCount", []), "cfg.powerAndRF.ueRFChainCount", ...
        sixgr.util.structGet(cfg, "rf.ue.numRFChains", []), "cfg.rf.ue.numRFChains", ...
        sixgr.util.structGet(cfg, "scenario.ue.numRFChains", []), "cfg.scenario.ue.numRFChains", ...
        sixgr.util.structGet(cfg, "scenario.ue.nTxAnt", []), "cfg.scenario.ue.nTxAnt", ...
        fallbackPorts, "waveform_ports");
else
    if direction == "UL"
        [n, source] = localFirstFiniteWithSource( ...
            sixgr.util.structGet(cfg, "powerAndRF.bsRxRFChainCount", []), "cfg.powerAndRF.bsRxRFChainCount", ...
            sixgr.util.structGet(cfg, "rf.bs.numRFChains", []), "cfg.rf.bs.numRFChains", ...
            sixgr.util.structGet(cfg, "scenario.bs.numRFChains", []), "cfg.scenario.bs.numRFChains", ...
            sixgr.util.structGet(cfg, "scenario.bs.nRxAnt", []), "cfg.scenario.bs.nRxAnt", ...
            sixgr.util.structGet(cfg, "scenario.bs.nTxAnt", []), "cfg.scenario.bs.nTxAnt", ...
            fallbackPorts, "waveform_ports");
    else
        [n, source] = localFirstFiniteWithSource( ...
            sixgr.util.structGet(cfg, "powerAndRF.bsRFChainCount", []), "cfg.powerAndRF.bsRFChainCount", ...
            sixgr.util.structGet(cfg, "rf.bs.numRFChains", []), "cfg.rf.bs.numRFChains", ...
            sixgr.util.structGet(cfg, "scenario.bs.numRFChains", []), "cfg.scenario.bs.numRFChains", ...
            sixgr.util.structGet(cfg, "lls6g.energy_efficiency.rf_chain_count", []), "cfg.lls6g.energy_efficiency.rf_chain_count", ...
            sixgr.util.structGet(cfg, "phy.nTxAnt", []), "cfg.phy.nTxAnt", ...
            fallbackPorts, "waveform_ports");
    end
end
if ~(isfinite(double(n)) && double(n) >= 1)
    n = 1;
else
    n = max(1, round(double(n)));
end
end

function [value, source] = localFirstFiniteWithSource(varargin)
value = NaN;
source = "unavailable";
for i = 1:2:nargin
    raw = varargin{i};
    candidateSource = string(varargin{i + 1});
    if isempty(raw)
        continue;
    end
    if islogical(raw)
        raw = double(raw);
    end
    if ~isnumeric(raw)
        numeric = str2double(string(raw));
    else
        numeric = double(raw);
    end
    numeric = numeric(:);
    numeric = numeric(isfinite(numeric));
    if ~isempty(numeric)
        value = numeric(1);
        source = candidateSource;
        return;
    end
end
end

function value = localFirstFinite(varargin)
value = NaN;
for i = 1:nargin
    raw = double(varargin{i});
    raw = raw(:);
    raw = raw(isfinite(raw));
    if ~isempty(raw)
        value = raw(1);
        return;
    end
end
end

function value = localPositiveInteger(raw, defaultValue)
value = defaultValue;
if isempty(raw)
    if ~(isfinite(double(value)) && double(value) >= 1)
        value = 1;
    else
        value = max(1, round(double(value)));
    end
    return;
end
raw = double(raw);
if isscalar(raw) && isfinite(raw) && raw >= 1
    value = round(raw);
elseif isfinite(double(defaultValue)) && double(defaultValue) >= 1
    value = max(1, round(double(defaultValue)));
else
    value = 1;
end
end
