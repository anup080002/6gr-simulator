function grid = refinementSNRGrid(cfg,crossingSNRDB)
%REFINEMENTSNRGRID Return a canonical globally aligned refinement grid.
step=double(cfg.snr.refinement_step_db);
span=double(cfg.snr.refinement_half_span_db);
start=ceil((double(crossingSNRDB)-span)/step)*step;
stop=floor((double(crossingSNRDB)+span)/step)*step;
grid=start:step:stop;
grid=grid(grid>=double(cfg.snr.minimum_db)& ...
    grid<=double(cfg.snr.maximum_db));
grid=unique(round(grid,10),"sorted");
end
