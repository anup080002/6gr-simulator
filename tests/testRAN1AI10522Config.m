function ok = testRAN1AI10522Config()
%TESTRAN1AI10522CONFIG Canonical YAML/schema/hash and fail-closed checks.
setup6GRSimToolkit("Verbose",false);
files=dir(fullfile("simulator","configs","scenarios","*ran1_10522*.yaml"));
assert(numel(files)==15,"Expected all 15 WebGUI-visible study scenarios.");
hashes=strings(numel(files),1);
for k=1:numel(files)
    path=fullfile(files(k).folder,files(k).name);
    [cfg,provenance,scfg]=sixgr.studies.ran1ai10522.loadStudyConfig(path);
    assert(string(cfg.study.schema_version)=="sixgr.ran1.10_5_2_2/v1");
    assert(logical(cfg.study.strict)&&logical(cfg.study.prohibit_fallback));
    assert(provenance.ConfigSHA256==string(scfg.ConfigHash));
    assert(strlength(provenance.ParameterContractSHA256)==64);
    hashes(k)=provenance.ConfigSHA256;
end
assert(numel(unique(hashes))==15,"Each scenario must have a distinct resolved hash.");
base=cfg; base.pdschDmrsStudy.timeDomain.noImplicitShift=false;
localAssertId(@()sixgr.studies.ran1ai10522.validateStudyConfig(base), ...
    "sixgr:ran1ai10522:InvalidTimeDomainPolicy");
base=cfg; base.study.prohibit_fallback=false;
localAssertId(@()sixgr.studies.ran1ai10522.validateStudyConfig(base), ...
    "sixgr:ran1ai10522:StrictModeRequired");
fprintf("RAN1 10.5.2.2 config: 15/15 canonical YAMLs and 2/2 negative guards pass.\n");
ok=true;
end

function localAssertId(f,id)
try, f(); error("test:ExpectedError","Expected %s.",id);
catch ME, assert(string(ME.identifier)==id,"Expected %s, got %s.",id,ME.identifier); end
end
