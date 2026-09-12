function ok=testULReferenceSignaling()
setup6GRSimToolkit('Verbose',false);
context=sixgr.phy.pdcch.DCIContext.fromLegacy(struct('NSizeGrid',25),'0_1'); data=context.Data;
data.ULPrecoding=struct('num_ports',2,'max_rank',2,'codebook_subset', ...
    "fullyAndPartialAndNonCoherent",'transmission_scheme',"codebook",'full_power_mode',"not_configured");
data.ULReferenceSignaling=struct('srs_resource_count',1,'dmrs_configuration_type',1, ...
    'dmrs_max_length',1,'dmrs_type_enhanced',false,'multipanel_sdm',false);
% Independent expected standard rows: rank, value, CDM groups, ports.
rows={1,0,1,0;1,1,1,1;1,2,2,0;1,3,2,1;1,4,2,2;1,5,2,3; ...
    2,0,1,[0 1];2,1,2,[0 1];2,2,2,[2 3];2,3,2,[0 2]; ...
    3,0,2,[0 1 2];4,0,2,[0 1 2 3]};
for k=1:size(rows,1)
    rank=rows{k,1}; expected=rows{k,2}; groups=rows{k,3}; ports=rows{k,4};
    value=sixgr.phy.pdcch.ULReferenceSignaling.encodeAntenna(data,rank,ports,groups,1);
    assert(value==expected);
    [actualPorts,actualGroups]=sixgr.phy.pdcch.ULReferenceSignaling.decodeAntenna(data,rank,expected);
    assert(isequal(actualPorts,ports) && actualGroups==groups);
end
for count=1:4
    data.ULReferenceSignaling.srs_resource_count=count;
    context=sixgr.phy.pdcch.DCIContext(data);
    schema=sixgr.phy.pdcch.DCISchemaEngine.resolve(context);
    names=string({schema.Definitions.Name});
    if count==1, assert(~any(names=="srs_resource_indicator"));
    else, def=schema.Definitions(names=="srs_resource_indicator"); assert(def.Width==ceil(log2(count))); end
    for sri=0:count-1
        payload=sixgr.phy.pdcch.buildDCI01UplinkGrant(struct('NSizeGrid',25,'DCIContext',context), ...
            'NumLayers',1,'TPMI',3,'SRSResourceIndicator',sri,'DMRSPortSet',0,'NumCDMGroupsWithoutData',2);
        received=sixgr.phy.pdcch.decodeDCIPayload(payload.Bits,'0_1',context);
        assert(received.Fields.antenna_ports==2 && received.Fields.dmrs_num_cdm_groups_without_data==2 && ...
            isequal(received.Fields.dmrs_port_set,0) && received.Fields.srs_resource_index0based==sri);
        if count==1, assert(~isfield(received.Fields,'srs_resource_indicator')); end
        f=payload.FieldTable; ap=f(string(f.FieldName)=="antenna_ports",:);
        % FieldTable offsets are zero-based; MATLAB indexing is one-based.
        assert(ap.WidthBits==3 && isequal(payload.Bits(ap.BitStart+1:ap.BitEnd+1),int8([0;1;0])));
    end
    localReject(@()sixgr.phy.pdcch.ULReferenceSignaling.bindSRI(struct(),data,count));
end
localReject(@()sixgr.phy.pdcch.ULReferenceSignaling.decodeAntenna(data,1,7));
localReject(@()sixgr.phy.pdcch.ULReferenceSignaling.encodeAntenna(data,1,2,1,1));
localReject(@()sixgr.phy.pdcch.ULReferenceSignaling.encodeAntenna(data,1,0,2,2));
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml');
raw=s.toStruct();
bad=raw; bad.control.ul_reference_signaling.srs_resource_count=2;
localConfigReject(bad,'sixgr:lls6g:config:SRSResourceSetRuntimeMismatch');
bad=raw; bad.reference_signals.pusch_dmrs_num_cdm_groups_without_data=3;
localConfigReject(bad,'sixgr:lls6g:config:ULDMRSContextMismatch');
bad=raw; bad.reference_signals=rmfield(bad.reference_signals,'pusch_dmrs_num_cdm_groups_without_data');
localConfigReject(bad,'sixgr:lls6g:config:MissingULDMRSAuthority');
ok=true;
end
function localConfigReject(cfg,identifier)
try, sixgr.lls6g.config.validateScenarioConfig(cfg);
catch ME, assert(strcmp(ME.identifier,identifier),'Unexpected rejection: %s',ME.identifier); return; end
error('test:MissingRejection','Inconsistent YAML authority was accepted.');
end
function localReject(fn)
try, fn(); catch ME, assert(startsWith(string(ME.identifier),'sixgr:phy:pdcch:')); return; end
error('test:MissingRejection','Invalid reference signaling was accepted.');
end
