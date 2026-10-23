function binding=resolveReceiveBranchLayout(cfg,receiverID,direction,nPhysical,fs,epoch)
% Distinguish absent legacy geometry from malformed installed authority.
% No synthetic RF type, matrix or executed receipt is created here.
direction=string(direction);
assert(isscalar(direction)&&any(direction==["DL","UL"]), ...
    'RF:ReceiveBranchInstallation','Declare the actual receiver direction.');
if direction=="UL"
    arrayPath='lls6g.userContext.RuntimeServingBSAntenna'; referencePath='rf.bsPowerReference';
else
    arrayPath='lls6g.userContext.RuntimeUEAntenna'; referencePath='rf.uePowerReference';
end
binding=struct('Available',false,'Status',"unavailable_no_installed_receive_array", ...
    'Installation',struct(),'Layout',struct());
a=sixgr.util.structGet(cfg,arrayPath,[]);
if isempty(a)||(isstruct(a)&&isscalar(a)&&isempty(fieldnames(a))), return; end
reference=sixgr.util.structGet(cfg,referencePath,[]);
if isempty(reference)||(isstruct(reference)&&isscalar(reference)&&isempty(fieldnames(reference)))
    % Invalid explicit geometry still fails even when the RF type is absent.
    binding.Installation=sixgr.rf.validateReceiveBranchInstallation( ...
        cfg,receiverID,direction,nPhysical,fs,epoch);
    binding.Status="validated_geometry_unavailable_explicit_RF_reference";
    return;
end
binding.Layout=sixgr.rf.ReceiveBranchLayout.freeze(cfg,receiverID,direction,nPhysical,fs,epoch);
binding.Installation=struct('Identity',binding.Layout.Identity,'Geometry',binding.Layout.Geometry);
binding.Available=true;
binding.Status="installed_identity_layout_not_yet_executed";
end
