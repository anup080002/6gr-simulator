function row=retainControlEVMPairs(root,row,pairs)
% Lossless post-reception storage; never an input to CSI/decoder decisions.
assert(istable(row) && height(row)==1 && isstruct(pairs), ...
    'sixgr:report:ControlEVMDetailInput','One completed trial and its paired samples are required.');
row.ControlEVMSamplesJSON="";
row.ControlEVMSamplesMATFile="";
row.ControlEVMSamplesMATFileSHA256="";
row.ControlEVMSamplesContentSHA256="";
row.ControlEVMSamplesStorageContract="control_evm_pairs/v2";
row.ControlEVMSamplesCount=0;
if isempty(pairs), return; end
if ~sixgr.util.persistenceEnabled()
    % An explicitly non-persisting component retains its exact evidence in
    % memory. Do not create a dangling file reference or discard samples.
    row.ControlEVMSamplesJSON=string(jsonencode(pairs));
    row.ControlEVMSamplesStorageContract="inline_control_evm_pairs/v1";
    row.ControlEVMSamplesCount=sum(arrayfun(@(p)numel(p.SampleIndex),pairs));
    return;
end
% Version 2 additionally binds the actual producer-supplied sweep identity.
% In particular ConfiguredSNR_dB is not always accompanied by SNR_dB.
% Never infer missing historical metadata or create another physical trial
% merely by changing the labels of an already-retained sample population.
identityNames=intersect(["Direction","UEIndex","CellID","RNTI","Slot","SNR_dB", ...
    "SweepPointIndex","ConfiguredSNR_dB"], ...
    string(row.Properties.VariableNames),'stable');
identity=table2struct(row(:,identityNames));
descriptor=pairs;
arrayFields=["SampleIndex","ReferenceReal","ReferenceImag","MeasuredReal","MeasuredImag"];
assert(all(isfield(pairs,arrayFields)), ...
    'sixgr:report:ControlEVMPairSchema','Retain all five paired-sample arrays.');
for k=1:numel(pairs)
    for field=arrayFields
        descriptor(k).(field)=string(sixgr.channel.ChannelFactory.runtimeNumericArraySHA256(pairs(k).(field)));
    end
end
digest=sixgr.util.sha256Hex(struct('Contract',row.ControlEVMSamplesStorageContract, ...
    'TrialIdentity',identity,'Pairs',descriptor));
relative="air_interface/mat/control_evm/"+digest+".mat";
target=fullfile(root,relative);
payload=struct('Contract',row.ControlEVMSamplesStorageContract, ...
    'ContentSHA256',digest,'TrialIdentity',identity,'Pairs',pairs);
if isfile(target)
    saved=load(target);
    assert(isequaln(saved,payload),'sixgr:report:ControlEVMDetailCollision', ...
        'Never overwrite an altered or conflicting retained EVM artifact.');
else
    sixgr.util.matSave(target,payload,'UseArtifactStore',false);
    saved=load(target);
    assert(isequaln(saved,payload),'sixgr:report:ControlEVMDetailRoundTrip', ...
        'Every sample, numeric class, shape and source identity must survive storage.');
end
row.ControlEVMSamplesMATFile=relative;
row.ControlEVMSamplesMATFileSHA256=sixgr.util.sha256File(target);
row.ControlEVMSamplesContentSHA256=digest;
row.ControlEVMSamplesCount=sum(arrayfun(@(p)numel(p.SampleIndex),pairs));
end
