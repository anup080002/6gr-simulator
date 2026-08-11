function result = run_ntn_topology_short_proof(runTag)
%RUN_NTN_TOPOLOGY_SHORT_PROOF Run one short satellite/UE physical proof.
if nargin<1
    runTag="";
end
setup6GRSimToolkit('Verbose',false);
result=sixgr.ntn.resilientsync.topology.runShortProof( ...
    "configs/ntn_resilient_sync/quick.yaml","RunTag",string(runTag));
fprintf("NTN topology proof: %s\n%s\n",result.Status,result.RunDirectory);
end
