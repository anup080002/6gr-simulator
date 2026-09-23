function ok=testPUSCHRelocatedCSIWaveform()
% A PUCCH-configured report keeps its format on an actual PUSCH waveform.
ok=testPUSCHReceivedCSIWaveform(tempname(fullfile(pwd,'logs')),"PUCCH");
end
