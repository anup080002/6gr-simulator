function ok=testParameterCatalogCacheRefresh()
% Copy the actual loader into an isolated namespace. Never rewrite the
% repository catalogs while another MATLAB runtime owns a frozen scenario.
root=tempname; mkdir(root);
loaderDir=fullfile(root,'+sixgrCatalogCacheFixture','+lls6g','+config'); mkdir(loaderDir);
schemaDir=fullfile(root,'simulator','configs','schema'); mkdir(schemaDir);
copyfile(which('sixgr.lls6g.config.loadParameterCatalog'),fullfile(loaderDir,'loadParameterCatalog.m'));
addpath(root); cleanup=onCleanup(@()localCleanup(root)); %#ok<NASGU>
base=fullfile(schemaDir,'scenario_parameter_catalog.yaml');
overlay=fullfile(schemaDir,'scenario_parameter_catalog_extension_01.yaml');
matrix=fullfile(schemaDir,'matrix_parameter_catalog.yaml');
write(base,'{"sections":{"base":{"parameters":{"alpha":1}}},"top_level_order":["base"]}');
write(matrix,'{"sections":{"matrix":{"parameters":{"alpha":1}}}}');
loadCatalog=@sixgrCatalogCacheFixture.lls6g.config.loadParameterCatalog;
a=loadCatalog('scenario'); assert(a.sections.base.parameters.alpha==1);
assert(isequal(a,loadCatalog('scenario')),'Warm lookup must retain exact policy.');
% Overlay creation must invalidate a previously populated cache.
first='{"sections":{"probe":{"parameters":{"alpha":1}}},"top_level_order":["probe"]}';
write(overlay,first);
b=loadCatalog('scenario'); assert(b.sections.probe.parameters.alpha==1);
assert(isequal(string(b.top_level_order(:)),["base";"probe"]));
% Same bytes count and restored modification time: content is authority.
stamp=java.io.File(overlay).lastModified();
write(overlay,strrep(first,'"alpha":1','"alpha":2'));
java.io.File(overlay).setLastModified(stamp);
c=loadCatalog('scenario'); assert(c.sections.probe.parameters.alpha==2);
write(base,'{"sections":{"base":{"parameters":{"alpha":3}}},"top_level_order":["base"]}');
c=loadCatalog('scenario');
assert(c.sections.base.parameters.alpha==3 && c.sections.probe.parameters.alpha==2);
% Independent matrix cache must refresh too; scenario cache cannot mask it.
m=loadCatalog('matrix'); assert(m.sections.matrix.parameters.alpha==1);
write(matrix,'{"sections":{"matrix":{"parameters":{"alpha":2}}}}');
m=loadCatalog('matrix'); assert(m.sections.matrix.parameters.alpha==2);
% A present invalid overlay must throw, not return the last good catalog.
write(overlay,'[1,2,3]'); failed=false;
try, loadCatalog('scenario'); catch ME
    assert(strcmp(ME.identifier,'sixgr:lls6g:config:BadTopLevel')); failed=true;
end
assert(failed,'Invalid changed catalogs must not be hidden by the cache.');
delete(overlay);
d=loadCatalog('scenario'); assert(~isfield(d.sections,'probe'));
fprintf('PARAMETER_CATALOG_CACHE_REFRESH_PASS base_overlay_matrix_presence_and_same_size_content=1\n');
ok=true;
end
function write(path,text)
fid=fopen(path,'w'); assert(fid>=0); closer=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s',text);
end
function localCleanup(root)
rmpath(root);
% root is the unique directory created by this test, never a repository.
if isfolder(root), rmdir(root,'s'); end
end
