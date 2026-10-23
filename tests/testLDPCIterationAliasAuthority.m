function ok=testLDPCIterationAliasAuthority()
% Configuration-only maximum-budget authority, not consumed LDPC iterations.
% No waveform, decoder, receiver, scheduler or performance claim is made.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
repo=fileparts(fileparts(mfilename('fullpath')));
fixtures=fullfile(repo,'simulator','configs','scenarios',[
    "lls_mobile_2ue_100kmh_1sector_full_capture.yaml"
    "lls_tdd_four_port_received_rank_transition_fixture.yaml"
    "lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml"]);
expected=[50 8 8];
original=cellfun(@fileread,cellstr(fixtures),'UniformOutput',false);
work=tempname; mkdir(work);
cleanup=onCleanup(@()rmdir(work,'s')); %#ok<NASGU> % Only this unique test directory.
for k=1:numel(fixtures)
    scenario=sixgr.lls6g.config.loadScenarioConfig(fixtures(k));
    resolved=scenario.toStruct();
    localAssertValue(resolved,expected(k));
    cfg=sixgr.lls6g.buildInternalConfig(scenario,fullfile(work,"build_"+k));
    dl=sixgr.phy.phycode.resolveLDPCMaxIterations(cfg,'Direction','DL');
    ul=sixgr.phy.phycode.resolveLDPCMaxIterations(cfg,'Direction','UL');
    assert(cfg.phy.ldpc.maxIterations==expected(k) && dl==expected(k) && ul==expected(k));
    fprintf('LDPC_ITERATION_AUTHORITY fixture=%s resolved=%g internal=%g DL=%g UL=%g waveform=0\n', ...
        fixtures(k),resolved.coding.max_decoder_iterations,cfg.phy.ldpc.maxIterations,dl,ul);
    assert(strcmp(original{k},fileread(fixtures(k))),'Original scenario file changed.');
end

% Three flat aliases form one last-authored semantic group. Explicitly
% returning to the existing default is an override, not "unspecified".
flat=["coding.max_decoder_iterations","coding.ldpc_max_iterations", ...
    "receiver_algorithms.decoder_iterations"];
canonical=["canonical_control.coding.max_decoder_iterations", ...
    "canonical_control.receiver.decoder_iterations"];
for path=flat
    authority=localMerge(struct(),localSet(struct(),flat(1),25));
    authority=localMerge(authority,localSet(struct(),path,50));
    authority=localMerge(authority,struct('meta',struct('description','unrelated grandchild')));
    cfg=localNormalize(localSet(localMinimal(),flat(1),8),'LDPCIterationAuthority',authority);
    localAssertValue(cfg,50);
    authority=localMerge(authority,localSet(struct(),path,8));
    localAssertValue(localNormalize(cfg,'LDPCIterationAuthority',authority),8);
end
equal=struct();
for path=[flat canonical], equal=localSet(equal,path,17); end
localAssertValue(localNormalize(sixgr.util.mergeStruct(localMinimal(),equal),'Authority',equal),17);
for pair={flat(1:2),flat([1 3]),canonical,[flat(2) canonical(1)]}
    paths=pair{1}; bad=localSet(localSet(struct(),paths(1),8),paths(2),50);
    localReject(@()localMerge(struct(),bad),'sixgr:lls6g:config:LDPCIterationAliasConflict',paths);
end
for value={0,-1,1.5,NaN,Inf,[],[8 9],true,'50',1+1i}
    bad=localSet(struct(),flat(1),value{1});
    localReject(@()localMerge(struct(),bad),'sixgr:lls6g:config:InvalidLDPCIterationLimit',flat(1));
end

% Real loader recursion, including an unrelated scientific grandchild and
% operational-only wrapper. These are declared config fixtures, not PHY.
parent=localWrite(work,'flat_parent',fixtures(1),localSet(struct(),flat(1),25));
grandchild=localWrite(work,'unrelated_child',parent,struct('meta',struct('description','iteration inheritance probe')));
localAssertLoaded(grandchild,25);
backDefault=localWrite(work,'explicit_default',parent,localSet(struct(),flat(2),8));
localAssertLoaded(backDefault,8);
receiverChild=localWrite(work,'receiver_child',parent,localSet(struct(),flat(3),31));
localAssertLoaded(receiverChild,31);
operational=localWrite(work,'operational_child',receiverChild, ...
    struct('run_control',struct('runtime_checkpoint_enable',true)));
