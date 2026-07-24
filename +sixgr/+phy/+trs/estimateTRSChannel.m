function ch = estimateTRSChannel(rx, cfg, tx, det)
%ESTIMATETRSCHANNEL Estimate channel from received TRS REs using nrChannelEstimate.

slotDet = det.SlotDetections;
resources = localResolveSlotResources(cfg, tx);
rows = repmat(localChannelRow(), numel(slotDet), 1);
for ii = 1:numel(slotDet)
    attempted = true;
    available = false;
    nmseDb = NaN;
    noiseEst = NaN;
    status = "channel_estimate_unavailable";
    try
        rxGrid = slotDet(ii).RxGrid;
        if isempty(rxGrid)
            rxGrid = sixgr.phy.waveform.ofdmDemodulate( ...
                resources(ii).Carrier, slotDet(ii).CorrectedWaveform);
        end
        [hest, noiseEst] = nrChannelEstimate(resources(ii).Carrier, rxGrid, ...
            resources(ii).Indices, resources(ii).Symbols);
        rxRE = slotDet(ii).RxRE(:);
        if isempty(rxRE)
            rxRE = rxGrid(resources(ii).Indices);
        end
        ref = resources(ii).Symbols(:);
        hPilot = hest(resources(ii).Indices);
        n = min([numel(rxRE), numel(ref), numel(hPilot)]);
        rxRE = rxRE(1:n);
        ref = ref(1:n);
        hPilot = hPilot(1:n);
        mask = isfinite(real(rxRE)) & isfinite(imag(rxRE)) & ...
            isfinite(real(ref)) & isfinite(imag(ref)) & ...
            isfinite(real(hPilot)) & isfinite(imag(hPilot));
        if ~any(mask)
            nmse = NaN;
        else
            rxRE = rxRE(mask);
            ref = ref(mask);
            hPilot = hPilot(mask);
            residual = rxRE(:) - hPilot(:) .* ref(:);
            nmse = mean(abs(residual).^2, "omitnan") ./ max(mean(abs(rxRE(:)).^2, "omitnan"), eps);
        end
        nmseDb = 10 * log10(max(nmse, eps));
        available = isfinite(nmseDb) && logical(slotDet(ii).Detected);
        status = "channel_estimate_available_pilot_reconstruction_nmse";
    catch ME
        status = "channel_estimate_failed:" + string(ME.identifier);
    end
    row = localChannelRow();
    row.RunId = string(cfg.RunId);
    row.ConfigHash = string(cfg.ConfigHash);
    row.Slot = double(slotDet(ii).Slot);
    row.ChannelEstimationAttempted = logical(attempted);
    row.TRSChannelEstimateAvailable = logical(available);
    row.NMSE_dB = double(nmseDb);
    row.NoiseEstimate = double(noiseEst);
    row.ChannelNMSEThreshold_dB = double(cfg.ChannelNMSEThresholddB);
    row.ChannelEstimator = "nrChannelEstimate_pilot_reconstruction_nmse";
    row.Status = string(status);
    row.TruthStatus = "real_lls_evidence";
    rows(ii) = row;
end

function resources = localResolveSlotResources(cfg, tx)
if isfield(tx, "SlotResources") && isfield(tx, "Config") && ...
        isfield(tx.Config, "ConfigHash") && string(tx.Config.ConfigHash) == string(cfg.ConfigHash)
    resources = tx.SlotResources;
else
    resources = sixgr.phy.trs.generateTRSSymbolsAndIndices(cfg).SlotResources;
end
end
ch = struct();
ch.Table = struct2table(rows, "AsArray", true);
ch.Attempted = any([rows.ChannelEstimationAttempted]);
ch.EstimateAvailable = all([rows.TRSChannelEstimateAvailable]);
ch.MeanNMSE_dB = mean([rows.NMSE_dB], "omitnan");
end

function row = localChannelRow()
row = struct("RunId", "", "ConfigHash", "", "Slot", NaN, ...
    "ChannelEstimationAttempted", false, "TRSChannelEstimateAvailable", false, ...
    "NMSE_dB", NaN, "NoiseEstimate", NaN, "ChannelNMSEThreshold_dB", NaN, ...
    "ChannelEstimator", "nrChannelEstimate_pilot_reconstruction_nmse", ...
    "Status", "", "TruthStatus", "");
end
