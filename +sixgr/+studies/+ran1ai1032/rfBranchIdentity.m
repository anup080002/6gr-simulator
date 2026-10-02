function id=rfBranchIdentity(branch)
% Fingerprint resolved RF/compensation policy, including external mask digest.
assert(isstruct(branch) && isscalar(branch) && isfield(branch,'id'), ...
    'sixgr:ran1ai1032:F1RFBranch','A resolved RF branch is required.');
id=string(branch.id)+":"+string(sixgr.util.sha256Hex( ...
    uint8(unicode2native(jsonencode(branch),'UTF-8'))));
end
