function ok=testN40ReceivedMACControl()
% Actual original SRS/control/UL MAC; common/access/DRB/TAG are declared.
[ok,folder,state]=test20MHzSharedSRSPowerBinding([],'mac_chain');
assert(ok&&state.TestMACReceivedChainCompleted);
fprintf('N40_RECEIVED_MAC_COMPONENT_PASS evidence=%s\n',folder);
end
