function ok = testRAN1LLSPDSCHMexEquivalence()
%TESTRAN1LLSPDSCHMEXEQUIVALENCE Prove exact canonical DL decoder parity.

setup6GRSimToolkit("Verbose",false,"RunToolboxChecks",false);
[mexCfg,provenance] = sixgr.lls.loadConfig( ...
    "configs/lls/pdsch_reference_smoke.yaml");
matlabCfg = mexCfg;
matlabCfg.receiver.useMexLDPC = false;
matlabCfg = sixgr.lls.validateConfig(matlabCfg);
snrIndices = [1 2];
mexRuntime = 0;
matlabRuntime = 0;
mexDecodeLatency = 0;
matlabDecodeLatency = 0;
for index = 1:numel(snrIndices)
    snrIndex = snrIndices(index);
    snrDb = double(mexCfg.simulation.snrDb(snrIndex));
    mexPHY = sixgr.lls.buildPHYConfig(mexCfg,snrDb);
    matlabPHY = sixgr.lls.buildPHYConfig(matlabCfg,snrDb);
    [mexRow,mexDiagnostic] = sixgr.lls.runPDSCHTransportBlock( ...
        mexCfg,mexPHY,provenance.ConfigSHA256,snrIndex,1);
    [matlabRow,matlabDiagnostic] = sixgr.lls.runPDSCHTransportBlock( ...
        matlabCfg,matlabPHY,provenance.ConfigSHA256,snrIndex,1);
    assert(mexRow.UseMexLDPC && contains(mexRow.LDPCDecoderEngine, ...
        "ldpc_decode_batch_kernel"));
    assert(~matlabRow.UseMexLDPC && matlabRow.LDPCDecoderEngine == ...
        "sixgr.phy.phycode.ldpcDecode");
    assert(mexRow.CRCError == matlabRow.CRCError && ...
        mexRow.BitErrors == matlabRow.BitErrors);
    assert(isequal(mexDiagnostic.Rx.TransportBlock, ...
        matlabDiagnostic.Rx.TransportBlock));
    assert(isequal(mexDiagnostic.Rx.Decode.DecodedCodeBlocks, ...
        matlabDiagnostic.Rx.Decode.DecodedCodeBlocks));
    mexRuntime = mexRuntime + mexRow.RuntimeSeconds;
    matlabRuntime = matlabRuntime + matlabRow.RuntimeSeconds;
    mexDecodeLatency = mexDecodeLatency + ...
        double(mexDiagnostic.Rx.Decode.DecodeLatency_s);
    matlabDecodeLatency = matlabDecodeLatency + ...
        double(matlabDiagnostic.Rx.Decode.DecodeLatency_s);
end
assert(mexDecodeLatency < matlabDecodeLatency, ...
    "Exact MEX LDPC path must reduce decoder-only latency.");
fprintf(['RAN1LLSPDSCHMexEquivalence: exact outputs match; ' ...
    'decoder %.2fx, end-to-end %.2fx speedup.\n'], ...
    matlabDecodeLatency/mexDecodeLatency,matlabRuntime/mexRuntime);
ok = true;
end
