function value=buildDMRSArtifactEvidence(runID)
%BUILDDMRSARTIFACTEVIDENCE Measured digital sequence component evidence.
rows=cell(24,1);
for ii=1:numel(rows)
    mu=mod(ii-1,4); nRB=24+6*mod(ii-1,4);
    granularity="allContiguousRBs";
    if mod(ii,2)==1, granularity="sameAsREG-bundle"; end
    context=struct('NumerologyMu',mu,'Slot',mod(3*ii,10*2^mu), ...
        'Symbol',mod(ii-1,3),'NID',mod(43*ii,1008),'CORESETRBs',nRB, ...
        'PrecoderGranularity',granularity,'AttemptedPRBs',0:nRB-1);
    actual=sixgr.phy.pdcch.PDCCHDMRS.generate(context);
    e=sixgr.phy.pdcch.measureDMRSSequenceCorrelation(context,actual);
    assert(e.IndependentMismatchCount==0,'sixgr:phy:pdcch:dmrs_reference_mismatch', ...
        'PDCCH DM-RS samples disagree with the independent sequence reference.');
    e.RunID=string(runID); e.CaseID="DMRS"+compose('%04d',ii);
    e.DMRSVectorIndex=ii; e.NumerologyMu=mu; e.Slot=actual.Slot;
    e.Symbol=actual.Symbol; e.NID=actual.NID; e.CInit=actual.CInit;
    e.CORESETID=1; e.CORESETRBs=nRB;
    e.PrecoderGranularity=actual.PrecoderGranularity;
    e.AttemptedPRBs=join(string(context.AttemptedPRBs),'|');
    e.DMRSRECount=actual.MappedRECount; e.SequenceSHA256=actual.SequenceSHA256;
    e.IndexSHA256=actual.IndexSHA256; e.Status="PASS";
    rows{ii}=struct2table(e);
end
value=vertcat(rows{:});
end
