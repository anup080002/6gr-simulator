function ok=testPacketHARQLatePDCPDiscard()
% Actual coded PDSCHs with explicitly arranged receiver callback order.
% Verifies production discard/reporting; not shared RF timing qualification.
ok=testPacketHARQFirstSuccessEvidence('OutOfOrder',true,'LateAfterReordering',true);
end
