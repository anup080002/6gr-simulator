function ok=testDisabledPathlossTruthBoundary()
% Explicit no-pathloss LLS is not an unsupported active model or NR pathloss
% evidence. Strict active-model rejection remains required.
setup6GRSimToolkit('Verbose',false);
cfg=sixgr.config.defaultConfig();
cfg.channel.complianceMode="strict_38901";
cfg.channel.pathlossModel="none";
cfg.channel.pathloss.model="none";
cfg.channel.pathlossEnabled=false;
cfg.channel.shadowFadingEnabled=false;
cfg.channel.losEnabled=false;
model=sixgr.channel.TR38901Plus(cfg,'Seed',15);
[loss,~,e]=model.pathloss([0;0;25],[40 150;0 0;1.5 1.5]);
assert(isequal(loss,[0 0]) && ~e.pathlossEnabled && ~e.fallbackUsedForPathloss);
assert(string(e.pathlossExecutionBackend)=="disabled_by_configuration" && ...
    string(e.pathlossTruthClassification)=="not_applicable_pathloss_disabled" && ...
    string(e.pathlossComplianceStatus)=="not_applicable_pathloss_disabled" && ...
    string(e.pathlossModelSource)=="explicit_none_with_pathloss_disabled");
reject(@()model.pathloss([0;0;25],[40;0;1.5],'PathlossEnabled',true), ...
    'TR38901Plus:UnsupportedPathlossModel');
cfg.channel.pathlossEnabled=true;
reject(@()sixgr.channel.TR38901Plus(cfg),'TR38901Plus:StrictPathlossModel');
cfg.channel.pathlossEnabled=false; cfg.channel.pathlossModel="typo";
cfg.channel.pathloss.model="typo";
reject(@()sixgr.channel.TR38901Plus(cfg),'TR38901Plus:StrictPathlossModel');
cfg.channel.pathlossModel="ABG"; cfg.channel.pathloss.model="ABG";
reject(@()sixgr.channel.TR38901Plus(cfg),'TR38901Plus:StrictPathlossModel');
ok=true;
fprintf('PASS testDisabledPathlossTruthBoundary: explicit disabled none; active/unknown/ABG guards retained\n');
end

function reject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s.',id,cause.identifier); return;
end
error('test:MissingPathlossRejection','Expected %s.',id);
end
