function evidence=measurePBCHResidualFrequency(rxSSB, sync, pbch)
%MEASUREPBCHRESIDUALFREQUENCY Post-acquisition received DM-RS phase drift.
% No transmitted samples, injected offsets or simulated channel enter this
% measurement. Same-subcarrier pilot pairs remove static frequency-selective
% channel phase. Time-varying channel phase/phase noise remain in the result;
% this is NOT an independently isolated oscillator-CFO measurement.
arguments
    rxSSB = []
    sync = struct()
    pbch = struct()
end
evidence=struct('PBCHResidualCommonFrequency_Hz',NaN, ...
    'PBCHResidualFrequencyAvailable',false, ...
    'PBCHResidualFrequencyStatus',"not_attempted", ...
    'PBCHResidualFrequencySource',"received_PBCH_DMRS_after_PSS_CP_frequency_correction", ...
    'PBCHResidualFrequencyRole',"common_frequency_includes_channel_phase_evolution_not_oscillator_only", ...
    'PBCHResidualFrequencyIndependentCapture',false, ...
    'PBCHResidualFrequencyEvidenceJSON',"");
if isempty(rxSSB), return; end
if ~logical(sixgr.util.structGet(pbch,'Ok',false)) || ...
        double(sixgr.util.structGet(pbch,'ErrFlag',NaN))~=0
    evidence.PBCHResidualFrequencyStatus="unavailable_without_CRC_verified_PBCH_identity";
    return;
end
assert(size(rxSSB,1)==240 && size(rxSSB,2)==4, ...
    'sixgr:phy:broadcast:ResidualFrequencyGrid','PBCH measurement requires the acquired 240-by-4 grid.');
assert(pbch.NCellID==sync.NCellID, ...
    'sixgr:phy:broadcast:ResidualFrequencyIdentity','Use the received cell/DM-RS identity, not another transmission.');
carrier=nrCarrierConfig('NSizeGrid',20,'SubcarrierSpacing',sync.SCS_SSB_kHz, ...
    'NSlot',sync.DemodulationSlot,'NCellID',pbch.NCellID);
[frequency,info]=sixgr.phy.rx.estimateCFOFromReferenceSymbols(rxSSB, ...
    nrPBCHDMRSIndices(pbch.NCellID),nrPBCHDMRS(pbch.NCellID,pbch.iBar_SSB), ...
    carrier,sync.SampleRate_Hz,'Nfft',sync.Nfft, ...
    'SymbolIndicesZeroBased',double(sync.SSBSymbolColumnsOneBased)-1);
evidence.PBCHResidualCommonFrequency_Hz=frequency;
evidence.PBCHResidualFrequencyAvailable=logical(info.EstimateAvailable);
evidence.PBCHResidualFrequencyStatus=string(info.Status);
info.NCellID=double(pbch.NCellID);
info.iBarSSB=double(pbch.iBar_SSB);
info.AcquisitionCorrectionApplied_Hz=double(sync.CFOCorrectionApplied_Hz);
info.IndependentCapture=false;
info.MeasurementRole=evidence.PBCHResidualFrequencyRole;
evidence.PBCHResidualFrequencyEvidenceJSON=string(jsonencode(info));
end
