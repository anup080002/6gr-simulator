function ok=testH4100CSIIMDataMapping()
% Real scheduler/frozen-grant/TX mapping on the H4 CSI-RS + CSI-IM slot.
% Delivered CSI/SRS are explicit boundary fixtures, not receiver evidence.
count=0;
assert(testH4100AdaptiveDataMapping(@check, ...
    'simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_gate.yaml',6));
assert(count==6,'Exercise both edge beams at every supported DL rank.');
ok=true;
    function check(cfg,direction,grant,frozen,tx,info) %#ok<INUSD>
        if direction~="DL", return; end
        plan=sixgr.phy.refsig.csiIMResource(tx.Carrier,cfg);
        assert(plan.Scheduled && plan.NumRE==1092 && tx.CSIIMResource.Scheduled);
        grid=reshape(tx.Grid,[],size(tx.Grid,3));
        assert(size(grid,2)==64 && all(grid(plan.PhysicalIndices1Based,:)==0,'all'));
        assert(frozen.CodingLayout.NumLayers==grant.NumLayers && ...
            numel(tx.TransportBlock)>0 && numel(tx.Codeword)>numel(tx.TransportBlock));
        count=count+1;
    end
end
