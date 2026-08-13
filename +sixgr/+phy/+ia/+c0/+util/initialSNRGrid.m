function grid = initialSNRGrid(cfg)
%INITIALSNRGRID Include the configured coarse and high-SNR sanity points.
grid=unique([double(cfg.snr.coarse_grid_db(:).') ...
    double(cfg.statistics.high_snr_sanity_db)],"sorted");
end
