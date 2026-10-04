function ok=testRAN1AI1032CorrectedAlt3Mapping()
%TESTRAN1AI1032CORRECTEDALT3MAPPING Exact six-bit study-table boundaries.
name="experimental_6gr_ai1032_alt3";
definition=sixgr.phy.research.resolveExperimentalMCSTable(name);
assert(~isempty(definition) && definition.IndexWidthBits==6 && ...
    size(definition.Rows,1)==32 && size(definition.ReservedRows,1)==5);
expected=sixgr.studies.ran1ai1032.MCSCatalog.alt3Extended();
assert(height(expected)==37 && isequal(expected.indication_index,(0:36)'));
assert(isequal(definition.ReservedRows,[28 2;29 4;30 6;31 8;36 10]));
for index=0:63
    row=expected(expected.indication_index==index,:);
    profile=sixgr.link.resolveMCSProfile(name,index);
    if isempty(row)
        assert(index>=37 && ~profile.Valid, ...
            'Unassigned six-bit codepoint must not schedule a TB.');
    elseif row.entry_kind=="stored_tbs"
        assert(~profile.Valid && ~row.new_TB_allowed && ...
            any(definition.ReservedRows(:,1)==index), ...
            'Reserved codepoint must require existing HARQ TB context.');
    else
        assert(profile.Valid && profile.Qm==row.Qm && ...
            abs(profile.TargetCodeRate-row.target_code_rate_x1024/1024)<1e-14, ...
            'Regular codepoint differs from the corrected TDoc meaning.');
    end
end
assert(~sixgr.link.resolveMCSProfile(name,31.5).Valid, ...
    'Fractional MCS indices must not round into a valid six-bit field.');
assert(expected.entry_id(expected.indication_index==27)=="B27" && ...
    expected.entry_id(expected.indication_index==32)=="H0" && ...
    expected.entry_id(expected.indication_index==35)=="H3");
% Exercise the configured, connected UL control bit field, not just an MCS
% lookup. The paired DL format remains the ordinary five-bit NR layout.
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_four_port_connected_research_ul_fixture.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
cfg.phy.pusch.mcsTable=char(name);
cfg.phy.pusch.experimentalMCSTable=definition;
ul=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg,'0_1');
dl=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg,'1_1');
ulSchema=sixgr.phy.pdcch.DCISchemaEngine.resolve(ul);
dlSchema=sixgr.phy.pdcch.DCISchemaEngine.resolve(dl);
legacy=cfg;
legacy.phy.pusch.mcsTable='experimental_square_qam_v1';
legacy.phy.pusch.experimentalMCSTable= ...
    sixgr.phy.research.resolveExperimentalMCSTable(legacy.phy.pusch.mcsTable);
legacyUL=sixgr.phy.pdcch.DCISchemaEngine.resolve( ...
    sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(legacy,'0_1'));
assert(ulSchema.Definitions([ulSchema.Definitions.Name]=="mcs").Width==6 && ...
    dlSchema.Definitions([dlSchema.Definitions.Name]=="mcs").Width==5 && ...
    ulSchema.SchemaVersion=="sixgr_research_connected_ul_6bit/v1" && ...
    ulSchema.RawBits==legacyUL.RawBits+1, ...
    'Corrected Alt-3 must add exactly one MCS bit to the affected UL DCI.');
for r=definition.ReservedRows.'
    storedProfile=sixgr.phy.pdcch.resolveConnectedMCS(cfg.phy.pusch,r(1));
    assert(~storedProfile.Valid && storedProfile.RequiresHARQHistory && ...
        storedProfile.Qm==r(2) && isnan(storedProfile.TargetCodeRate));
end
fields=struct();
for d=ulSchema.Definitions(:).'
    fields.(char(d.Name))=d.ValueMin;
end
fields.mcs=32;
encoded=sixgr.phy.pdcch.DCIPacker.pack(fields,ul);
decoded=sixgr.phy.pdcch.DCIParser.parse(encoded.Bits,ul);
assert(decoded.Fields.mcs==32 && numel(encoded.Bits)==ulSchema.RawBits && ...
    encoded.StandardProfile=="experimental_ul_mcs_with_nr_dci_layout" && ...
    decoded.StandardProfile=="experimental_mcs_with_nr_dci_layout");
fields.mcs=36;
reserved=sixgr.phy.pdcch.DCIPacker.pack(fields,ul);
reservedDecoded=sixgr.phy.pdcch.DCIParser.parse(reserved.Bits,ul);
reservedProfile=sixgr.phy.pdcch.resolveConnectedMCS(cfg.phy.pusch,36);
assert(reservedDecoded.Fields.mcs==36 && ~reservedProfile.Valid && ...
    reservedProfile.RequiresHARQHistory && reservedProfile.Qm==10);
fresh=cfg; fresh.phy.pusch.mcsIndex=36;
fresh.phy.pusch.modulation='1024QAM';
fresh.phy.pusch.codeRate=805.5/1024;
carrier=sixgr.phy.grid.makeCarrier(fresh);
localReject(@()sixgr.phy.research.configuredPUSCHTransport(fresh,carrier), ...
    'sixgr:research:StoredTBSHistoryRequired');
fields.mcs=37;
unassigned=sixgr.phy.pdcch.DCIPacker.pack(fields,ul);
localReject(@()sixgr.phy.pdcch.DCIParser.parse(unassigned.Bits,ul), ...
    'sixgr:phy:pdcch:field_out_of_range');
ok=true;
fprintf('RAN1_AI1032_CORRECTED_ALT3_MAPPING_PASS regular=32 reserved=5 unassigned=27\n');
end

function localReject(fn,id)
try
    fn();
catch ME
    assert(strcmp(ME.identifier,id),'Expected %s, got %s: %s',id,ME.identifier,ME.message);
    return;
end
error('test:MissingRejection','Expected %s.',id);
end
