function tests = testUCIPUSCHPhaseCore
%TESTUCIPUSCHPHASECORE Focused typed UCI-on-PUSCH regressions.
tests = functiontests(localfunctions);
end

function setupOnce(~)
repoRoot = fileparts(fileparts(mfilename("fullpath")));
addpath(repoRoot);
setup6GRSimToolkit("Verbose", false);
end

function testTypedACKCSIAndConfiguredGrantUCIRoundTrip(testCase)
pusch = nrPUSCHConfig;
pusch.PRBSet = 0:23;
pusch.SymbolAllocation = [0 14];
pusch.Modulation = "QPSK";
pusch.NumLayers = 1;
pusch.TransformPrecoding = false;
pusch.BetaOffsetACK = 1;
pusch.BetaOffsetCSI1 = 1.25;
pusch.BetaOffsetCSI2 = 1.25;
pusch.UCIScaling = 1;
payload = sixgr.phy.ul.pusch.PUSCHUCIPayload( ...
    "HARQACK", [1;0], ...
    "CSIPart1", [1;0;1;1], ...
    "CSIPart2", [0;1;1;0;1;0], ...
    "ConfiguredGrantUCI", [1;1]);
targetCodeRate = 0.30;
transportBlockSize = 512;
initialIMCS = 10;
budget = nrULSCHInfo(pusch, targetCodeRate, ...
    transportBlockSize, 2, 4, 8);
ulschBits = int8(mod((0:double(budget.GULSCH)-1).', 2));

mux = sixgr.phy.ul.pusch.PUSCHUCIMultiplexer.multiplex( ...
    pusch, targetCodeRate, transportBlockSize, ...
    ulschBits, payload, initialIMCS);
hardLLR = (1 - 2 * double(mux.Codewords{1})) * 50;
demux = sixgr.phy.ul.pusch.PUSCHUCIDemultiplexer.demultiplex( ...
    pusch, targetCodeRate, transportBlockSize, ...
    hardLLR, payload, initialIMCS);

verifyEqual(testCase, mux.OwnerCodeword, 0);
verifyEqual(testCase, numel(mux.Codewords{1}), ...
    mux.GPerCodeword);
verifyEqual(testCase, numel(mux.ACKCodedBits), ...
    double(budget.GACK));
verifyEqual(testCase, numel(mux.CSI1CodedBits), ...
    double(budget.GCSI1));
verifyEqual(testCase, numel(mux.CSI2AndCGUCICodedBits), ...
    double(budget.GCSI2));
verifyTrue(testCase, demux.HARQACKCRCOK);
verifyTrue(testCase, demux.CSI1CRCOK);
verifyTrue(testCase, demux.CSI2CRCOK);
verifyTrue(testCase, demux.ConfiguredGrantUCIMatch);
verifyEqual(testCase, demux.DecodedHARQACK, payload.HARQACK);
verifyEqual(testCase, demux.DecodedCSIPart1, payload.CSIPart1);
verifyEqual(testCase, demux.DecodedCSIPart2, payload.CSIPart2);
verifyEqual(testCase, demux.DecodedConfiguredGrantUCI, ...
    payload.ConfiguredGrantUCI);
end

function testSchedulingRequestFailsBeforeEncoding(testCase)
verifyError(testCase, @() ...
    sixgr.phy.ul.pusch.PUSCHUCIPayload( ...
    "HARQACK", 1, ...
    "SchedulingRequest", 1), ...
    "sixgr:pusch:SchedulingRequestNotCarriedOnPUSCH");
end

function testCSI2RequiresCSI1(testCase)
verifyError(testCase, @() ...
    sixgr.phy.ul.pusch.PUSCHUCIPayload( ...
    "CSIPart2", [1;0]), ...
    "sixgr:pusch:InvalidUCIBitBudget");
end

function testTwoCodewordUCIOwnerFollowsInitialMCS(testCase)
pusch = nrPUSCHConfig;
pusch.PRBSet = 0:23;
pusch.SymbolAllocation = [0 14];
pusch.Modulation = {"QPSK","16QAM"};
pusch.NumLayers = 5;
pusch.TransmissionScheme = "codebook";
pusch.NumAntennaPorts = 8;
pusch.TPMI = 0;
pusch.TransformPrecoding = false;
pusch.DMRS.DMRSConfigurationType = 2;
pusch.DMRS.DMRSLength = 2;
pusch.DMRS.DMRSPortSet = 0:4;
payload = sixgr.phy.ul.pusch.PUSCHUCIPayload("HARQACK", [1;0]);
rates = [0.30 0.45];
tbs = [512 1024];
initialIMCS = [4 12];
budget = nrULSCHInfo(pusch, rates, tbs, 2, 0, 0);
ulsch = cell(1, 2);
for cw = 1:2
    ulsch{cw} = int8(mod((0:double(budget.GULSCH(cw))-1).', 2));
end

mux = sixgr.phy.ul.pusch.PUSCHUCIMultiplexer.multiplex( ...
    pusch, rates, tbs, ulsch, payload, initialIMCS);

verifyEqual(testCase, mux.OwnerCodeword, 1);
verifyEqual(testCase, cellfun(@numel, mux.Codewords), ...
    mux.GPerCodeword);
verifyEqual(testCase, numel(mux.ACKCodedBits), ...
    double(budget.GACK(2)));
end
