function ok=testULPrecodingDCIField()
% Independent 38.212 table rows, not only encoder/decoder agreement.
setup6GRSimToolkit('Verbose',false);
legacy=sixgr.phy.pdcch.DCIContext.fromLegacy(struct('NSizeGrid',25),'0_1');
data=legacy.Data;
data.ULPrecoding=struct('num_ports',2,'max_rank',1, ...
    'codebook_subset',"fullyAndPartialAndNonCoherent", ...
    'transmission_scheme',"codebook",'full_power_mode',"not_configured");
for maxRank=1:2
    data.ULPrecoding.max_rank=maxRank;
    if maxRank==1
        expected=[(0:5).' ones(6,1) (0:5).']; width=3;
    else
        expected=[0 1 0;1 1 1;2 2 0;3 1 2;4 1 3;5 1 4;6 1 5;7 2 1;8 2 2]; width=4;
    end
    context=sixgr.phy.pdcch.DCIContext(data);
    schema=sixgr.phy.pdcch.DCISchemaEngine.resolve(context);
    def=schema.Definitions(string({schema.Definitions.Name})=="precoding_information_and_number_of_layers");
    assert(def.Width==width && def.ValueMax==size(expected,1)-1);
    for row=expected.'
        encoded=sixgr.phy.pdcch.ULPrecodingField.encode(data,row(2),row(3));
        assert(encoded==row(1));
        [rank,tpmi]=sixgr.phy.pdcch.ULPrecodingField.decode(data,row(1));
        assert(rank==row(2) && tpmi==row(3));
        cfg=struct('NSizeGrid',25,'DCIContext',context);
        payload=sixgr.phy.pdcch.buildDCI01UplinkGrant(cfg,'NumLayers',rank,'TPMI',tpmi);
        received=sixgr.phy.pdcch.decodeDCIPayload(payload.Bits,'0_1',context);
        assert(received.Fields.precoding_information_and_number_of_layers==row(1) && ...
            received.Fields.precoding_information_and_number_of_layers_tpmi==tpmi && ...
            received.Fields.precoding_information_and_number_of_layers_rank_minus1==rank-1);
    end
    localReject(@()sixgr.phy.pdcch.ULPrecodingField.decode(data,2^width-1));
    data.ULPrecoding.codebook_subset="nonCoherent";
    narrow=sixgr.phy.pdcch.ULPrecodingField.resolve(data);
    assert(narrow.Width==maxRank);
    localReject(@()sixgr.phy.pdcch.ULPrecodingField.encode(data,1,3));
    data.ULPrecoding.codebook_subset="fullyAndPartialAndNonCoherent";
end
data.ULPrecoding.num_ports=4;
localReject(@()sixgr.phy.pdcch.ULPrecodingField.resolve(data));
ok=true;
end

function localReject(fn)
try, fn(); catch ME
    assert(startsWith(string(ME.identifier),'sixgr:phy:pdcch:')); return;
end
error('test:MissingRejection','An unsupported/reserved precoding request was accepted.');
end
