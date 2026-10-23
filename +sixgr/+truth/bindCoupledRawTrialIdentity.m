function raw = bindCoupledRawTrialIdentity(raw, cfg)
% Bind the active coupled producer's completed trials BEFORE publication.
% Not for imported/recovered evidence: only the producing runtime owns this
% identity. Preserve existing identities and reject contradictions through
% the same binder used for primary CSV publication. Never invent trial rows.
arguments
    raw (1,1) struct
    cfg (1,1) struct
end
domains = ["DL","UL","PBCH","PRACH","PDCCH","PUCCH","SRS","CSIRS","TRS"];
signals = ["DL","UL","PBCH","PRACH","PDCCH","PUCCH","SRS","CSI-RS","TRS"];
for k = 1:numel(domains)
    if ~isfield(raw, domains(k)), continue; end
    raw.(domains(k)) = sixgr.truth.bindCoupledExecutionIdentity( ...
        raw.(domains(k)), cfg, signals(k), true);
end
end
