function row=retainCSIRSReceivedEVMPairs(root,row,pairs,metrics)
% Dedicated RX namespace preserves the original TX ControlEVMSamples binding.
assert(istable(row)&&height(row)==1&&isstruct(metrics)&&isscalar(metrics));
for field=string(fieldnames(metrics)).'
    row.("CSIRSReceivedEVM"+field)=metrics.(field);
end
if isempty(pairs), return; end
assert(islogical(metrics.Available)&&isscalar(metrics.Available)&&metrics.Available, ...
    'sixgr:report:CSIRSReceivedEVMProof','Received pairs require original completed isolation evidence.');
temporary=sixgr.report.retainControlEVMPairs(root,row,pairs);
names=string(temporary.Properties.VariableNames);
for field=names(startsWith(names,"ControlEVMSamples"))
    target=replace(field,"ControlEVMSamples","CSIRSReceivedEVMSamples");
    row.(target)=temporary.(field);
end
end
