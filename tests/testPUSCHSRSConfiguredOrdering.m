function ok=testPUSCHSRSConfiguredOrdering(scenarioPath)
%TESTPUSCHSRSCONFIGUREDORDERING Verify installed priority and UL TDRA.
if nargin<1
    scenarioPath=['simulator/configs/scenarios/' ...
        'lls_tdd_5mhz_rank2_4tx2rx_awgn_m10db.yaml'];
end
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
assert(cfg.phy.srs.enable && cfg.phy.pdcch.enable && cfg.phy.pucch.enable);
assert(cfg.phy.pusch.priorityIndex==0 && ...
    string(cfg.phy.pusch.priorityIndexSource)=="yaml.pusch.priority_index");
configured=sixgr.phy.frame.assertConfiguredPriorityZeroPUSCHSRSOrder(cfg);
assert(configured.Applicable && configured.ConfiguredRowsChecked==2 && ...
    isequal(configured.SRSSymbols0Based,11));
assert(isequal(double(cfg.phy.pusch.symbolAllocation),[0 11]));
context=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg,'0_1');
rows=double(context.Data.ULTimeDomainAllocations);
assert(isequal(rows,[0 0 11 1;1 0 11 2]));
for symbols={0:12,12:13,[0:10 12]}
    localReject(@()sixgr.phy.frame.assertPriorityZeroPUSCHBeforeSRS( ...
        symbols{1},11,14),'sixgr:phy:frame:PriorityZeroPUSCHSRSOrder');
end
for k2=[1 2]
    selected=sixgr.truth.selectConfiguredTDRARow(cfg,'UL',[0 11],k2);
    assert(isequal(selected.SymbolAllocation,[0 11]) && ...
        selected.SlotOffset==k2);
end
bad=s.toStruct();
bad.pusch.start_symbol=0;
bad.pusch.num_symbols=13;
bad.pusch.time_domain_allocations=[0 0 13 1;1 0 13 2];
localReject(@()sixgr.lls6g.buildInternalConfig(bad,tempname), ...
    'sixgr:phy:frame:PriorityZeroPUSCHSRSOrder');
ok=true;
fprintf(['PUSCH_SRS_CONFIGURED_ORDERING_PASS: priority-0 allocation, ' ...
    'installed DCI rows, and exact symbol order.\n']);
end

function localReject(fn,id)
try
    fn();
catch exception
    assert(strcmp(exception.identifier,id), ...
        'Expected %s, got %s.',id,exception.identifier);
    return;
end
error('testPUSCHSRSConfiguredOrdering:ExpectedRejection','Expected %s.',id);
end
