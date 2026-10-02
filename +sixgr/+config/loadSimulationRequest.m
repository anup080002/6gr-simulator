function request = loadSimulationRequest(configPath)
%LOADSIMULATIONREQUEST Shared YAML front door; execution scope is not PHY truth.
% LLS retains the existing ScenarioConfig. SLS supplies a native simulator
% config, optionally composed from explicit YAML/JSON native fragments.
[data, files] = localResolve(configPath, strings(0,1));
mode = upper(strtrim(string(sixgr.util.structGet(data,'run_control.execution_mode','LLS'))));
assert(isscalar(mode) && any(mode == ["LLS","SLS"]), ...
    'sixgr:simulation:InvalidMode','run_control.execution_mode must be LLS or SLS.');
request = struct('Mode',mode,'Data',data,'SourceFiles',files,'Config',struct());
if mode == "LLS"
    assert(~isfield(data,'sls'),'sixgr:simulation:ModeMismatch', ...
        'An sls configuration cannot execute as LLS; select execution_mode: SLS.');
    return
end
assert(isfield(data,'sls') && isstruct(data.sls) && isscalar(data.sls), ...
    'sixgr:simulation:MissingSLSConfig','SLS requires an sls mapping with native config fields.');
extra=setdiff(string(fieldnames(data)),["meta","run_control","sls"]);
assert(isempty(extra),'sixgr:simulation:ModeNamespace', ...
    'SLS physics/output parameters belong under sls.config, not ignored LLS root fields: %s',strjoin(extra,', '));
assert(all(ismember(string(fieldnames(data.sls)),["config","config_files"])), ...
    'sixgr:simulation:ModeNamespace','sls accepts only config and config_files.');
assert(isequal(string(fieldnames(data.run_control)),"execution_mode"), ...
    'sixgr:simulation:ModeNamespace','SLS run controls belong under sls.config.run; root run_control selects execution_mode only.');
native = struct();
fragmentPaths = string(sixgr.util.structGet(data,'sls.config_files',strings(0,1)));
for ref = fragmentPaths(:).'
    [fragment, source] = localResolve(localPath(configPath,ref),strings(0,1));
    native = sixgr.util.mergeStruct(native,fragment);
    files = [files; source]; %#ok<AGROW>
end
overlay = sixgr.util.structGet(data,'sls.config',struct());
assert(isstruct(overlay) && isscalar(overlay),'sixgr:simulation:BadSLSConfig', ...
    'sls.config must be a native simulator configuration mapping.');
native = sixgr.util.mergeStruct(native,overlay);
native = localDecodeNativeValues(native);
assert(isequal(sixgr.util.structGet(native,'run.useConfigFragments',[]),false), ...
    'sixgr:simulation:ImplicitFragments', ...
    'SLS requires sls.config.run.useConfigFragments=false; list fragments explicitly in sls.config_files.');
assert(string(sixgr.util.structGet(native,'run.mode','')) == "system", ...
    'sixgr:simulation:ModeMismatch','SLS requires sls.config.run.mode=system.');
backend = string(sixgr.util.structGet(native,'system.phyBackend',''));
assert(any(backend == ["waveform","calibrated_link_abstraction"]), ...
    'sixgr:simulation:MissingBackend', ...
    'Select sls.config.system.phyBackend: waveform or calibrated_link_abstraction.');
assert(~logical(sixgr.util.structGet(native,'system.linkAbstraction.allowDevelopmentFixtures',false)), ...
    'sixgr:simulation:DevelopmentCalibration', ...
    'The public SLS runner does not accept test-only BLER calibration. Use dedicated tests for fixtures.');
id = string(sixgr.util.structGet(data,'meta.scenario_id',''));
assert(isscalar(id) && ~isempty(regexp(char(id),'^[A-Za-z0-9][A-Za-z0-9_.-]*$','once')), ...
    'sixgr:simulation:ScenarioID','meta.scenario_id must be a safe nonempty folder identifier.');
% loadConfig also infers a preset from scenario.name/profile and injects
% preset policy (including waveform aliases). This public request already
% declared its fragments; do not silently apply a second scenario preset.
cfg=sixgr.util.mergeStruct(sixgr.config.defaultConfig(),native);
cfg=sixgr.config.normalizeConfig(cfg);
request.Config=sixgr.config.validateConfig(cfg);
request.Config.meta.scenarioID = char(id);
root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
files(end+1,1)=string(fullfile(root,'simulator','configs','schema','core_parameter_catalog.yaml'));
request.SourceFiles = unique(files,'stable');
end

function out=localDecodeNativeValues(value)
% Invert the existing JSON-safe complex matrix wire representation. Beam
% matrices must reach the scheduler as the exact numeric tensor, not a struct.
out=value;
if iscell(value)
    for k=1:numel(value), out{k}=localDecodeNativeValues(value{k}); end
elseif isstruct(value)
    if isscalar(value) && isfield(value,'json_type')
        assert(string(value.json_type)=="complex_array_split" && ...
            all(isfield(value,{'size','real','imag'})), ...
            'sixgr:simulation:NativeValueEncoding','Unsupported native config value encoding.');
        dims=double(value.size(:).');
        validateattributes(dims,{'double'},{'integer','nonnegative','finite','vector','nonempty'});
        assert(numel(dims)>=2 && isnumeric(value.real) && isnumeric(value.imag) && ...
            numel(value.real)==prod(dims) && numel(value.imag)==prod(dims) && ...
            all(isfinite(value.real(:))) && all(isfinite(value.imag(:))), ...
            'sixgr:simulation:NativeValueEncoding','Complex matrix size/data must agree and be finite.');
        out=complex(reshape(value.real,dims),reshape(value.imag,dims));
        return
    end
    names=fieldnames(value);
    for k=1:numel(value)
        for n=1:numel(names), out(k).(names{n})=localDecodeNativeValues(value(k).(names{n})); end
    end
end
end

function [data, files] = localResolve(path, stack)
path = string(java.io.File(char(path)).getCanonicalPath());
assert(~any(stack == path),'sixgr:simulation:InheritanceCycle','Configuration inheritance cycle: %s',path);
raw = sixgr.lls6g.config.readConfigFile(path);
if isfield(raw,'sls') && isstruct(raw.sls) && isfield(raw.sls,'config_files')
    refs=string(raw.sls.config_files);
    for k=1:numel(refs), refs(k)=localPath(path,refs(k)); end
    raw.sls.config_files=cellstr(refs);
end
parents = string(sixgr.util.structGet(raw,'inherits',strings(0,1)));
data = struct(); files = strings(0,1);
for ref = parents(:).'
    [parent, sources] = localResolve(localPath(path,ref),[stack;path]);
    data = sixgr.util.mergeStruct(data,parent); files = [files;sources]; %#ok<AGROW>
end
if isfield(raw,'inherits'), raw = rmfield(raw,'inherits'); end
data = sixgr.util.mergeStruct(data,raw); files = [files;path];
end

function path = localPath(owner, ref)
path = string(fullfile(fileparts(owner),ref));
if java.io.File(char(ref)).isAbsolute(), path=string(ref); end
if ~isfile(path) && isfile(ref), path=string(ref); end
end
