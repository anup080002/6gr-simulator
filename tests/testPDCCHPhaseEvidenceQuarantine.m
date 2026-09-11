function ok=testPDCCHPhaseEvidenceQuarantine()
% Safety regression, not a substitute for the blocked phase qualification.
root=fileparts(fileparts(mfilename('fullpath')));
vectors=fullfile(root,'tests','vectors','pdcch');
for fast=[false true]
    output=tempname;
    observed="";
    try
        sixgr.phy.pdcch.runPDCCHPhaseValidation( ...
            'VectorRoot',vectors,'OutputDir',output, ...
            'Strict',true,'FastTestMode',fast);
    catch exception
        observed=string(exception.identifier);
    end
    assert(observed=="sixgr:phy:pdcch:unverified_phase_evidence", ...
        'Unverified phase evidence must fail explicitly in both execution modes.');
    assert(~isfolder(output) && ~isfile(output), ...
        'The guard must reject before producing any primary artifacts.');
end
for fast=[false true]
    output=tempname;
    observed="";
    try
        sixgr.phy.pucch.runPUCCHPhaseValidation( ...
            'VectorRoot',fullfile(root,'tests','vectors','pucch'), ...
            'OutputDir',output,'Strict',true,'FastTestMode',fast);
    catch exception
        observed=string(exception.identifier);
    end
    assert(observed=="sixgr:phy:pucch:UnverifiedPhaseEvidence");
    assert(~isfolder(output) && ~isfile(output));
end
ok=true;
end
