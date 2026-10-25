classdef PUCCHPowerAuthority
    %PUCCHPOWERAUTHORITY Last-authored aliases for configured PUCCH terms.
    % The installed PUCCH resource owns DeltaF and the static adjustment g.
    % These aliases do not create a received-TPC loop or an RF PCMAX model.
    methods (Static)
        function out=merge(out,authored)
            arguments
                out (1,1) struct
                authored (1,1) struct
            end
            if isempty(fieldnames(out)), out=emptyAuthority(); end
            validateAuthority(out);
            retained=isfield(authored,'ContractVersion');
            if retained, validateAuthority(authored); end
            [names,paths]=pairs();
            for k=1:numel(names)
                name=names(k);
                if retained
                    if isfield(authored.Values,name), out.Values.(name)=authored.Values.(name); end
                else
                    [value,present]=readPair(authored,name,paths(k,:));
                    if present, out.Values.(name)=value; end
                end
            end
        end

        function cfg=apply(cfg,authority)
            arguments
                cfg (1,1) struct
                authority (1,1) struct = struct()
            end
            if isempty(fieldnames(authority)), authority=emptyAuthority(); end
            validateAuthority(authority);
            [names,paths]=pairs();
            for k=1:numel(names)
                name=names(k);
                if isfield(authority.Values,name)
                    value=authority.Values.(name); present=true;
                else
                    [value,present]=readPair(cfg,name,paths(k,:));
                end
                if ~present, continue; end
                for path=paths(k,:)
                    cfg=sixgr.util.structSet(cfg,path,value);
                end
            end
        end
    end
end

function a=emptyAuthority()
a=struct('ContractVersion',"sixgr.config.PUCCHPowerAuthority/v1",'Values',struct());
end
function [names,paths]=pairs()
names=["P0","DeltaTF","PCMAX","Alpha"];
suffix=["p0_dbm","delta_tf_db","pcmax_dbm","alpha"].';
paths=["rf_frontend.ul_power_control.pucch."+suffix, ...
    "pucch_resources.power_control."+suffix];
end
function validateAuthority(a)
[names,~]=pairs();
assert(isequal(sort(fieldnames(a)),{'ContractVersion';'Values'})&& ...
    isstring(a.ContractVersion)&&isscalar(a.ContractVersion)&& ...
    ~ismissing(a.ContractVersion)&&a.ContractVersion=="sixgr.config.PUCCHPowerAuthority/v1"&& ...
    isstruct(a.Values)&&isscalar(a.Values)&&all(ismember(string(fieldnames(a.Values)),names)), ...
    'sixgr:lls6g:config:InvalidPUCCHPowerAuthority','Invalid retained PUCCH power authority.');
for name=reshape(string(fieldnames(a.Values)),1,[])
    validateValue(a.Values.(name),name,"retained "+name);
end
end
function [value,present]=readPair(cfg,name,paths)
value=[]; present=false;
for path=paths
    [raw,found]=readPath(cfg,path);
    if ~found, continue; end
    v=validateValue(raw,name,path);
    if present&&~isequal(value,v)
        error('sixgr:lls6g:config:ConflictingPUCCHPowerAliases', ...
            'Conflicting PUCCH power aliases %s and %s in the same authored/resolved layer.',paths(1),paths(2));
    end
    value=v; present=true;
end
end
function [value,found]=readPath(cfg,path)
value=cfg; found=true;
for key=split(path,'.').'
    if ~isstruct(value)||~isscalar(value)||~isfield(value,key)
        value=[]; found=false; return;
    end
    value=value.(key);
end
end
function value=validateValue(raw,name,path)
valid=isnumeric(raw)&&isreal(raw)&&isscalar(raw)&&isfinite(raw);
if valid&&name=="Alpha", valid=raw>=0&&raw<=1; end
assert(valid,'sixgr:lls6g:config:InvalidPUCCHPowerValue', ...
    '%s requires a finite numeric scalar %s (alpha in [0,1]); text/logical values are not numeric authority.',path,name);
value=double(raw);
end
