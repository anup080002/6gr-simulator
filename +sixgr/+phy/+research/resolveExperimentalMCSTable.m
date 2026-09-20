function definition=resolveExperimentalMCSTable(name)
% Explicit catalog-only lab codepoints. Unknown names have no definition.
definition=[];
name=lower(strtrim(string(name)));
if ~isscalar(name) || ~startsWith(name,"experimental_"), return; end
catalog=sixgr.lls6g.config.loadParameterCatalog('scenario');
tables=catalog.value_maps.experimental_mcs_tables;
hit=find(string({tables.name})==name);
if isempty(hit), return; end
assert(isscalar(hit),'sixgr:research:InvalidMCSTable','Experimental table names must be unique.');
t=tables(hit); indices=double(t.indices(:)); qm=double(t.qm(:)); rates=double(t.code_rates(:));
assert(string(t.research_class)=="optional_research_experiment" && ...
    ~isempty(indices) && numel(indices)==numel(qm) && numel(indices)==numel(rates) && ...
    numel(unique(indices))==numel(indices) && all(isfinite(indices) & indices==fix(indices) & indices>=0 & indices<=31) && ...
    all(ismember(qm,[2 4 6 8 10])) && all(isfinite(rates) & rates>0 & rates<1), ...
    'sixgr:research:InvalidMCSTable','Install unique 5-bit indices, square QAM and finite code rates in (0,1).');
definition=struct('Name',name,'ResearchClass',string(t.research_class), ...
    'StandardNR',false,'Rows',[indices qm rates]);
end
