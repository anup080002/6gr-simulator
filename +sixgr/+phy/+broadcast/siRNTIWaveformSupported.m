function [supported, reason] = siRNTIWaveformSupported()
%SIRNTIWAVEFORMSUPPORTED Verify SI-RNTI DCI over Type0 common PDCCH.
%
% SI-RNTI is used as the DCI CRC mask. The Type0 common-search-space PDCCH
% physical scrambling uses nRNTI=0 with NCellID as nID; passing 65535 as the
% nrPDCCH/nrPDCCHDecode scrambling RNTI is both semantically wrong and can
% crash MATLAB R2024a native code. This probe checks the exact safe chain
% used by the SIB1 waveform Tx/Rx helpers.

persistent cachedSupported cachedReason
if ~isempty(cachedSupported)
    supported = cachedSupported;
    reason = cachedReason;
    return;
end

required = ["nrDCIEncode","nrDCIDecode","nrPDCCH","nrPDCCHDecode"];
missing = strings(0, 1);
for i = 1:numel(required)
    if exist(required(i), "file") ~= 2
        missing(end+1, 1) = required(i); %#ok<AGROW>
    end
end
if ~isempty(missing)
    cachedSupported = false;
    cachedReason = "missing_5g_toolbox_functions:" + strjoin(missing, ",");
    supported = cachedSupported;
    reason = cachedReason;
    return;
end

try
    k = 32;
    e = 288;
    siRNTI = 65535;
    nCellID = 17;
    bits = int8(mod((0:k-1).', 2));
    dciCW = nrDCIEncode(bits, siRNTI, e);
    pdcchSymbols = nrPDCCH(dciCW, nCellID, 0);
    rxCW = nrPDCCHDecode(pdcchSymbols, nCellID, 0, 1e-6);
    [decodedBits, mask] = nrDCIDecode(rxCW, k, 8, siRNTI);
    cachedSupported = isequal(int8(decodedBits(:)), bits(:)) && double(mask) == 0;
    if cachedSupported
        cachedReason = "si_rnti_crc_mask_with_type0_css_pdcch_scrambling_rnti_0_supported";
    else
        cachedReason = "si_rnti_type0_css_probe_failed_crc_or_payload_mismatch";
    end
catch ME
    cachedSupported = false;
    cachedReason = "si_rnti_type0_css_probe_error:" + string(ME.identifier) + ":" + string(ME.message);
end

supported = cachedSupported;
reason = cachedReason;
end
