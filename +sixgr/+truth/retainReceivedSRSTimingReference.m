function reference = retainReceivedSRSTimingReference(prepared, observation, output)
% Retain a practical received clock independently of oracle/NMSE scoring.
% Ok/StrictOk describe qualification and are deliberately not read here.
reference=[];
assert(isstruct(output) && isscalar(output), ...
    'sixgr:truth:InvalidSRSReceiverEvidence','SRS receiver evidence must be a scalar struct.');
usable=sixgr.util.structGet(output,'SRSRuntimeEvidenceUsable',false);
assert(localBoolean(usable),'sixgr:truth:InvalidSRSReceiverEvidence', ...
    'SRSRuntimeEvidenceUsable must be an explicit boolean, not NaN or a status string.');
if ~logical(usable), return; end
required=["DetectionUsable","ResourceExtractionAvailable","ChannelEstimateAvailable", ...
    "SRSChannelEstimateAvailable","MeasurementUsable","StrictReceiverEvidenceOk"];
for field=required
    value=sixgr.util.structGet(output,field,[]);
    assert(localBoolean(value) && logical(value), ...
        'sixgr:truth:InconsistentSRSReceiverEvidence', ...
        'Usable SRS timing contradicts practical receiver field %s.',field);
end
assert(~logical(sixgr.util.structGet(output,'Skipped',false)), ...
    'sixgr:truth:InconsistentSRSReceiverEvidence','A skipped SRS cannot supply a received clock.');
% This constructor validates actual observation identity, bounded pilot
% correlation, capture coverage and the prohibition on oracle/zero padding.
reference=sixgr.phy.sync.ReceivedULTimingReference(prepared,observation,output.ReceiveTiming);
end

function tf=localBoolean(value)
tf=(islogical(value) || isnumeric(value)) && isscalar(value) && ...
    isreal(value) && isfinite(value) && (value==0 || value==1);
end
