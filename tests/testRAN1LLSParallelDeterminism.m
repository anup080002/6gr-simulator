function ok = testRAN1LLSParallelDeterminism()
%TESTRAN1LLSPARALLELDETERMINISM Verify batched workers preserve PHY truth.

setup6GRSimToolkit("Verbose",false,"RunToolboxChecks",false);
tmp = string(tempname);
mkdir(tmp);
cleanup = onCleanup(@()localCleanup(tmp)); %#ok<NASGU>
serial = sixgr.lls.runLLS("configs/lls/pusch_reference_smoke.yaml", ...
    "OutputRoot",tmp,"RunTag","serial","GeneratePlots",false);
parallel = sixgr.lls.runLLS("configs/lls/pusch_awgn_parallel_regression.yaml", ...
    "OutputRoot",tmp,"RunTag","parallel","GeneratePlots",false);

columns = ["SNRIndex","TrialIndex","BitSeed","NoiseSeed","ChannelSeed", ...
    "TransportBlockSizeBits","BitErrors","CRCError","MeasuredSNRdB", ...
    "TrueChannelGridSHA256","PostEqSINRdB"];
assert(isequaln(serial.TrialTable{:,columns},parallel.TrialTable{:,columns}), ...
    "Serial and worker-batched actual waveform trials must be identical.");
summaryColumns = ["SNRdB","NumTB","NumBlockErrors","BLER","NumBitErrors", ...
    "ThroughputBps","MeanMeasuredSNRdB"];
assert(isequaln(serial.SummaryTable{:,summaryColumns}, ...
    parallel.SummaryTable{:,summaryColumns}));
fprintf("RAN1LLSParallelDeterminism: %d actual TB rows match exactly.\n", ...
    height(serial.TrialTable));
ok = true;
end

function localCleanup(path)
p = gcp("nocreate");
if ~isempty(p)
    delete(p);
end
if exist(path,"dir") == 7
    rmdir(path,"s");
end
end
