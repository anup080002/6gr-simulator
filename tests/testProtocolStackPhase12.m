function tests = testProtocolStackPhase12
%TESTPROTOCOLSTACKPHASE12 Dedicated Release-18 protocol-stack test plan.
tests = functiontests(localfunctions);
end

function testRLCUMExactHeaders(t), runCase(t,"testRLCUMExactHeaders"); end
function testRLCUMReassembly(t), runCase(t,"testRLCUMReassembly"); end
function testRLCUMWrapAndWindow(t), runCase(t,"testRLCUMWrapAndWindow"); end
function testRLCAMExactHeaders12(t), runCase(t,"testRLCAMExactHeaders12"); end
function testRLCAMExactHeaders18(t), runCase(t,"testRLCAMExactHeaders18"); end
function testRLCAMSegmentation(t), runCase(t,"testRLCAMSegmentation"); end
function testRLCAMResegmentation(t), runCase(t,"testRLCAMResegmentation"); end
function testRLCAMStatusPDU(t), runCase(t,"testRLCAMStatusPDU"); end
function testRLCAMPolling(t), runCase(t,"testRLCAMPolling"); end
function testRLCAMTimers(t), runCase(t,"testRLCAMTimers"); end
function testRLCAMMaxRetx(t), runCase(t,"testRLCAMMaxRetx"); end
function testRLCEntityLifecycle(t), runCase(t,"testRLCEntityLifecycle"); end
function testPDCPExactHeaders(t), runCase(t,"testPDCPExactHeaders"); end
function testPDCPCountHFN(t), runCase(t,"testPDCPCountHFN"); end
function testPDCPReordering(t), runCase(t,"testPDCPReordering"); end
function testPDCPDiscardTimer(t), runCase(t,"testPDCPDiscardTimer"); end
function testPDCPStatusReport(t), runCase(t,"testPDCPStatusReport"); end
function testPDCPDataRecovery(t), runCase(t,"testPDCPDataRecovery"); end
function testPDCPNEA0NIA0(t), runCase(t,"testPDCPNEA0NIA0"); end
function testPDCPNEA2NIA2(t), runCase(t,"testPDCPNEA2NIA2"); end
function testPDCPSecurityActivation(t), runCase(t,"testPDCPSecurityActivation"); end
function testPDCPDuplication(t), runCase(t,"testPDCPDuplication"); end
function testPDCPNegativeMatrix(t), runCase(t,"testPDCPNegativeMatrix"); end
function testSDAPDLHeader(t), runCase(t,"testSDAPDLHeader"); end
function testSDAPULHeader(t), runCase(t,"testSDAPULHeader"); end
function testSDAPEndMarker(t), runCase(t,"testSDAPEndMarker"); end
function testSDAPQFIToDRB(t), runCase(t,"testSDAPQFIToDRB"); end
function testSDAPReflectiveQoS(t), runCase(t,"testSDAPReflectiveQoS"); end
function testSDAPNegativeMatrix(t), runCase(t,"testSDAPNegativeMatrix"); end
function testRRCASN1Setup(t), runCase(t,"testRRCASN1Setup"); end
function testRRCASN1Security(t), runCase(t,"testRRCASN1Security"); end
function testRRCASN1Capability(t), runCase(t,"testRRCASN1Capability"); end
function testRRCASN1Reconfiguration(t), runCase(t,"testRRCASN1Reconfiguration"); end
function testRRCASN1Release(t), runCase(t,"testRRCASN1Release"); end
function testRRCASN1Reestablishment(t), runCase(t,"testRRCASN1Reestablishment"); end
function testRRCASN1Resume(t), runCase(t,"testRRCASN1Resume"); end
function testRRCTransactionIDs(t), runCase(t,"testRRCTransactionIDs"); end
function testRRCTimers(t), runCase(t,"testRRCTimers"); end
function testRRCStateMachine(t), runCase(t,"testRRCStateMachine"); end
function testRadioBearerAtomicCommit(t), runCase(t,"testRadioBearerAtomicCommit"); end
function testRadioBearerRelease(t), runCase(t,"testRadioBearerRelease"); end
function testSecurityModeProcedure(t), runCase(t,"testSecurityModeProcedure"); end
function testHandoverMeasurementReport(t), runCase(t,"testHandoverMeasurementReport"); end
function testHandoverReconfigurationWithSync(t), runCase(t,"testHandoverReconfigurationWithSync"); end
function testHandoverTargetRA(t), runCase(t,"testHandoverTargetRA"); end
function testHandoverRLCHandling(t), runCase(t,"testHandoverRLCHandling"); end
function testHandoverPDCPRecovery(t), runCase(t,"testHandoverPDCPRecovery"); end
function testHandoverT304Failure(t), runCase(t,"testHandoverT304Failure"); end
function testHandoverPacketContinuity(t), runCase(t,"testHandoverPacketContinuity"); end
function testNASBoundary(t), runCase(t,"testNASBoundary"); end
function testTrafficNamedStreams(t), runCase(t,"testTrafficNamedStreams"); end
function testTrafficCBR(t), runCase(t,"testTrafficCBR"); end
function testTrafficPoisson(t), runCase(t,"testTrafficPoisson"); end
function testTrafficBurst(t), runCase(t,"testTrafficBurst"); end
function testTrafficXRPDUSet(t), runCase(t,"testTrafficXRPDUSet"); end
function testTrafficMMTC(t), runCase(t,"testTrafficMMTC"); end
function testTrafficTraceReplay(t), runCase(t,"testTrafficTraceReplay"); end
function testTrafficNegativeProfiles(t), runCase(t,"testTrafficNegativeProfiles"); end
function testProtocolLineage(t), runCase(t,"testProtocolLineage"); end
function testProtocolConservation(t), runCase(t,"testProtocolConservation"); end
function testFirstDeliveryDeduplication(t), runCase(t,"testFirstDeliveryDeduplication"); end
function testMultiBearerIsolation(t), runCase(t,"testMultiBearerIsolation"); end
function testEndToEndConnectedModeNoLoss(t), runCase(t,"testEndToEndConnectedModeNoLoss"); end
function testEndToEndConnectedModeLoss(t), runCase(t,"testEndToEndConnectedModeLoss"); end
function testProtocolArtifactGeneration(t), runCase(t,"testProtocolArtifactGeneration"); end
function testProtocolImpactAnalysis(t), runCase(t,"testProtocolImpactAnalysis"); end
function testProtocolReproducibility(t), runCase(t,"testProtocolReproducibility"); end

function runCase(testCase,name)
root = string(fullfile(fileparts(mfilename("fullpath")),"vectors","protocol"));
sixgr.protocol.ProtocolSelfTest.runOne(name,root);
verifyTrue(testCase,true);
end
