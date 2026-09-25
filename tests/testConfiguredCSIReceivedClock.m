function ok=testConfiguredCSIReceivedClock()
% Actual shared SRS and independently scheduled PUCCH, not injected timing.
for mode=["present","remove_after_tx","absent"]
    assert(testSharedPeriodicCSIProducer(mode,true));
end
fprintf('CONFIGURED_CSI_RECEIVED_CLOCK_PASS producer_modes=3 injected_timing=0\n');
ok=true;
end
