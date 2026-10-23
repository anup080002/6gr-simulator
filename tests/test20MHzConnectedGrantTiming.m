function ok=test20MHzConnectedGrantTiming()
% Production timing for the selected all-30-kHz n40 scenario, not PHY CRC.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
for slot0=[2 3 5 6 7 8]
    allocation=[0 14]; if mod(slot0,5)==3, allocation=[0 10]; end
    for rank=[1 2 4]
        grant=struct('Direction',"DL",'ControlAbsoluteSlot',slot0, ...
            'ControlSymbolAllocation',cfg.phy.pdcch.symbolAllocation, ...
            'SymbolAllocation',allocation,'PRBSet',0:50, ...
            'NumLayers',rank,'Modulation',"QPSK",'HARQProcess',0);
        decision=sixgr.phy.frame.TimingRelationEngine.resolveProductionGrant(cfg,grant);
        fprintf('SAME_SLOT_DL_TIMING slot0=%d rank=%d valid=%d reason=%s\n', ...
            slot0,rank,decision.Valid,decision.ReasonCode);
        assert(decision.Valid,'%s: %s',decision.ReasonCode,decision.Diagnostic);
        assert(decision.K0==0 && decision.DataAbsoluteSlot==slot0 && ...
            decision.HARQACKDecision.ProcessingBudget.N1Symbols==13);
        % Keep the real signed time overlap visible, not a fabricated zero.
        assert(decision.DataDecision.ProcessingGapTicks<0 && ...
            decision.DataDecision.MinimumProcessingTicks==0 && ...
            decision.DataDecision.BufferedSameSlotPDSCH);
    end
end
% Same-slot DL buffering must never exempt UL preparation or duplex checks.
ul=struct('Direction',"UL",'ControlAbsoluteSlot',0, ...
    'ControlSymbolAllocation',cfg.phy.pdcch.symbolAllocation, ...
    'SymbolAllocation',cfg.phy.pusch.symbolAllocation,'HARQProcess',0);
valid=sixgr.phy.frame.TimingRelationEngine.resolveProductionGrant(cfg,ul);
assert(valid.Valid && valid.DataAbsoluteSlot==4 && valid.K2==4);
ul.ControlAbsoluteSlot=1;
opposite=sixgr.phy.frame.TimingRelationEngine.resolveProductionGrant(cfg,ul);
assert(~opposite.Valid && contains(opposite.ReasonCode,'opposite_direction'));
ok=true; disp('20MHZ_CONNECTED_GRANT_TIMING_PASS');
end
