function ok=testISACPDSCHReferenceGrid()
%TESTISACPDSCHREFERENCEGRID Production TBS reservation and waveform mapping.
[jointCfg,~]=sixgr.isac.loadJointConfig( ...
    "configs/isac/joint_isac_tdoc_master.yaml","quick");
[llsCfg,provenance]=sixgr.lls.loadConfig( ...
    "configs/lls/pdsch_isac_monostatic_30ghz_example.yaml");
llsCfg.isac.enabled=false;
phy=sixgr.lls.buildPHYConfig(llsCfg,35);
[carrier,~]=sixgr.phy.grid.makeCarrier(phy);
profiles=["W0","W1","W2","W3"]; rows=cell(numel(profiles),1);
for i=1:numel(profiles)
    reference=sixgr.isac.buildReferenceGrid(jointCfg,carrier,profiles(i),301+i,4, ...
        localVariant(profiles(i)));
    [row,diagnostic]=sixgr.lls.runPDSCHTransportBlock(llsCfg,phy, ...
        string(provenance.ConfigSHA256),1,i,"CaptureDiagnostic",true, ...
        "ISACReferenceGrid",reference.Grid);
    event=diagnostic.Tx.ISACReferenceEvent;
    assert(event.Enabled&&event.Transmitted&&event.NRE>0);
    sanitized=diagnostic.Tx.ISACReferenceGrid;
    sanitizedMask=sanitized~=0;
    assert(row.ReservedRE==nnz(any(sanitizedMask,3)) && event.NRE==nnz(sanitizedMask));
    assert(all(diagnostic.Tx.Grid(sanitizedMask)==sanitized(sanitizedMask)));
    rows{i}=struct2table(row);
end
t=vertcat(rows{:});
assert(numel(unique(t.TransportBlockSizeBits))==1 && all(~t.CRCError));
fprintf("testISACPDSCHReferenceGrid: PASS (%d profiles, TBS=%d)\n", ...
    height(t),t.TransportBlockSizeBits(1));
ok=true;
end

function value=localVariant(profile)
if profile=="W1", value="reset_aligned_interval"; else, value="default"; end
end
