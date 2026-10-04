function ok=testRAN1AI1032Alt3ConnectedPUSCH()
% Received six-bit H0 DCI through coded PUSCH/UCI and independent gNB RX.
% Focused waveform/HARQ case, not statistical calibration.
ok=testConnectedResearchPUSCH(25,"experimental_6gr_ai1032_alt3",32,2);
end
