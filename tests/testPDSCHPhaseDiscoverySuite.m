function tests = testPDSCHPhaseDiscoverySuite
%TESTPDSCHPHASEDISCOVERYSUITE MATLAB unit-test discovery for Prompt-02.
%
% Most repository regressions use the historical logical-returning
% function convention.  This small function-based suite makes the required
% runtests('*PDSCH*') command execute representative production evidence;
% the explicit phase suite still invokes every mandatory logical test.

tests = functiontests(localfunctions);
end

function testProductionEvidenceBuilder(testCase)
verifyTrue(testCase, testPDSCHPhaseEvidenceBuilder());
end

function testStrictTransmitterReceiver(testCase)
verifyTrue(testCase, testPDSCHTransmitterExplicitPipeline());
verifyTrue(testCase, testPDSCHReceiverNoNoiseExact());
verifyTrue(testCase, testPDSCHReceiverAWGN());
verifyTrue(testCase, testPDSCHCompatibilityFacadeDelegation());
verifyTrue(testCase, testPDSCHRank1To8NoNoiseRoundTrip());
end

function testModulationCompleteness(testCase)
verifyTrue(testCase, testPDSCHSoftDemodulationLLRSign());
verifyTrue(testCase, testPDSCH1024QAMRoundTrip());
end

function testStrictProcedureCallers(testCase)
verifyTrue(testCase, testRASIPDSCHStrictOwnership());
verifyTrue(testCase, testDLPDSCHThroughputExecutionContract());
end

function testTransactionalArtifactExporter(testCase)
verifyTrue(testCase, testPDSCHArtifactExporter());
end
