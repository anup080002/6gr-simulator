function result = runOracleReceiver(rxWaveform,bundle,cfg,trueCFOHz,truePSSTimingSamples)
%RUNORACLERECEIVER Known timing/CFO/association upper bound for IA.
n = (0:size(rxWaveform,1)-1).';
corrected = rxWaveform.*exp(-1j*2*pi*double(trueCFOHz)*n/bundle.SampleRateHz);
symbolLengths = double(bundle.OFDMInfo.SymbolLengths(:));
prefix = sum(symbolLengths(1:double(bundle.CandidateStartSymbol)));
slotStart = round(double(truePSSTimingSamples)-prefix);
if slotStart < 0 || slotStart >= size(corrected,1)
    result = struct("CompleteSSBSuccess",false,"PBCHOk",false, ...
        "FailureReason","oracle_slot_start_outside_capture");
    return;
end
grid = nrOFDMDemodulate(bundle.Carrier,corrected(slotStart+1:end,:));
cols = double(bundle.CandidateStartSymbol)+(1:4);
if size(grid,2) < cols(end)
    result = struct("CompleteSSBSuccess",false,"PBCHOk",false, ...
        "FailureReason","oracle_grid_too_short");
    return;
end
rxSSBGrid = grid(:,cols,:);
sync = struct("NCellID",double(bundle.NCellID), ...
    "NID2",double(bundle.NID2),"NID1",floor(double(bundle.NCellID)/3), ...
    "Lmax",double(cfg.waveform.lmax));
try
    pbch = sixgr.phy.ia.c0.receiver.recoverPBCH( ...
        rxSSBGrid,sync,bundle,cfg);
    result = struct("CompleteSSBSuccess",logical(pbch.Ok), ...
        "PBCHOk",logical(pbch.Ok),"PBCH",pbch, ...
        "FailureReason","","EvidenceClass","oracle_upper_bound");
catch ME
    result = struct("CompleteSSBSuccess",false,"PBCHOk",false, ...
        "FailureReason",string(ME.identifier)+":"+string(ME.message), ...
        "EvidenceClass","oracle_upper_bound");
end
end
