function ok=testScenarioAliasDefaultsCacheRefresh()
% Exercise the actual normalizer in an isolated namespace; never edit live defaults.
root=tempname; mkdir(root);
loaderDir=fullfile(root,'+sixgrAliasCacheFixture','+lls6g','+config'); mkdir(loaderDir);
defaultsDir=fullfile(root,'simulator','configs','defaults'); mkdir(defaultsDir);
copyfile(which('sixgr.lls6g.config.normalizeScenarioAliases'), ...
    fullfile(loaderDir,'normalizeScenarioAliases.m'));
addpath(root); cleanup=onCleanup(@()localCleanup(root)); %#ok<NASGU>
names={'top_level_required_sections_01.yaml','top_level_required_sections_02.yaml', ...
    'top_level_required_sections_03.yaml','processing_chains.yaml','global.yaml'};
for k=1:numel(names), localWrite(fullfile(defaultsDir,names{k}),'{}'); end
modern=fullfile(defaultsDir,names{1}); legacy=fullfile(defaultsDir,names{5});
localWrite(modern,'{"run_control":{"seed":11}}');
localWrite(legacy,'{"simulation":{"random_seed":11}}');
normalize=@sixgrAliasCacheFixture.lls6g.config.normalizeScenarioAliases;
cfg.frequency.duplex_mode='TDD'; cfg.run_control.seed=12; cfg.simulation.random_seed=13;
a=normalize(cfg); assert(a.run_control.seed==12 && a.simulation.random_seed==12);
assert(isequaln(a,normalize(cfg)),'Unchanged defaults must preserve warm-session behavior.');
% Same length and restored mtime: the content, not metadata, must invalidate.
stamp=java.io.File(modern).lastModified();
localWrite(modern,'{"run_control":{"seed":12}}'); java.io.File(modern).setLastModified(stamp);
b=normalize(cfg);
assert(b.run_control.seed==13 && b.simulation.random_seed==13, ...
    'test:StaleModernAliasDefaults','Changed modern defaults were ignored in the warm session.');
stamp=java.io.File(legacy).lastModified();
localWrite(legacy,'{"simulation":{"random_seed":13}}'); java.io.File(legacy).setLastModified(stamp);
c=normalize(cfg);
assert(c.run_control.seed==12 && c.simulation.random_seed==13, ...
    'test:StaleLegacyAliasDefaults','Changed legacy defaults were ignored in the warm session.');
% A later defaults layer must invalidate and retain merge precedence.
overlay=fullfile(defaultsDir,names{4});
localWrite(overlay,'{"run_control":{"seed":11}}');
d=normalize(cfg); assert(d.simulation.random_seed==12);
localWrite(overlay,'[1,2,3]'); failed=false;
try, normalize(cfg); catch ME
    assert(strcmp(ME.identifier,'sixgr:lls6g:config:BadTopLevel')); failed=true;
end
assert(failed,'Malformed changed defaults must not return a stale good configuration.');
localWrite(overlay,'{}'); assert(isequaln(c,normalize(cfg)));
delete(legacy); failed=false;
try, normalize(cfg); catch, failed=true; end
assert(failed,'A deleted required defaults file must not be hidden by the cache.');
localWrite(legacy,'{"simulation":{"random_seed":13}}');
assert(isequaln(c,normalize(cfg)),'Restored defaults must recover without an engine restart.');
fprintf('SCENARIO_ALIAS_DEFAULTS_CACHE_REFRESH_PASS modern_legacy_overlay_content_and_invalid_inputs=1\n');
ok=true;
end
function localWrite(path,content)
fid=fopen(path,'w'); assert(fid>=0); cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s',content);
end
function localCleanup(root)
rmpath(root);
% Only the unique directory created above belongs to this test.
if isfolder(root), rmdir(root,'s'); end
end
