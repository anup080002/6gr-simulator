function out = generateMultiUESRSGrid(srsCfg, ueIds)
%GENERATEMULTIUESRSGRID Generate separable per-UE SRS evidence bundles.

ueIds = double(ueIds(:).');
bundles = repmat(struct("UEId", NaN, "ConfigHash", "", "Waveform", [], "GridSlots", []), numel(ueIds), 1);
for ii = 1:numel(ueIds)
    one = sixgr.phy.srs.generateSRSResourceGridForUE(srsCfg, ueIds(ii));
    bundles(ii).UEId = double(ueIds(ii));
    bundles(ii).ConfigHash = string(one.ConfigHash);
    bundles(ii).Waveform = one.Waveform;
    bundles(ii).GridSlots = one.GridSlots;
end
out = struct("UEBundles", bundles, "NumUEs", double(numel(ueIds)), ...
    "ConfigHash", string(srsCfg.ConfigHash), "TruthStatus", "real_lls_evidence");
end
