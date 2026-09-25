function ok = test5MHzSaturatedTrafficConfiguration()
% Verify actual generated arrivals, not the full_buffer label alone.
setup6GRSimToolkit('Verbose',false);
root = fullfile('simulator','configs','scenarios');
base = sixgr.lls6g.config.loadScenarioConfig(fullfile(root, ...
    'lls_tdd_5mhz_rank2_shared_awgn_20db.yaml'));
source = sixgr.lls6g.config.loadScenarioConfig(fullfile(root, ...
    'lls_tdd_5mhz_rank2_shared_awgn_20db_saturated.yaml'));
cfg = sixgr.lls6g.buildInternalConfig(source,tempname);
baseline = sixgr.lls6g.buildInternalConfig(base,tempname);
% The sole radio policy change releases the permanent frequency pool;
% physical PUCCH/PDCCH/CSI/SRS and per-occasion overlap checks stay enabled.
assert(source.get('users.n_users') == 1);
assert(baseline.phy.pucch.reserveConfiguredPRBsFromPUSCH);
assert(~cfg.phy.pucch.reserveConfiguredPRBsFromPUSCH);
assert(cfg.phy.pucch.detectPUCCHPUSCHOverlap && cfg.phy.pucch.uciOnPUSCHEnabled);
assert(string(cfg.phy.pucch.unsupportedOverlapPolicy) == "reject_before_waveform");
expectedPHY = baseline.phy;
expectedPHY.pucch.reserveConfiguredPRBsFromPUSCH = false;
assert(isequaln(cfg.phy,expectedPHY));
assert(isequaln(cfg.channel,baseline.channel));
expectedMAC = baseline.mac;
expectedMAC.scheduler.minPRBPerUE = 2;
assert(isequaln(cfg.mac,expectedMAC));
assert(source.get('scheduler.min_prbs_per_grant')==2);
slotSeconds = 1e-3/(double(cfg.phy.numerology.scs_kHz)/15);
assert(cfg.phy.carrier.NSizeGrid == 25 && slotSeconds == 1e-3);
assert(isequal(cfg.phy.pdcch.searchSpace.numCandidates,[4 2 2 1 0]), ...
    'Shared DL/UL control requires the installed pair of AL4 candidates.');
assert(cfg.phy.pdcch.blindDecodeCandidates==sum(cfg.phy.pdcch.searchSpace.numCandidates));
traffic = sixgr.system.TrafficFactory.generate(cfg,1,58,slotSeconds);
assert(all(traffic.OfferedBitsDL(:) == 100e6*slotSeconds));
assert(all(traffic.OfferedBitsUL(:) == 100e6*slotSeconds));
assert(cfg.phy.pdsch.maxLayers == 2 && cfg.phy.pusch.maxLayers == 2);
assert(string(cfg.phy.pdsch.mcsTable) == "qam64_table1" && ...
    string(cfg.phy.pusch.mcsTable) == "qam64_table1");
% Upper bound counts every RE as data at unit coding rate, including
% control/DM-RS/guard symbols. Actual service cannot exceed this bound.
rawSlotBound = 25*12*14*2*6;
assert(all(traffic.OfferedBitsDL(:) > rawSlotBound) && ...
    all(traffic.OfferedBitsUL(:) > rawSlotBound));
% Exercise the actual budget producer and contiguous allocation primitive.
% This proves schedulable PRBs, not execution or delivered throughput.
state = struct('CfgMobility',cfg,'SymbolsPerSlot',14,'NumRB',25, ...
    'CurrentSlot',5,'CurrentDirection','UL', ...
    'TimingControlAbsoluteSlot0Based',3,'CurrentSlotULSymbolStart',0, ...
    'CurrentSlotULNumSymbols',14,'ControlGating',struct('PDCCHRequired',false));
budget = sixgr.truth.CoupledTruthRuntime.configuredSlotBudgetRuntime(state);
assert(isempty(budget.ReservedPUCCHPRBSet) && isequal(budget.PRBSet,0:24));
chunk = sixgr.l2.mac.contiguousPRBChunk(budget.PRBSet,1,25,4);
assert(isequal(chunk,0:24));
state.CfgMobility = baseline;
old = sixgr.truth.CoupledTruthRuntime.configuredSlotBudgetRuntime(state);
assert(isequal(old.ReservedPUCCHPRBSet,[0 4 5]));
assert(isequal(sixgr.l2.mac.contiguousPRBChunk(old.PRBSet,1,25,4),6:24));
sweep = sixgr.lls6g.config.loadScenarioConfig(fullfile(root, ...
    'lls_tdd_5mhz_rank2_shared_awgn_snr_sweep_saturated.yaml'));
assert(string(sweep.get('scenario.runner_profile')) == "generic_sweep");
overrides = sweep.get('scenario.sweep.overrides');
assert(isequal(arrayfun(@(v) v.config.simulation.snr_db,overrides(:)).', ...
    [-30 -20 -10 0 10 20 30 40]));
assert(sweep.get('traffic.targetRate_Mbps') == 200);
sweepCandidates=double(sweep.get('control.search_space_num_candidates'));
assert(isequal(sweepCandidates(:).',[4 2 2 1 0]), ...
    'The eight-point sweep must inherit the repaired 5 MHz search space; got %s.', ...
    mat2str(sweepCandidates));
assert(sweep.get('control.blind_decode_candidates')==sum(sweepCandidates));
assert(sweep.get('scheduler.min_prbs_per_grant') == 2);
assert(~sweep.get('pucch_resources.overlap_policy.reserve_configured_pucch_prbs_from_pusch'));
assert(sweep.get('pucch_resources.overlap_policy.detect_pucch_pusch_overlap') && ...
    sweep.get('pucch_resources.overlap_policy.uci_on_pusch_enabled'));
fprintf('SATURATED_5MHZ DL=100Mbps UL=100Mbps raw_rate_one_bound=%.3fMbps points=8 contiguous_UL_PRBs=25 physical_controls_retained=1\n', ...
    rawSlotBound/slotSeconds/1e6);
ok = true;
end