localAssertLoaded(operational,31);
emptyChild=localWrite(work,'empty_child',receiverChild,struct());
localAssertLoaded(emptyChild,31);
later=localWrite(work,'later_partial',strings(0,1),localSet(struct(),flat(2),19));
multi=localWrite(work,'multiple_parents',[parent later],struct());
localAssertLoaded(multi,19);

% A new canonical declaration replaces inherited canonical mirrors, but a
% conflicting flat child cannot silently supersede active canonical policy.
both=localSet(localSet(struct(),canonical(1),25),canonical(2),25);
canonParent=localWrite(work,'canonical_parent',parent,both);
canonChild=localWrite(work,'canonical_child',canonParent,localSet(struct(),canonical(2),31));
localAssertLoaded(canonChild,31);
bad=localWrite(work,'flat_vs_canonical',canonChild,localSet(struct(),flat(1),32));
localReject(@()sixgr.lls6g.config.loadScenarioConfig(bad), ...
    'sixgr:lls6g:config:LDPCIterationAliasConflict',[flat(1) canonical(2)]);
sameDoc=localSet(localSet(struct(),canonical(1),25),canonical(2),31);
bad=localWrite(work,'canonical_same_document',parent,sameDoc);
localReject(@()sixgr.lls6g.config.loadScenarioConfig(bad), ...
    'sixgr:lls6g:config:LDPCIterationAliasConflict',canonical);

% The direct no-authorship API retains existing canonical precedence over
% stale flat mirrors. Explicit leaf authorship, unlike a stale mirror, fails.
stale=localSet(localSet(localMinimal(),flat(1),8),canonical(1),43);
localAssertValue(localNormalize(stale),43);
localReject(@()localNormalize(stale,'Authority',localSet(struct(),flat(1),8)), ...
    'sixgr:lls6g:config:LDPCIterationAliasConflict',[flat(1) canonical(1)]);

% The existing ordered override engine remains authoritative. Repeating the
% SAME target retains last-entry order; different contradictory aliases fail.
for target=[flat canonical]
    cfg=localMinimal();
    cfg.canonical_control.runtime_overrides=struct('path',target,'value',37);
    normalized=localNormalize(cfg); localAssertValue(normalized,37);
    again=localNormalize(normalized); localAssertValue(again,37);
    assert(isequaln(normalized,again),'Repeated normalization changed effective runtime authority.');
end
cfg=localSet(localMinimal(),canonical(1),25);
cfg.canonical_control.runtime_overrides=struct('path',flat(1),'value',37);
normalized=localNormalize(cfg); localAssertValue(normalized,37);
assert(normalized.canonical_control.coding.max_decoder_iterations==37 && ...
    isequaln(normalized,localNormalize(normalized)), ...
    'The final deliberate runtime override did not replace the canonical mirror consistently.');
cfg=localMinimal();
cfg.canonical_control.runtime_overrides=[ ...
    struct('path',flat(1),'value',50),struct('path',flat(1),'value',8), ...
    struct('path',"simulation.random_seed",'value',91)];
normalized=localNormalize(cfg); localAssertValue(normalized,8);
assert(normalized.simulation.random_seed==91 && ...
    isequaln(normalized.canonical_control.runtime_overrides,cfg.canonical_control.runtime_overrides));
assert(isequaln(normalized,localNormalize(normalized)));
cfg.canonical_control.runtime_overrides=[ ...
    struct('path',flat(1),'value',8),struct('path',flat(2),'value',50)];
localReject(@()localNormalize(cfg),'sixgr:lls6g:config:LDPCIterationAliasConflict',flat(1:2));

% Public supplied accumulators are validated, not trusted by a version label.
valid=localMerge(struct(),localSet(struct(),flat(1),8));
for value={0,NaN,Inf,1.5}
    bad=valid; bad.Flat.Value=value{1};
    localReject(@()localMerge(bad,struct()),'sixgr:lls6g:config:InvalidLDPCIterationAuthority',strings(0,1));
    localReject(@()localNormalize(localMinimal(),'LDPCIterationAuthority',bad), ...
        'sixgr:lls6g:config:InvalidLDPCIterationAuthority',strings(0,1));
