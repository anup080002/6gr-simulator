function [supported, reason] = siRNTIWaveformSupported()
%SIRNTIWAVEFORMSUPPORTED Public R2024a PDCCH APIs reject SI-RNTI 0xFFFF.
%
% AUD-015 requires SI-RNTI = 65535. MATLAB R2024a public nrPDCCH and
% nrPDCCHConfig validators cap RNTI at 65519, and probing nrDCIEncode with
% 65535 has produced native crashes in this environment. Until the repo owns
% a SI-RNTI-capable PDCCH polar/CRC/scrambling wrapper, strict SIB1 must fail
% closed instead of silently substituting another RNTI.

supported = false;
reason = "MATLAB_R2024a_public_PDCCH_validators_reject_SI_RNTI_65535_custom_encoder_required";
end
