function ok=testType0PlannedRECount()
% Configuration-only count/coordinate closure; never runtime occupancy.
setup6GRSimToolkit('Verbose',false);
paths=["lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml", ...
    "h4_100_cdlc100_connected_impaired_40db_adaptation.yaml"];
for path=paths
    scenario=sixgr.lls6g.config.loadScenarioConfig( ...
        fullfile('simulator','configs','scenarios',path));
    cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
    for scope=["selected_ssb_occasion","all_active_ssb_occasions"]
        cfg.phy.sib1.transmissionScope=scope;
        [rows,checks]=sixgr.truth.buildPlannedREAllocation(cfg,'TargetChannels','TYPE0_PDCCH');
        sixgr.truth.assertAllocationPreflight(checks);
        rows=rows(rows.channel=="TYPE0_PDCCH",:);
        check=checks(checks.feature=="TYPE0_PDCCH",:);
        carrier=sixgr.phy.grid.makeCarrier(cfg);
        indices=sixgr.phy.broadcast.resolveSIB1TransmitSSBIndices(cfg);
        expectedCount=0;
        for beam=indices
            carrier=sixgr.phy.grid.makeCarrier(cfg);
            child=cfg; child.phy.sib1.transmissionScope="selected_ssb_occasion";
            child.phy.ssb.runtimeSSBIndex=beam;
            mib=struct('PDCCHConfigSIB1',child.phy.mib.pdcchConfigSIB1, ...
                'DMRSTypeAPosition',child.phy.mib.dmrsTypeAPosition, ...
                'SSBSubcarrierOffset',sixgr.util.structGet(child,'phy.ssb.kSSB',0), ...
                'SSBIndex',beam,'Source',"configured_MIB_bits_preflight");
            resolution=sixgr.phy.broadcast.deriveType0PDCCHFromMIB(carrier,child,mib,'RNTI',65535);
            slots=unique(double(resolution.MonitoringOccasions.AbsoluteSlot));
            slots=slots(slots>=0 & slots<cfg.run.totalSlots);
            for slot=reshape(slots,1,[])
                carrier.NFrame=floor(slot/carrier.SlotsPerFrame);
                carrier.NSlot=mod(slot,carrier.SlotsPerFrame);
                native=sixgr.phy.frame.ChannelAllocationMaterializer.materializePDCCH( ...
                    carrier,resolution.PDCCH,'AbsoluteSlot',slot);
                match=rows.absolute_slot==slot;
                if numel(indices)>1
                    match=match & endsWith(rows.allocation_id,"_ssb_"+beam);
                end
                selected=rows(match,:); coordinates=zeros(0,3);
                for k=1:height(selected)
                    sc=selected.subcarrier_start(k)+(0:selected.subcarrier_count(k)-1).';
                    coordinates=[coordinates;sc,repmat( ...
                        [selected.symbol_index(k),selected.port_index(k)],numel(sc),1)]; %#ok<AGROW>
                end
                assert(isequal(sortrows(coordinates),sortrows(native.ActualCoordinates0Based)), ...
                    'Configured Type-0 RE coordinates must equal native data AND DM-RS allocation.');
                expectedCount=expectedCount+size(native.ActualCoordinates0Based,1);
            end
        end
        assert(expectedCount==sum(rows.re_count) && check.exact_re_count==expectedCount, ...
            'test:Type0RECount','Count actual resource elements, not allocation identities.');
        assert(all(rows.evidence_scope=="planned_config_not_runtime_observation"));
        fprintf('TYPE0_PLANNED_RE_COUNT_PASS scenario=%s scope=%s beams=%d RE=%d allocations=%d\n', ...
            path,scope,numel(indices),expectedCount,numel(unique(rows.allocation_id)));
    end
end
ok=true;
end
