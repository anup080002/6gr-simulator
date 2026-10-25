function accepted=pbchAcquisitionAccepted(trials)
%PBCHACQUISITIONACCEPTED Received identity/MIB authority, not CRC alone.
% Per-row result: callers retain the original BCH CRC even if the decoded
% candidate identity is inconsistent. SI reception is a later procedure and
% neither SIB1TreeEqual nor a generic combined-report Status grants MIB
% authority. A later SI exception can set the combined Crash/Status fields;
% it does not undo the original accepted BCH identity. Missing/NaN/legacy
% BCH evidence is not a successful acquisition.
assert(istable(trials),'sixgr:truth:InvalidPBCHAcquisitionEvidence', ...
    'Use original PBCH receiver trial rows.');
accepted=true(height(trials),1);
for name=["BCHCRCValid","MIBDecoded","CandidateIdentityConsistent","SSBIdentityVerified"]
    if ~ismember(name,string(trials.Properties.VariableNames))
        accepted(:)=false;
        return;
    end
    value=trials.(name);
    if ~((isnumeric(value)||islogical(value)) && isreal(value) && ...
            isequal(size(value),[height(trials),1]))
        accepted(:)=false;
        return;
    end
    accepted=accepted & isfinite(value) & value==1;
end
end
