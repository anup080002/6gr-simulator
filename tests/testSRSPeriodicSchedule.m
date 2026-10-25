function ok = testSRSPeriodicSchedule()
setup6GRSimToolkit("Verbose", false);
s=sixgr.lls6g.config.loadScenarioConfig('configs/lls/lls_srs_strict_mini_anchor.yaml');
internal=sixgr.lls6g.buildInternalConfig(s,tempname);
strict=sixgr.phy.srs.buildSRSConfigFromScenario(internal);
T = sixgr.phy.srs.validateSRSPeriodicSchedule(strict);
assert(height(T) >= 2 && all(T.ExpectedOccasion) && all(T.NativeMappingOccasion) && ...
    all(isnan(T.ObservedOccasion)) && all(T.TruthStatus=="configured_native_resource_mapping_not_received_evidence"), ...
    "Native mapped occasions must not be copied into observed receiver evidence.");
% Deliberately different native calendar must expose a mapping disagreement.
wrong=strict; wrong.ToolboxSRS.SRSPeriod=[4 1];
disagreement=sixgr.phy.srs.validateSRSPeriodicSchedule(wrong);
assert(all(disagreement.ExpectedOccasion) && ~any(disagreement.NativeMappingOccasion) && ...
    all(isnan(disagreement.ObservedOccasion)));

cfg = struct();
% A single physical resource sounding every fifth slot uses period5/offset4,
% not four incompatible phases of a period20 native resource.
cfg = sixgr.util.structSet(cfg, "phy.srs.slotWithinPeriod1Based", 5);
cfg.phy.srs.period_slots=5; cfg.phy.srs.period_offset=4;
assert(~sixgr.truth.coupledSRSResourceOpportunity(cfg, 9, 1, 2, 5, "multiplex_due_users", 2), ...
    "Coupled SRS multiplexing must not turn a non-SRS slot into an SRS occasion.");
assert(sixgr.truth.coupledSRSResourceOpportunity(cfg, 10, 1, 2, 5, "multiplex_due_users", 2) && ...
    sixgr.truth.coupledSRSResourceOpportunity(cfg, 10, 2, 2, 5, "multiplex_due_users", 2), ...
    "Coupled SRS multiplexing must allow both UEs on a configured SRS occasion.");

cfg.phy.srs.slotWithinPeriod1Based = 1;
cfg.phy.srs.period_slots=1; cfg.phy.srs.period_offset=0;
assert(sixgr.truth.coupledSRSResourceOpportunity(cfg, 1, 1, 2, 1, "round_robin_phase", 1) && ...
    ~sixgr.truth.coupledSRSResourceOpportunity(cfg, 1, 2, 2, 1, "round_robin_phase", 1) && ...
    ~sixgr.truth.coupledSRSResourceOpportunity(cfg, 2, 1, 2, 1, "round_robin_phase", 1) && ...
    sixgr.truth.coupledSRSResourceOpportunity(cfg, 2, 2, 2, 1, "round_robin_phase", 1), ...
    "Repeated single-occasion SRS periods must rotate across UEs by absolute occasion ordinal.");
ok = true;
end
