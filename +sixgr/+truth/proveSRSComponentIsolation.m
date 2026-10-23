function proof=proveSRSComponentIsolation(trace,request)
% Preserve the SRS proof contract while sharing signal-independent arithmetic.
try
    proof=sixgr.truth.proveEmittedComponentIsolation(trace,request);
catch cause
    if strcmp(cause.identifier,'sixgr:truth:EmittedComponentIsolationEvidence')
        message=strrep(cause.message,'original frozen component waveform','original frozen SRS waveform');
        error('sixgr:truth:SRSIsolationEvidence','%s',message);
    end
    rethrow(cause);
end
proof.ContractVersion="sixgr.truth.SRSComponentIsolation/v1";
proof.AllHistorySRSOnlyRequired=proof.AllHistoryComponentOnlyRequired;
proof=rmfield(proof,'AllHistoryComponentOnlyRequired');
end
