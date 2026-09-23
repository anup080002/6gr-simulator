function ok = testLegacyOLLADbMarginMapping(decisionFcn)
% Legacy ILLA smoothing must not change the units of shared HARQ OLLA.
if nargin < 1
    decisionFcn = @sixgr.link.computeLinkAdaptationDecision;
end
setup6GRSimToolkit('Verbose',false);
cfg = sixgr.config.defaultConfig();
cfg.phy.linkAdaptation.mode = 'amc';
cfg.phy.linkAdaptation.dlPolicy = 'cqi';
cfg.phy.linkAdaptation.ulPolicy = 'cqi';
cfg.phy.linkAdaptation.domain = 'legacy_mcs';
cfg.phy.linkAdaptation.dlDomain = 'legacy_mcs';
cfg.phy.linkAdaptation.ulDomain = 'legacy_mcs';
cfg.phy.linkAdaptation.outerLoopFlag = true;
cfg.phy.linkAdaptation.deltaMCSPolicy = 'olla';
cfg.phy.linkAdaptation.ollaStepDown = 0.9;
cfg.phy.linkAdaptation.ollaStepUp = 0.1;
cfg.phy.linkAdaptation.ollaMarginMinDb = -10;
cfg.phy.linkAdaptation.ollaMarginMaxDb = 10;
cfg.phy.pdsch.mcsTable = 'qam64_table1';
cfg.phy.pusch.mcsTable = 'qam64_table1';
cfg.phy.csi.cqiTable = 'table1';
for direction = ["DL","UL"]
    metrics = struct('CQI',12,'RI',1);
    [initial,state] = decisionFcn(cfg,direction,metrics);
    assert(initial.Valid,'Legacy regression needs a valid initial decision.');
    feedback = struct('Ack',false,'RV',0,'IsRetransmission',false);
    for k = 1:6
        [state,event] = sixgr.link.updateOLLAStateFromHARQFeedback( ...
            cfg,direction,feedback,state);
        assert(event.Eligible);
    end
    assert(abs(state.DeltaMCS + 5.4) < 1e-12);
    [decision,after] = decisionFcn( ...
        cfg,direction,metrics,'AdaptationState',state);
    expected = sixgr.link.applyOLLADeltaDbToMCSIndex( ...
        decision.CQIBasedMCS,state.DeltaMCS,decision.MCSTable, ...
        decision.CQITable,direction,'Config',cfg);
    fprintf('LEGACY_OLLA %s actual=%g expected_db_mapping=%g delta_db=%g\n', ...
        direction,decision.MCSIndex,expected,state.DeltaMCS);
    assert(decision.MCSIndex == expected, ...
        'test:LegacyOLLADbUsedAsIndex', ...
        'Legacy ILLA must not add the shared OLLA dB margin directly to MCS.');
    assert(after.OLLAUpdateCount == state.OLLAUpdateCount && ...
        after.DeltaMCS == state.DeltaMCS, ...
        'A CSI-only decision must not update or rewrite HARQ OLLA state.');
    assert(string(decision.OLLADomain) == 'delta_db_required_sinr_margin');
    assert(isfinite(decision.OLLABaseRequiredSINR_dB) && ...
        isfinite(decision.OLLATargetRequiredSINR_dB));
end
ok = true;
end
