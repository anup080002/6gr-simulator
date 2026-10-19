function ok=testH4100Msg3ObservedPortDomains()
% Actual 273-PRB carrier/four-chain Msg3 TX, not a fabricated index fixture.
sc=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','h4_100_cdlc100_connected_impaired_40db_adaptation.yaml'));
cfg=sixgr.config.normalizeConfig(sixgr.lls6g.buildInternalConfig(sc,tempname));
ra=sixgr.mac.ra.RAConfig(cfg,'RunId','h4_msg3_port_domains', ...
    'ScenarioName','h4_msg3_port_domains','UEId',1,'CellId',1,'AttemptId',1);
grant=sixgr.mac.ra.buildRARULGrant(ra);
msg=sixgr.mac.ra.buildMsg3Payload('UEId',1,'UEIdentity','UE-1','RRCSetupRequest',true);
saved=rng; cleanup=onCleanup(@()rng(saved)); %#ok<NASGU>
rng(double(cfg.run.seed),'twister');
tx=sixgr.phy.ra.generateMsg3PUSCHWaveform(cfg,ra,grant,msg);
assert(tx.Carrier.NSizeGrid==273 && tx.PUSCH.NumLayers==1 && ...
    size(tx.Grid,3)==4 && tx.PrecodeInfo.HybridElementDomainApplied);
assert(size(tx.PUSCHNativeIndices,2)==1 && size(tx.PUSCHWaveformIndices,2)==4);
T=observe(tx);
assert(sum(T.re_count)==nnz(tx.Grid) && all(T.layer_count==1));
active=find(squeeze(any(any(tx.Grid~=0,1),2)))-1;
assert(isequal(unique(T.port_index),active(:)), ...
    'Only nonzero transmitted antenna pages count as occupied, not the chain inventory.');
bad=tx; bad.PUSCHNativeIndices(1)=bad.PUSCHNativeIndices(1)+1;
reject(bad,'sixgr:truth:ExecutedREIndexMismatch');
bad=tx; bad.PUSCHWaveformIndices(1)=bad.PUSCHWaveformIndices(1)+1;
reject(bad,'sixgr:truth:ExecutedREIndexMismatch');
bad=tx; index=tx.PUSCHWaveformIndices(1); bad.Grid(index)=bad.Grid(index)*1.01;
reject(bad,'sixgr:truth:ExecutedREGridMismatch');
bad=rmfield(tx,'DMRSNativeIndices');
reject(bad,'sixgr:truth:MissingExecutedPUSCHDomains');
fprintf('PASS H4 Msg3: %d native data RE, %d mapped columns, %d nonzero grid RE.\n', ...
    size(tx.PUSCHNativeIndices,1),size(tx.PUSCHWaveformIndices,2),nnz(tx.Grid));
ok=true;
end

function T=observe(tx)
T=sixgr.truth.buildObservedREAllocation(tx,'Direction','UL','AbsoluteSlot',34);
end

function reject(tx,id)
try
    observe(tx);
catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s.',id,cause.identifier);
    return;
end
error('sixgr:test:MissingExpectedFailure','Expected %s.',id);
end
