function verifyCampaignSeedAuthority(report,expectedSeed)
% The configured master seed, not only MATLAB's global RNG, owns the run.
file=report.Reproducibility.SeedsCSV;
assert(isfile(file),'The campaign must retain its configured seed provenance.');
rows=readtable(file,'TextType','string');
for component=["global_campaign","e2e_probe"]
    selected=rows(string(rows.Component)==component,:);
    assert(height(selected)==1 && selected.Seed==expectedSeed && ...
        string(selected.SeedExpression)=="cfg.run.seed", ...
        'Configured seed authority mismatch for %s; changing rng alone is not a new PHY/channel seed.',component);
end
fprintf('CONFIGURED_CAMPAIGN_SEED_PASS: master=%d\n',expectedSeed);
end
