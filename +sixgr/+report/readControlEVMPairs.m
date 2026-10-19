function records=readControlEVMPairs(row,trialPath,verifyOnly)
% Read legacy inline or checksum-bound full paired samples, never a proxy.
if nargin<3, verifyOnly=false; end
records=struct([]);
names=string(row.Properties.VariableNames);
token=""; relative="";
if ismember('ControlEVMSamplesJSON',names), token=string(row.ControlEVMSamplesJSON); end
if ismember('ControlEVMSamplesMATFile',names), relative=string(row.ControlEVMSamplesMATFile); end
if ismissing(token), token=""; end
if ismissing(relative), relative=""; end
assert(strlength(token)==0 || strlength(relative)==0, ...
    'sixgr:report:AmbiguousControlEVMPairs','A trial cannot have two competing sample authorities.');
if strlength(relative)==0
    if strlength(token)>0 && ~verifyOnly, records=jsondecode(token); end
    return;
end
required=["ControlEVMSamplesMATFileSHA256","ControlEVMSamplesContentSHA256", ...
    "ControlEVMSamplesStorageContract","ControlEVMSamplesCount"];
assert(all(ismember(required,names)) && ...
    row.ControlEVMSamplesStorageContract=="control_evm_pairs/v1" && ...
    ~isempty(regexp(char(relative),'^air_interface/mat/control_evm/[a-f0-9]{64}\.mat$','once')), ...
    'sixgr:report:ControlEVMDetailBinding','A versioned run-relative immutable sample binding is required.');
% These primary/mirrored CSV locations establish the owning run boundary.
% An unbounded ancestor search can accidentally borrow another run's data.
folder=string(fileparts(char(java.io.File(char(trialPath)).getAbsolutePath())));
[component,csvName]=fileparts(folder);
[runRoot,componentName]=fileparts(component);
assert(strcmpi(csvName,'csv') && any(strcmpi(componentName,{'air_interface','control'})), ...
    'sixgr:report:ControlEVMDetailRunScope', ...
    'MAT-bound trials must be read from this run''s air_interface/csv or control/csv.');
runRoot=string(java.io.File(char(runRoot)).getCanonicalPath());
% The second location is the explicit historical component-root defect.
% Support retained runs without modifying their bindings, but nowhere else.
candidates=[fullfile(runRoot,relative),fullfile(runRoot,'air_interface',relative)];
targets=strings(0,1);
for candidate=candidates
    canonical=string(java.io.File(char(candidate)).getCanonicalPath());
    assert(startsWith(canonical,runRoot+filesep,'IgnoreCase',ispc), ...
        'sixgr:report:ControlEVMDetailRunScope','Paired samples must remain inside the owning run.');
    if isfile(canonical), targets(end+1,1)=canonical; end %#ok<AGROW>
end
assert(~isempty(targets),'sixgr:report:ControlEVMDetailMissing', ...
    'Missing exact paired-sample artifact %s; do not substitute another observation.',relative);
assert(numel(targets)==1,'sixgr:report:AmbiguousControlEVMPairs', ...
    'Canonical and legacy component-root artifacts cannot compete for one trial.');
target=targets(1);
assert(sixgr.util.sha256File(target)==string(row.ControlEVMSamplesMATFileSHA256), ...
    'sixgr:report:ControlEVMDetailChecksum','Retained paired samples changed after publication.');
% Even a cached CSV publication must validate its source-file checksum.
if verifyOnly, return; end
saved=load(target);
assert(all(isfield(saved,{'Contract','ContentSHA256','TrialIdentity','Pairs'})) && ...
    saved.Contract==row.ControlEVMSamplesStorageContract && ...
    saved.ContentSHA256==row.ControlEVMSamplesContentSHA256 && ...
    endsWith(relative,saved.ContentSHA256+".mat"), ...
    'sixgr:report:ControlEVMDetailBinding','Detail contract/content identity does not match the trial.');
for field=string(fieldnames(saved.TrialIdentity)).'
    assert(ismember(field,names) && isequaln(saved.TrialIdentity.(field),row.(field)), ...
        'sixgr:report:ControlEVMDetailTrialIdentity','Paired samples belong to a different trial (%s).',field);
end
records=saved.Pairs;
assert(isstruct(records) && sum(arrayfun(@(p)numel(p.SampleIndex),records))==row.ControlEVMSamplesCount, ...
    'sixgr:report:ControlEVMDetailCount','Retain the complete paired-sample population.');
end
