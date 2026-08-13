function ok=testPDCCHTDoc10521Core
%TESTPDCCHTDOC10521CORE Dedicated exact/config PDCCH TDoc checks.
setup6GRSimToolkit("Verbose",false);
c=sixgr.phy.pdcch.tdoc.loadCampaignConfig( ...
    "simulator/configs/pdcch_tdoc10521/master.yaml");
assert(c.Config.strict_mode&&c.Config.output.png_only);
a=sixgr.phy.pdcch.tdoc.AnalyticalSuite.run(c.Config);
assert(all(a.Acceptance.Pass));
assert(height(sixgr.phy.pdcch.tdoc.ScenarioRegistry.catalog())==39);
assert(height(sixgr.phy.pdcch.tdoc.ScenarioRegistry.figures())==15);
ok=true;fprintf("PDCCH TDoc 10.5.2.1 core checks: PASS\n");
end
