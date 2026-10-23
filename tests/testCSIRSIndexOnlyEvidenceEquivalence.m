function ok=testCSIRSIndexOnlyEvidenceEquivalence()
% No RNG/sample/validation change when unused per-RE tables are omitted.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_4ghz_20mhz_64txru_4rx_cdlc100_impaired.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,2);
c=sixgr.phy.grid.makeCarrier(cfg);
before=rng; t=tic;
[ind,sym,info]=sixgr.phy.refsig.csirs(c,cfg); evidenceSeconds=toc(t);
t=tic; [leanInd,leanSym]=sixgr.phy.refsig.csirs(c,cfg); leanSeconds=toc(t);
assert(isequal(ind,leanInd) && isequal(sym,leanSym) && isequal(before,rng));
assert(info.NumResources==8 && height(info.ResourceMappingTable)==numel(sym));
for n=1:8
    r=info.Resources(n); T=r.ResourceMappingTable;
    assert(height(T)==numel(r.Symbols) && ...
        isequal(T.SymbolI+1i*T.SymbolQ,r.Symbols(:)) && ...
        isequal(T.LinearIndex,double(r.Indices(:))));
    [k,l,p]=ind2sub([12*c.NSizeGrid,c.SymbolsPerSlot,r.NumPorts],double(r.Indices(:)));
    assert(isequal(T.Subcarrier,k-1) && isequal(T.Symbol,l-1) && isequal(T.Port,p-1) && ...
        all(T.ResourceID==r.ResourceID) && all(T.PRB==floor((k-1)/12)));
end
bad=cfg; bad.phy.csirs.symbolLocationsByResource(2)=bad.phy.csirs.symbolLocationsByResource(1);
for outputs=[1 3]
    caught=false;
    try
        if outputs==1
            ignored=sixgr.phy.refsig.csirs(c,bad); %#ok<NASGU>
        else
            [a,b,d]=sixgr.phy.refsig.csirs(c,bad); %#ok<ASGLU>
        end
    catch err
        caught=strcmp(err.identifier,'sixgr:phy:csirs:ResourceCollision');
    end
    assert(caught,'Index-only callers must retain collision validation.');
end
fprintf('CSI_INDEX_EVIDENCE_EQUIVALENCE_PASS RE=%d evidence_s=%.6g lean_s=%.6g\n', ...
    numel(sym),evidenceSeconds,leanSeconds);
ok=true;
end
