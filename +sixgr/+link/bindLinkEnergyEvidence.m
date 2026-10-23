function trial = bindLinkEnergyEvidence(trial,evidence)
%BINDLINKENERGYEVIDENCE Lossless original-receipt projection, no late relabel.
arguments
    trial table
    evidence (1,1) struct
end
assert(height(trial)==1 && isfield(evidence,'Identity') && isfield(evidence.Identity,'Direction'), ...
    'sixgr:link:EnergyEvidenceOwner','One original owner row and direction are required.');
token=string(jsonencode(evidence)); digest=string(sixgr.util.sha256Hex(char(token)));
values=struct('LinkEnergyEvidenceJSON',token,'LinkEnergyEvidenceSHA256',digest);
for name=string(fieldnames(values))'
    if ismember(name,string(trial.Properties.VariableNames))
        prior=string(trial.(name));
        assert(isscalar(prior) && ~ismissing(prior) && (strlength(prior)==0 || prior==values.(name)), ...
            'sixgr:link:EnergyEvidenceConflict','Cannot overwrite original energy evidence.');
    end
    trial.(name)=values.(name);
end
% Includes every supplied original population/attempt field, not only slot.
sixgr.report.collectLinkEnergyRatioEvidence(trial,string(evidence.Identity.Direction),"bind_validation");
end
