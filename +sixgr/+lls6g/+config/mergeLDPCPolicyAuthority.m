function authority=mergeLDPCPolicyAuthority(authority,authored)
%MERGELDPCPOLICYAUTHORITY Retain per-field decoder-policy YAML authorship.
% Independent knobs do not replace the whole policy. Canonical control wins
% inherited flat mirrors; a later contradictory flat declaration must name
% canonical_control explicitly. This does not change iteration authority.
arguments
    authority (1,1) struct
    authored (1,1) struct
end
version="sixgr.config.LDPCPolicyAuthority/v1";
names=["ldpc_algorithm","ldpc_scaling_factor","ldpc_min_sum_offset", ...
    "ldpc_early_termination","ldpc_schedule_type"];
if isempty(fieldnames(authority))
    authority=struct('ContractVersion',version,'Flat',struct(),'Canonical',struct());
end
localValidateAuthority(authority,version,names);
retained=isfield(authored,'ContractVersion');
if retained
    localValidateAuthority(authored,version,names);
end
for name=names
    if retained
        flat=localRecord(authored.Flat,name); canonical=localRecord(authored.Canonical,name);
    else
        flat=localRead(authored,"coding."+name,name);
        canonical=localRead(authored,"canonical_control.coding."+name,name);
        if ~isempty(fieldnames(flat))&&~isempty(fieldnames(canonical))
            localRequireEqual(flat,canonical,'Conflicting explicit declarations in one YAML document.');
        end
    end
    if ~isempty(fieldnames(canonical))
        authority.Canonical.(name)=canonical;
    elseif ~isempty(fieldnames(flat))&&isfield(authority.Canonical,name)
        localRequireEqual(flat,authority.Canonical.(name), ...
            'A later flat declaration conflicts with active canonical control; override canonical_control explicitly.');
    end
    if ~isempty(fieldnames(flat)), authority.Flat.(name)=flat; end
end
end

function localValidateAuthority(authority,version,names)
id='sixgr:lls6g:config:InvalidLDPCPolicyAuthority';
assert(isequal(sort(fieldnames(authority)),sort({'ContractVersion';'Flat';'Canonical'}))&& ...
    isstring(authority.ContractVersion)&&isscalar(authority.ContractVersion)&& ...
    ~ismissing(authority.ContractVersion)&&authority.ContractVersion==version,id, ...
    'Expected the original scalar decoder-policy authority and exact version.');
for group=["Flat","Canonical"]
    values=authority.(group);
    assert(isstruct(values)&&isscalar(values)&&all(ismember(string(fieldnames(values)),names)), ...
        id,'Decoder-policy authority contains an invalid field group.');
    prefix="coding."; if group=="Canonical", prefix="canonical_control.coding."; end
    for name=string(fieldnames(values)).'
        record=values.(name);
        assert(isstruct(record)&&isscalar(record)&& ...
            isequal(sort(fieldnames(record)),{'Path';'Value'})&& ...
            isstring(record.Path)&&isscalar(record.Path)&& ...
            ~ismissing(record.Path)&&record.Path==prefix+name,id, ...
            'Decoder-policy authority must retain the exact original field path.');
        localValidateValue(record.Value,name,record.Path);
    end
end
end

function record=localRecord(group,name)
record=struct();
if isfield(group,name), record=group.(name); end
end

function record=localRead(source,path,name)
record=struct(); value=source;
for part=split(path,'.').'
    if ~isstruct(value)||~isscalar(value)||~isfield(value,part), return; end
    value=value.(part);
end
value=localValidateValue(value,name,path);
record=struct('Value',value,'Path',path);
end

function value=localValidateValue(value,name,path)
names=["ldpc_algorithm","ldpc_scaling_factor","ldpc_min_sum_offset", ...
    "ldpc_early_termination","ldpc_schedule_type"];
runtime=["algorithm","scalingFactor","minSumOffset","termination","scheduleType"];
if name=="ldpc_early_termination"
    assert(islogical(value)&&isscalar(value),'sixgr:lls6g:config:InvalidLDPCPolicy', ...
        '%s must be a scalar logical, not a numeric or empty coercion.',path);
    return;
end
key=runtime(names==name);
try
    checked=sixgr.config.validateLDPCPolicy(struct(key,value),"coding");
catch err
    error('sixgr:lls6g:config:InvalidLDPCPolicy','%s: %s',path,err.message);
end
value=checked.(key);
end

function localRequireEqual(a,b,reason)
assert(isequaln(a.Value,b.Value),'sixgr:lls6g:config:LDPCPolicyConflict', ...
    '%s %s versus %s must agree.',reason,a.Path,b.Path);
end
