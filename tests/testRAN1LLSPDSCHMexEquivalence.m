function ok = testRAN1LLSPDSCHMexEquivalence()
% Historical entry name: test exact v2 MATLAB batch versus native matrix.
% The v1 MEX ABI is retired; this does NOT qualify a replacement MEX/speedup.

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
    assert(~mexRow.UseMexLDPC && mexRow.LDPCDecoderEngine == ...
        "sixgr_ldpc_decode_batch_kernel_v2_MATLAB");
    assert(~matlabRow.UseMexLDPC && matlabRow.LDPCDecoderEngine == ...
        "nrLDPCDecode");
    assert(mexRow.CRCError == matlabRow.CRCError && ...
        mexRow.BitErrors == matlabRow.BitErrors);
    assert(isequal(mexDiagnostic.Rx.TransportBlock, ...
        matlabDiagnostic.Rx.TransportBlock));
    assert(isequal(mexDiagnostic.Rx.Decode.DecodedCodeBlocks, ...
        matlabDiagnostic.Rx.Decode.DecodedCodeBlocks));
    assert(isequal(mexDiagnostic.Rx.Decode.FinalParityChecks, ...
        matlabDiagnostic.Rx.Decode.FinalParityChecks));
    assert(mexDiagnostic.Rx.Decode.BatchLDPCRequested && ...
        ~matlabDiagnostic.Rx.Decode.BatchLDPCRequested);
    mexRuntime = mexRuntime + mexRow.RuntimeSeconds;
    matlabRuntime = matlabRuntime + matlabRow.RuntimeSeconds;
    mexDecodeLatency = mexDecodeLatency + ...
        double(mexDiagnostic.Rx.Decode.DecodeLatency_s);
    matlabDecodeLatency = matlabDecodeLatency + ...
        double(matlabDiagnostic.Rx.Decode.DecodeLatency_s);
end
fprintf(['RAN1LLSPDSCH exact v2 MATLAB batch: bits/CRC/full parity match; MEX_qualified=0; ' ...
    'measured native/batch time ratio decoder=%.2f total=%.2f (no speed guarantee).\n'], ...
    matlabDecodeLatency/mexDecodeLatency,matlabRuntime/mexRuntime);
ok = true;
end
