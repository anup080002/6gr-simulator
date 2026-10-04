function ok = testSchedulerComplexConfigCache()
% Complex beam configuration must not collapse distinct DM-RS/TBS keys.
setup6GRSimToolkit('Verbose',false);
for direction = ["DL", "UL"]
    cfg = sixgr.config.defaultConfig();
    cfg = withCanonicalSchedulerTiming(cfg);
    cfg.mac.scheduler.fastNREApprox = false;
    cfg.mac.scheduler.tbsMode = 'faithful';
    if direction == "DL", root = 'phy.pdsch'; else, root = 'phy.pusch'; end
    cfg = sixgr.util.structSet(cfg, root + ".enablePTRS", false);
    cfg = sixgr.util.structSet(cfg, root + ".transformPrecoding", false);
    cfg = sixgr.util.structSet(cfg, root + ".mappingType", 'A');
    cfg = sixgr.util.structSet(cfg, root + ".dmrs.additionalPositions", 0);
    cfg = sixgr.util.structSet(cfg, root + ".dmrs.configurationType", 1);
    cfg = sixgr.util.structSet(cfg, root + ".dmrs.scheduledPortSet", 0);
    cfg = sixgr.util.structSet(cfg, root + ".dmrs.availablePortSet", 0);
    cfg = sixgr.util.structSet(cfg, root + ".xOverhead", 0);
    cfg = sixgr.util.structSet(cfg, root + ".precoding.W", 1i);
    carrier = sixgr.phy.grid.makeCarrier(cfg);
    counts = zeros(1,4);
    % Revisit both configurations: hits must be as correct as cold misses.
    groups = [1 2 1 2];
    for k = 1:numel(groups)
        current = sixgr.util.structSet(cfg, root + ".dmrs.numCDMGroupsWithoutData", groups(k));
        scheduler = sixgr.l2.mac.SchedulerPF(current, 'Direction', direction);
        [bits,~,counts(k)] = scheduler.estimateTBS('QPSK',1,25,[2 12],0.3, ...
            'ForceExact',true,'ConfigOverride',current);
        % Independent native allocation, not DUT echoed ResourceAccounting.
        if direction == "DL", native = nrPDSCHConfig; else, native = nrPUSCHConfig; end
        native.PRBSet = 0:24;
        native.SymbolAllocation = [2 12];
        native.MappingType = 'A'; native.Modulation = 'QPSK'; native.NumLayers = 1;
        native.DMRS.DMRSConfigurationType = 1;
        native.DMRS.DMRSTypeAPosition = 2;
        native.DMRS.DMRSAdditionalPosition = 0;
        native.DMRS.DMRSPortSet = 0;
        native.DMRS.NumCDMGroupsWithoutData = groups(k);
        if direction == "DL"
            [~,reference] = nrPDSCHIndices(carrier,native);
        else
            native.TransformPrecoding = false;
            [~,reference] = nrPUSCHIndices(carrier,native);
        end
        expected = nrTBS('QPSK',1,25,reference.NREPerPRB,0.3,0);
        assert(counts(k) == reference.NREPerPRB && bits == expected, ...
            'sixgr:test:SchedulerComplexCacheCollision', ...
            '%s CDM=%g reused wrong TBS/NRE: NRE=%g expected=%g.', ...
            direction,groups(k),counts(k),reference.NREPerPRB);
    end
    assert(counts(1) ~= counts(2) && isequal(counts(1:2),counts(3:4)));
end
ok = true;
end
