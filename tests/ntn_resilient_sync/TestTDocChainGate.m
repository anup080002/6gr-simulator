classdef TestTDocChainGate < matlab.unittest.TestCase
    methods(Test)
        function allRequiredTxRxNodesExecute(tc)
            out=string(tempname);
            result=sixgr.ntn.resilientsync.runTDocChainGate( ...
                "configs/ntn_resilient_sync/tdoc.yaml", ...
                "OutputDirectory",out);
            tc.verifyEqual(result.Status,"CHAIN_GATE_PASS");
            tc.verifyEqual(sort(result.GateTable.Node), ...
                sort(["NTN_TOPOLOGY";"PDSCH";"TRS";"PRACH";"PUSCH";"PUCCH"]));
            tc.verifyTrue(all(result.GateTable.Pass));
            tc.verifyTrue(all(result.GateTable.ApproximationMode=="none"));
            tc.verifyFalse(any(result.GateTable.QualificationEligible));
            tc.verifyTrue(isfile(fullfile(out,"ntn_tdoc_tx_rx_chain_gate.csv")));
        end
    end
end
