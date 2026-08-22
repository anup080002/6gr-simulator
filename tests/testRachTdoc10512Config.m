function ok=testRachTdoc10512Config()
%TESTRACHTDOC10512CONFIG Validate reusable YAML-owned campaign profiles.
setup6GRSimToolkit("Verbose",false,"RunToolboxChecks",false);
root=fullfile("simulator","configs","rach_tdoc10512");
smoke=sixgr.rach.tdoc10512.buildRACHTDocStudyConfig(fullfile(root,"campaign_smoke.yaml"));
assert(smoke.Mode=="smoke");
assert(double(smoke.Resolved.random_access.statistical_qualification.minimum_trials)==100);
assert(double(smoke.Resolved.random_access.statistical_qualification.minimum_detection_trials)==100);
assert(string(smoke.Resolved.random_access.prach_format)=="B4");
assert(string(smoke.Resolved.random_access.channel_model)=="TDL-C");
assert(~logical(smoke.Resolved.tdoc10512.output.save_svg));
assert(logical(smoke.Resolved.tdoc10512.output.save_png));

analytical=sixgr.rach.tdoc10512.buildRACHTDocStudyConfig(fullfile(root,"campaign_analytical.yaml"));
assert(analytical.Mode=="analytical");
core=sixgr.rach.tdoc10512.buildRACHTDocStudyConfig(fullfile(root,"campaign_core.yaml"));
assert(core.Mode=="core_lls");
engineering=sixgr.rach.tdoc10512.buildRACHTDocStudyConfig(fullfile(root,"campaign_engineering.yaml"));
assert(engineering.Mode=="engineering_lls");
assert(double(core.Resolved.random_access.statistical_qualification.minimum_trials)>=1e6);

bad=smoke.Resolved; bad.tdoc10512.output.save_svg=true;
localExpect(@()sixgr.rach.tdoc10512.validateRACHTDocStudyConfig(bad), ...
    "sixgr:rach:tdoc10512:SVGForbidden");
bad=smoke.Resolved;
if iscell(bad.tdoc10512.scenarios)
    bad.tdoc10512.scenarios{end}.waveform_eligible=true;
else
    bad.tdoc10512.scenarios(end).waveform_eligible=true;
end
localExpect(@()sixgr.rach.tdoc10512.validateRACHTDocStudyConfig(bad), ...
    "sixgr:rach:tdoc10512:ATGCalibrationRequired");
ok=true;
fprintf('testRachTdoc10512Config: PASS\n');
end

function localExpect(f,id)
try
    f(); error("testRachTdoc10512Config:MissingError","Expected %s.",id);
catch ME
    assert(string(ME.identifier)==string(id),"Unexpected error: %s",ME.identifier);
end
end
