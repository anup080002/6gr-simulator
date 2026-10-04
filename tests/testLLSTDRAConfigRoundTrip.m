function ok=testLLSTDRAConfigRoundTrip()
% Same DL/UL TDRA semantics before and after immutable JSON serialization.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/validation/lls_fdd_staged_data_connected_dci.yaml');
source=s.toStruct();
for multiple=[false true]
    data=source;
    if multiple
        data.pdsch.time_domain_allocations=[0 2 12 0;1 2 10 1];
        data.pusch.time_domain_allocations=[0 0 14 1;1 2 12 2];
    end
    snapshot=jsonencode(data);
    decoded=jsondecode(snapshot);
    originalDecoded=decoded;
    before=sixgr.lls6g.buildInternalConfig(data,tempname);
    after=sixgr.lls6g.buildInternalConfig(decoded,tempname);
    assert(isequaln(decoded,originalDecoded),'Do not mutate immutable input.');
    for direction={'pdsch','pusch'}
        a=before.phy.(direction{1}); b=after.phy.(direction{1});
        assert(isequal(a.timeDomainAllocations,b.timeDomainAllocations));
        assert(isequal(a.TimeDomainAllocations,b.TimeDomainAllocations));
    end
    for format=["1_1","0_1"]
        a=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(before,format);
        b=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(after,format);
        assert(isequaln(a.Data,b.Data) && a.Digest==b.Digest, ...
            'JSON recovery must preserve the installed receiver DCI context.');
    end
end
% No truncation, padding, arbitrary flattening, duplicate indices or invalid
% slot allocations are accepted by the singleton-shape repair.
badLists={ [0 2 12], [0 2 12 0 1], [0 2;12 0], ...
    [0 2 12 0;0 2 10 1], [0 3 12 0], [0 2 12 -1], ...
    [0 2 12 NaN], [0 2.5 11 0] };
for direction={'pdsch','pusch'}
    for k=1:numel(badLists)
        bad=source;
        bad.(direction{1}).time_domain_allocations=badLists{k};
        reject(@()sixgr.lls6g.buildInternalConfig(bad,tempname));
    end
end
ok=true;
end

function reject(fn)
try
    fn();
catch err
    assert(strcmp(err.identifier,'sixgr:lls6g:config:InvalidDataChannelTDRAList'), ...
        'Wrong failure: %s: %s',err.identifier,err.message);
    return;
end
error('test:MissingError','Malformed TDRA list was accepted.');
end
