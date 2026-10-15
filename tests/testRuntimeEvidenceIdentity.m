function ok = testRuntimeEvidenceIdentity()
% Labelled serialization/manifest fixtures, not waveform performance results.
values = [16777215 NaN 1/3 Inf -Inf 0];
token = sixgr.truth.formatNumericEvidenceVector(values);
assert(isequaln(str2double(split(token,'|')).',values));
assert(sixgr.truth.formatNumericEvidenceVector([])=="");
assert(sixgr.truth.formatNumericEvidenceVector('1|NaN|3')=="1|NaN|3");
localError(@()sixgr.truth.formatNumericEvidenceVector(ones(2)), ...
    'sixgr:truth:InvalidNumericEvidenceVector');
localError(@()sixgr.truth.formatNumericEvidenceVector(1+1i), ...
    'sixgr:truth:InvalidNumericEvidenceVector');

n = 1024; t=(0:n-1).';
waveform = [.2*exp(1i*2*pi*t/8),.1*exp(-1i*2*pi*t/5)];
capture = struct('Waveform',waveform,'SampleRateHz',122.88e6, ...
    'Frame',0,'Slot',0,'WaveformAuthority',"exact_runtime_transmitter_composite_observation", ...
    'CompositeTransmitterWaveform',false,'ArtifactScope',"incorrect_component_scope");
bound = sixgr.truth.bindCommittedTxIQScope(capture,"DL");
assert(isequal(bound.Waveform,waveform) && bound.CompositeTransmitterWaveform);
assert(bound.ArtifactScope=="first_committed_grant_observed_composite_interval");
assert(contains(bound.VSGImportScope,"not_continuous_run"));
ul = sixgr.truth.bindCommittedTxIQScope(capture,"UL");
assert(ul.CompositeTransmitterWaveform && ul.EndpointType=="ue_transmitter");
component=capture; component.WaveformAuthority="exact_runtime_pdsch_waveform";
component=sixgr.truth.bindCommittedTxIQScope(component,"DL");
assert(~component.CompositeTransmitterWaveform && component.EndpointType=="gnb_grant_component");
bad=capture; bad.WaveformAuthority="configured_regenerated_waveform";
localError(@()sixgr.truth.bindCommittedTxIQScope(bad,"DL"), ...
    'sixgr:truth:UnknownCommittedIQAuthority');

% Exercise the actual MAT/WIQ/CSV exporter with this bounded test waveform.
folder=tempname; mkdir(folder);
cleanup=onCleanup(@()rmdir(folder,'s')); %#ok<NASGU>
cfg=struct('channel',struct('fc_Hz',4e9));
out=sixgr.truth.exportRuntimeTxIQCapture(folder,bound,cfg,'DL');
saved=load(out.MATPath,'waveform','metadata');
assert(isequal(saved.waveform,waveform) && saved.metadata.CompositeTransmitterWaveform);
assert(saved.metadata.ArtifactScope==bound.ArtifactScope && ...
    saved.metadata.SampleRateHz==122.88e6 && saved.metadata.CenterFrequencyHz==4e9);
manifest=sixgr.util.csvReadTable(out.ManifestPath);
assert(height(manifest)==1 && manifest.CompositeTransmitterWaveform==1 && ...
    string(manifest.ArtifactScope)==bound.ArtifactScope && ...
    string(manifest.PhysicalInstrumentValidationStatus)=="not_executed_requires_physical_instrument");
assert(manifest.KeysightInt16MaxComplexError<=sqrt(2)/(2*32767)+eps);
ok=true; fprintf('RUNTIME_EVIDENCE_IDENTITY_PASS\n');
end

function localError(action,identifier)
try
    action();
catch err
    assert(strcmp(err.identifier,identifier),err.message);
    return;
end
error('test:MissingExpectedFailure','Expected %s.',identifier);
end
