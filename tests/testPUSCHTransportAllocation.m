function ok=testPUSCHTransportAllocation()
% Native geometry is not authority for experimental modulation or bit count.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_four_port_connected_research_ul_fixture.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
carrier=sixgr.phy.grid.makeCarrier(cfg);
for rank=[2 4]
    args={'NumLayers',rank,'TPMI',0};
    [indices,info,geometry,transport]=sixgr.phy.grid.allocPUSCHTransport( ...
        carrier,cfg,args{:},'Modulation','1024QAM');
    [reference,nativeInfo]=sixgr.phy.grid.allocREsPUSCH( ...
        carrier,cfg,args{:},'Modulation','QPSK');
    assert(isequal(indices,reference) && strcmp(geometry.Modulation,'QPSK') && ...
        strcmp(info.Modulation,'1024QAM') && transport.Qm==10 && ...
        info.G==5*nativeInfo.G && info.NREPerPRB==nativeInfo.NREPerPRB && ...
        ~info.StandardNR && info.PUSCHIndicesInfo.G==info.G);
    actualTBS=nrTBS(info.Modulation,rank,numel(geometry.PRBSet),info.NREPerPRB,.5);
    assert(actualTBS==nrTBS('1024QAM',rank,numel(geometry.PRBSet),nativeInfo.NREPerPRB,.5));
    tx=struct('PUSCH',geometry,'PUSCHRole',info.GeometryRole, ...
        'Modulation','1024QAM','ResearchTransport',transport,'StandardNR',false);
    [modulation,experimental]=sixgr.link.resolvePUSCHTransportModulation(tx);
    assert(modulation=="1024QAM" && experimental);
    bad=tx; bad.Modulation='QPSK';
    localReject(@()sixgr.link.resolvePUSCHTransportModulation(bad), ...
        'sixgr:research:MissingTransportModulation');
    bad=rmfield(tx,'StandardNR');
    localReject(@()sixgr.link.resolvePUSCHTransportModulation(bad), ...
        'sixgr:research:MissingTransportModulation');
end
native=cfg; native.phy.pusch.mcsTable='qam64_table1';
[a,ai,ag]=sixgr.phy.grid.allocREsPUSCH(carrier,native);
[b,bi,bg,bt]=sixgr.phy.grid.allocPUSCHTransport(carrier,native);
assert(isequal(a,b) && isequaln(ai,bi) && isequaln(ag,bg) && isempty(bt));
bad=cfg; bad.phy.pusch.experimentalMCSTable.Rows(1,3)=.9;
localReject(@()sixgr.phy.grid.allocPUSCHTransport(carrier,bad), ...
    'sixgr:research:MCSTableContextMismatch');
fprintf('PUSCH_TRANSPORT_ALLOCATION_PASS native_unchanged=1 experimental_Qm=10 ranks=2,4\n');
ok=true;
end

function localReject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Expected %s, got %s: %s',id,ME.identifier,ME.message); return; end
error('test:MissingRejection','Expected %s.',id);
end
