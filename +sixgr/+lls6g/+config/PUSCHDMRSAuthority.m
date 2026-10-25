classdef PUSCHDMRSAuthority
    %PUSCHDMRSAUTHORITY Last-authored configured DM-RS alias group authority.
    % A port set here is the ordered configured pool, not an active grant.
    % No source file is reread: inheritance carries these value records.
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

function out=emptyAuthority()
out=struct('ContractVersion',"sixgr.config.PUSCHDMRSAuthority/v1",'Values',struct());
end
function [names,paths]=pairs()
names=["ConfigurationType","Length","AdditionalPositions","TypeAPosition","CDMGroups","PortSet"];
paths=["reference_signals.pusch_dmrs_config_type","pusch.dmrs_configuration_type"; ...
    "reference_signals.pusch_dmrs_max_length","pusch.dmrs_length"; ...
    "reference_signals.pusch_dmrs_additional_positions","pusch.dmrs_additional_position"; ...
    "reference_signals.pusch_dmrs_type_a_position","pusch.dmrs_type_a_position"; ...
    "reference_signals.pusch_dmrs_num_cdm_groups_without_data","pusch.dmrs_num_cdm_groups_without_data"; ...
    "reference_signals.pusch_dmrs.port_set","pusch.dmrs_port_set"];
end
function validateAuthority(a)
[names,~]=pairs();
assert(isequal(sort(fieldnames(a)),{'ContractVersion';'Values'})&& ...
    isstring(a.ContractVersion)&&isscalar(a.ContractVersion)&& ...
    ~ismissing(a.ContractVersion)&&a.ContractVersion=="sixgr.config.PUSCHDMRSAuthority/v1"&& ...
    isstruct(a.Values)&&isscalar(a.Values)&&all(ismember(string(fieldnames(a.Values)),names)), ...
    'sixgr:lls6g:config:InvalidPUSCHDMRSAuthority','Invalid retained configured DM-RS authority.');
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
        error('sixgr:lls6g:config:ConflictingPUSCHDMRSAliases', ...
            'Conflicting configured DM-RS aliases %s and %s in the same authored/resolved layer.',paths(1),paths(2));
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
valid=isnumeric(raw)&&isreal(raw)&&~isempty(raw)&&isvector(raw)&& ...
    all(isfinite(raw(:)))&&all(raw(:)==fix(raw(:)));
if valid
    switch name
        case {"ConfigurationType","Length"}, valid=isscalar(raw)&&ismember(raw,[1 2]);
        case "AdditionalPositions", valid=isscalar(raw)&&ismember(raw,0:3);
        case "TypeAPosition", valid=isscalar(raw)&&ismember(raw,[2 3]);
        case "CDMGroups", valid=isscalar(raw)&&ismember(raw,1:3);
        case "PortSet", valid=all(raw(:)>=0&raw(:)<=11)&&numel(unique(raw))==numel(raw);
    end
end
assert(valid,'sixgr:lls6g:config:InvalidPUSCHDMRSValue', ...
    '%s must contain valid numeric integer configured %s values (not coerced text/logical or an empty value).',path,name);
value=reshape(double(raw),1,[]);
end
