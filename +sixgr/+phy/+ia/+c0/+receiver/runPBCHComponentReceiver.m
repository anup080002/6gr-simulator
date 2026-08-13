function result = runPBCHComponentReceiver(rxWaveform,bundle,cfg, ...
        practicalCFOEstimateHz,truePSSTimingSamples)
%RUNPBCHCOMPONENTRECEIVER Isolate PBCH without perfect CE or perfect CFO.
% The component receiver is given the transmitted PCI and occurrence, but
% it reuses the practical receiver's CFO estimate and dedicated PBCH-DMRS
% channel estimator.  Every channel realization therefore contributes to
% PBCH-A independently of practical PSS/SSS success.
result = struct("Attempted",true,"Ok",false,"PBCH",struct(), ...
    "RxSSBGrid",complex(zeros(0,0,0)),"ResidualCFOHz",NaN, ...
    "FailureReason","","EvidenceClass","pbch_component_waveform_truth");
if ~(isscalar(practicalCFOEstimateHz) && isfinite(practicalCFOEstimateHz))
    result.FailureReason = "practical_cfo_estimate_unavailable";
    return;
end
try
    corrected = localFrequencyCorrect(rxWaveform,bundle.SampleRateHz, ...
        practicalCFOEstimateHz);
    symbolLengths = double(bundle.OFDMInfo.SymbolLengths(:));
    prefix = sum(symbolLengths(1:double(bundle.CandidateStartSymbol)));
    slotStart = round(double(truePSSTimingSamples)-prefix);
    if slotStart < 0 || slotStart >= size(corrected,1)
        result.FailureReason = "component_slot_start_outside_capture";
        return;
    end
    grid = nrOFDMDemodulate(bundle.Carrier,corrected(slotStart+1:end,:));
    columns = double(bundle.CandidateStartSymbol)+(1:4);
    if size(grid,2) < columns(end)
        result.FailureReason = "component_grid_too_short";
        return;
    end
    rxSSBGrid = grid(:,columns,:);
    sync = struct("NCellID",double(bundle.NCellID), ...
        "NID2",double(bundle.NID2), ...
        "NID1",floor(double(bundle.NCellID)/3), ...
        "Lmax",double(cfg.waveform.lmax));
    pbch = sixgr.phy.ia.c0.receiver.recoverPBCH( ...
        rxSSBGrid,sync,bundle,cfg);
    result.Ok = logical(pbch.Ok);
    result.PBCH = pbch;
    result.RxSSBGrid = rxSSBGrid;
    if ~result.Ok
        result.FailureReason = "component_pbch_crc_or_payload_mismatch";
    end
catch ME
    result.FailureReason = string(ME.identifier)+":"+string(ME.message);
end
end

function y = localFrequencyCorrect(x,fs,estimateHz)
n = (0:size(x,1)-1).';
y = x.*exp(-1j*2*pi*double(estimateHz)*n/double(fs));
end
