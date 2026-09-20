function ok=testConnectedDCIProfile()
% Independently specified baseline layouts; not a full-run qualification.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
raw=s.toStruct();
for channel={'pdsch','pusch'}
    for name={'dmrs_nscid','time_domain_allocations'}
        incomplete=raw; incomplete.(channel{1})=rmfield(incomplete.(channel{1}),name{1});
        localReject(@()sixgr.lls6g.config.validateScenarioConfig(incomplete), ...
            'sixgr:lls6g:config:MissingConnectedDataPolicy');
    end
end
ul=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg,'0_1');
dl=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg,'1_1');
assert(~ul.Data.LegacyCompatibility && ~dl.Data.LegacyCompatibility);
assert(ul.Data.SearchSpaceID==raw.control.connected_dci.search_space_id && ...
    dl.Data.CORESETID==raw.control.connected_dci.coreset_id);
common=["format_identifier","frequency_resource_assignment","time_resource_assignment", ...
    "mcs","ndi","rv","harq_process"];
ulNames=[common,"first_dai","tpc_command_for_pusch", ...
    "precoding_information_and_number_of_layers","antenna_ports","srs_request", ...
    "dmrs_sequence_initialization","ul_sch_indicator"];
dlNames=[common,"dai","tpc_command_for_pucch","pucch_resource_indicator", ...
    "pdsch_to_harq_feedback_timing","antenna_ports", ...
    "transmission_configuration_indication","srs_request","dmrs_sequence_initialization"];
% N_RB=25 gives nine RIV bits; two TDRA rows give one bit. Ordinary
% HARQ process ID is four bits, independent of this run's process count.
ulWidths=[1 9 1 5 1 2 4 2 2 3 3 2 1 1];
dlWidths=[1 9 1 5 1 2 4 2 2 3 3 4 3 2 1];
ulValues=[0 0 0 10 1 0 0 1 1 3 2 0 1 1];
dlValues=[1 0 0 10 1 0 0 1 1 0 7 0 0 0 1];
u=localCheck(ul,ulNames,ulWidths,ulValues,37);
d=localCheck(dl,dlNames,dlWidths,dlValues,43);
assert(u.Fields.precoding_information_and_number_of_layers_tpmi==3 && ...
    u.Fields.dmrs_sequence_initialization==1 && u.Fields.ul_sch_indicator==1);
assert(d.Fields.pdsch_to_harq_feedback_timing_slots==8);
for context={ul,dl}
    sizes=sixgr.phy.pdcch.DCISizeAlignmentEngine.resolve(context{1});
    assert(isequal(sort(sizes.UniqueMonitoredSizes),[37 43]));
end
assert(isequal(sort(cfg.phy.pdcch.dciPayloadSizesByFormat(:)),[37;43]));
% The new DL selector reaches actual sequence generation, not only DCI/YAML.
carrier=sixgr.phy.grid.makeCarrier(cfg);
p0=sixgr.phy.grid.pdschConfigFromConfig(carrier,cfg);
changed=cfg; changed.phy.pdsch.dmrs.NSCID=1;
p1=sixgr.phy.grid.pdschConfigFromConfig(carrier,changed);
assert(p0.DMRS.NSCID==0 && p1.DMRS.NSCID==1 && ...
    ~isequal(nrPDSCHDMRS(carrier,p0),nrPDSCHDMRS(carrier,p1)));

% Configuration changes, including zero-bit fields, change both peers'
% layouts consistently; padding/extra fields may not mask missing policy.
one=cfg; one.phy.pdsch.timeDomainAllocations=one.phy.pdsch.timeDomainAllocations(1,:);
one.phy.pucch.dlDataToULACK=8;
c=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(one,'1_1');
keep=~ismember(dlNames,["time_resource_assignment","pdsch_to_harq_feedback_timing"]);
decoded=localCheck(c,dlNames(keep),dlWidths(keep),dlValues(keep),39);
assert(~isfield(decoded.Fields,'time_resource_assignment') && ...
    ~isfield(decoded.Fields,'pdsch_to_harq_feedback_timing') && ...
    decoded.Fields.time_domain_assignment_index==0 && decoded.Fields.pdsch_to_harq_feedback_timing_slots==8);
bad=cfg; bad.phy.pdcch.operatorControl.connected_dci.cbg_enabled=true;
localReject(@()sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(bad,'0_1'), ...
    'sixgr:phy:pdcch:UnsupportedConnectedDCIPolicy');
bad=cfg; bad.phy.pdcch.operatorControl.connected_dci=rmfield(bad.phy.pdcch.operatorControl.connected_dci,'beta_offsets');
localReject(@()sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(bad,'0_1'), ...
    'sixgr:phy:pdcch:IncompleteConnectedDCIPolicy');
bad=cfg; bad.phy.pusch.NumAntennaPorts=1;
localReject(@()sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(bad,'0_1'), ...
    'sixgr:phy:pdcch:ULPrecodingContextMismatch');
bad=cfg; bad.phy.pusch.numLayers=2; % Installed maxRank remains one.
localReject(@()sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(bad,'0_1'), ...
    'sixgr:phy:pdcch:ULPrecodingContextMismatch');
bad=cfg; bad.phy.pdcch.operatorControl.ul_precoding.max_rank=2;
localReject(@()sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(bad,'0_1'), ...
    'sixgr:phy:pdcch:ULPrecodingContextMismatch');
bad=cfg; bad.phy.pdsch.timeDomainAllocations(2,1)=4;
localReject(@()sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(bad,'1_1'), ...
    'sixgr:phy:pdcch:InvalidConnectedTDRA');
bad=cfg; bad.phy.harq.cbgEnabled=true;
localReject(@()sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(bad,'1_1'), ...
    'sixgr:phy:pdcch:ConnectedRuntimeMismatch');
bad=cfg; bad.phy.pusch.intraSlotFrequencyHopping=true;
localReject(@()sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(bad,'0_1'), ...
    'sixgr:phy:pdcch:ConnectedRuntimeMismatch');

% Production scheduler packing uses the actual K1 list index, not K1 itself.
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,31);
g=sixgr.link.resolveWaveformGrant(cfg,'DL',4,'Slot',31,'SFN',3);
parsed=sixgr.phy.pdcch.DCIParser.parse(g.DCI.Bits,dl);
assert(parsed.Fields.pdsch_to_harq_feedback_timing_slots==g.K1 && ...
    parsed.Fields.pdsch_to_harq_feedback_timing==find(dl.Data.DLDataToULACK==g.K1)-1);
assert(numel(g.DCI.Bits)==43 && parsed.Fields.timing_offset_slots==g.K0);
ok=true;
end

function parsed=localCheck(context,names,widths,values,expectedLength)
schema=sixgr.phy.pdcch.DCISchemaEngine.resolve(context);
assert(isequal([schema.Definitions.Name],names) && isequal([schema.Definitions.Width],widths));
assert(schema.RawBits==expectedLength);
fields=struct(); expected=int8([]);
for k=1:numel(names)
    fields.(names(k))=values(k);
    expected=[expected;int8(bitget(uint32(values(k)),widths(k):-1:1).')]; %#ok<AGROW>
end
packed=sixgr.phy.pdcch.DCIPacker.pack(fields,context);
assert(isequal(packed.Bits,expected));
parsed=sixgr.phy.pdcch.DCIParser.parse(expected,context);
end

function localReject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Expected %s, got %s: %s',id,ME.identifier,ME.message); return; end
error('test:MissingRejection','Expected %s.',id);
end
