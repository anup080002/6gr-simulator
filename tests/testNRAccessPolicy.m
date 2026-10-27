function ok=testNRAccessPolicy()
legacy=sixgr.lls6g.config.resolveNRAccessPolicy(struct());assert(~legacy.Enabled);
n=struct('encoding_profile',"nr_rrc_access_base_srb1_uper_v1", ...
    'require_setup_complete',true,'transaction_id',2,'srb1_lcid',1, ...
    'establishment_cause',"mo-Signalling",'selected_plmn_identity',1,'dedicated_nas_hex',"7e0041");
p=sixgr.lls6g.config.resolveNRAccessPolicy(n);
assert(p.Enabled&&p.DedicatedNASHex=="7E0041"&&p.RequireReceivedSetupCompleteGrant && ...
    p.TransactionID==2 && p.SRB1LCID==1);
for field=["dedicated_nas_hex","selected_plmn_identity","establishment_cause"]
    reject(@()sixgr.lls6g.config.resolveNRAccessPolicy(rmfield(n,field)));
end
bad=n;bad.dedicated_nas_hex="7G";reject(@()sixgr.lls6g.config.resolveNRAccessPolicy(bad));
bad=n;bad.srb1_lcid=2;reject(@()sixgr.lls6g.config.resolveNRAccessPolicy(bad));
bad=n;bad.establishment_cause="spare1";reject(@()sixgr.lls6g.config.resolveNRAccessPolicy(bad));
ok=true;
end
function reject(f)
try,f();catch e,assert(string(e.identifier)=="sixgr:rrc:InvalidAccessPolicy");return;end
error('test:NRAccessPolicyGuard','Invalid access policy accepted.');
end
