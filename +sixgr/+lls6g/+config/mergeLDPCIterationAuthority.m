function authority=mergeLDPCIterationAuthority(authority,authored)
% Retain document-level authorship of the existing LDPC iteration aliases.
% Flat aliases are last-author-wins as one semantic group. Canonical control
% remains authoritative: a later flat contradiction must override canonical
% control explicitly. A canonical child can replace inherited canonical
% mirrors, but contradictory aliases in ONE document are never order-picked.
arguments
    authority (1,1) struct
    authored (1,1) struct
end
version="sixgr.config.LDPCIterationAuthority/v1";
if isempty(fieldnames(authority))
    authority=struct('ContractVersion',version,'Flat',struct(),'Canonical',struct());
end
localValidateAuthority(authority,version);
if isfield(authored,'ContractVersion')
    localValidateAuthority(authored,version);
    % A resolved parent can contain stale flat mirrors preceding its active
    % canonical document; it is not a new document authoring both surfaces.
    flat=authored.Flat; canonical=authored.Canonical;
else
    flat=localGroup(authored,["coding.max_decoder_iterations", ...
        "coding.ldpc_max_iterations","receiver_algorithms.decoder_iterations"]);
    canonical=localGroup(authored,["canonical_control.coding.max_decoder_iterations", ...
        "canonical_control.receiver.decoder_iterations"]);
    if ~isempty(fieldnames(flat)) && ~isempty(fieldnames(canonical))
        localRequireEqual(flat,canonical, ...
            'Conflicting explicit iteration declarations in the same YAML document.');
    end
end
if ~isempty(fieldnames(canonical))
    authority.Canonical=canonical;
elseif ~isempty(fieldnames(flat)) && ~isempty(fieldnames(authority.Canonical))
    localRequireEqual(flat,authority.Canonical, ...
        'A later flat declaration conflicts with active canonical control; override canonical_control explicitly.');
end
if ~isempty(fieldnames(flat)), authority.Flat=flat; end
end

function localValidateAuthority(authority,version)
id='sixgr:lls6g:config:InvalidLDPCIterationAuthority';
assert(isequal(sort(fieldnames(authority)),sort({'ContractVersion';'Flat';'Canonical'})) && ...
    isstring(authority.ContractVersion) && isscalar(authority.ContractVersion) && ...
    ~ismissing(authority.ContractVersion) && authority.ContractVersion==version, ...
    id,'Expected the original scalar iteration authority accumulator and exact contract version.');
localValidateGroup(authority.Flat,["coding.max_decoder_iterations", ...
    "coding.ldpc_max_iterations","receiver_algorithms.decoder_iterations"],id);
localValidateGroup(authority.Canonical,["canonical_control.coding.max_decoder_iterations", ...
    "canonical_control.receiver.decoder_iterations"],id);
end

function localValidateGroup(group,paths,id)
assert(isstruct(group) && isscalar(group),id,'Each iteration authority group must be a scalar struct.');
if isempty(fieldnames(group)), return; end
assert(isequal(sort(fieldnames(group)),{'Paths';'Value'}) && ...
    isnumeric(group.Value) && isreal(group.Value) && isscalar(group.Value) && ...
    isfinite(group.Value) && group.Value>=1 && group.Value==fix(group.Value) && ...
    isstring(group.Paths) && isvector(group.Paths) && ~isempty(group.Paths) && ...
    ~any(ismissing(group.Paths)) && all(ismember(group.Paths,paths)) && ...
    numel(unique(group.Paths))==numel(group.Paths),id, ...
    'Iteration authority requires a finite positive integer Value and exact original alias Paths.');
end

function group=localGroup(authored,paths)
group=struct();
for path=paths
    [value,present]=localGet(authored,path);
    if ~present, continue; end
    assert(isnumeric(value) && isreal(value) && isscalar(value) && ...
        isfinite(value) && value>=1 && value==fix(value), ...
        'sixgr:lls6g:config:InvalidLDPCIterationLimit', ...
        '%s must be a finite positive integer decoder-iteration limit.',path);
    next=struct('Value',value,'Paths',path);
    if isempty(fieldnames(group))
        group=next;
    else
        localRequireEqual(group,next, ...
            'Conflicting explicit iteration declarations in the same YAML document.');
        group.Paths(end+1)=path;
    end
end
end

function localRequireEqual(a,b,reason)
assert(double(a.Value)==double(b.Value), ...
    'sixgr:lls6g:config:LDPCIterationAliasConflict', ...
    '%s %s=%g versus %s=%g. Use one authority or identical values.', ...
    reason,strjoin(a.Paths,','),double(a.Value),strjoin(b.Paths,','),double(b.Value));
end

function [value,present]=localGet(source,path)
value=source; present=true;
for part=split(path,'.').'
    if ~isstruct(value) || ~isscalar(value) || ~isfield(value,part)
        value=[]; present=false; return;
    end
    value=value.(part);
end
end
