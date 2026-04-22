function plan = PDSCHRepetition(cfg)
%PDSCHRepetition Materialize repeated-copy scheduling for truthful studies.

plan = sixgr.pdsch.TDRAAllocator(cfg.TDRA, ...
    "RepetitionMode", cfg.RepetitionMode, ...
    "RepetitionCount", cfg.RepetitionCount);
plan.Mode = cfg.RepetitionMode;
plan.Count = cfg.RepetitionCount;
plan.CombiningMode = "llr_sum_if_same_length_else_not_materialized";
end