end
bad=valid; bad.Flat.Paths=canonical(1);
localReject(@()localMerge(struct(),bad),'sixgr:lls6g:config:InvalidLDPCIterationAuthority',strings(0,1));
bad=valid; bad.ContractVersion=[valid.ContractVersion valid.ContractVersion];
localReject(@()localMerge(struct(),bad),'sixgr:lls6g:config:InvalidLDPCIterationAuthority',strings(0,1));
bad=rmfield(valid,'Canonical');
localReject(@()localMerge(struct(),bad),'sixgr:lls6g:config:InvalidLDPCIterationAuthority',strings(0,1));

% Minimal/default-cache callers must not acquire an invented decoder budget.
empty=localMerge(struct(),struct());
assert(isempty(fieldnames(empty.Flat)) && isempty(fieldnames(empty.Canonical)));
minimal=localNormalize(localMinimal());
for path=[flat canonical]
    assert(isempty(sixgr.util.structGet(minimal,path,[])), ...
        'An absent iteration budget was manufactured at %s.',path);
end
fprintf('LDPC_ITERATION_ALIAS_AUTHORITY_PASS original_YAML_and_inheritance=1 maximum_budget_only=1 waveform=0\n');
ok=true;
end

function cfg=localMinimal()
cfg=struct('frequency',struct('duplex_mode','TDD'));
% Match the baseline's unbounded AMC policy explicitly. This iteration-only
% fixture must not trigger the unrelated legacy operating-point derivation
% audit, whose per-call provenance is intentionally rebuilt by normalization.
cfg.link_adaptation=struct('fixed_or_amc','amc','operating_point_mode','adaptive');
end
function cfg=localNormalize(cfg,varargin)
cfg=sixgr.lls6g.config.normalizeScenarioAliases(cfg,varargin{:});
derived=string(sixgr.util.structGet(cfg, ...
    'config_inheritance.provenance.auto_normalized_fields',strings(0,1)));
assert(~any(derived=="link_adaptation.operating_point_mode",'all'), ...
    'The iteration fixture unexpectedly relied on operating-point derivation.');
end
function authority=localMerge(authority,authored)
authority=sixgr.lls6g.config.mergeLDPCIterationAuthority(authority,authored);
end
function cfg=localSet(cfg,path,value)
cfg=sixgr.util.structSet(cfg,path,value);
end
function path=localWrite(work,name,parents,authored)
path=string(fullfile(work,name+".json"));
if ~isempty(parents), authored.inherits=string(parents); end
sixgr.util.jsonWrite(path,authored);
end
function localAssertLoaded(path,expected)
scenario=sixgr.lls6g.config.loadScenarioConfig(path);
localAssertValue(scenario.toStruct(),expected);
end
function localAssertValue(cfg,expected)
for path=["coding.max_decoder_iterations","coding.ldpc_max_iterations", ...
        "receiver_algorithms.decoder_iterations"]
    assert(isequal(double(sixgr.util.structGet(cfg,path,NaN)),double(expected)), ...
        'Wrong effective maximum at %s.',path);
end
for path=["canonical_control.coding.max_decoder_iterations", ...
        "canonical_control.receiver.decoder_iterations"]
    value=sixgr.util.structGet(cfg,path,[]);
    if ~isempty(value), assert(isequal(double(value),double(expected))); end
end
end
function localReject(action,id,paths)
try
    action();
catch cause
    assert(strcmp(cause.identifier,id),'Unexpected rejection %s: %s',cause.identifier,cause.message);
    % MATLAB iterates columns: a 0-by-1 string array has one empty column.
    % Iterate elements so an empty expected-path list checks only the typed
    % rejection, while every nonempty expected key must still be present.
    for k=1:numel(paths)
        path=paths(k);
        assert(contains(string(cause.message),path),'Missing conflicting key path %s.',path);
    end
    return;
end
error('test:MissingLDPCIterationRejection','Expected %s.',id);
end
