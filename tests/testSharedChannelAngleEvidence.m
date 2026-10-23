function ok=testSharedChannelAngleEvidence()
% Bounded native channel + metadata binding, not receiver AoA qualification.
setup6GRSimToolkit('Verbose',false);
channel=nrCDLChannel;
channel.DelayProfile='CDL-C'; channel.SampleRate=7.68e6;
channel.SampleDensity=Inf;
channel.NormalizeChannelOutputs=false;
channel.TransmitAntennaArray.Size=[1 1 2 1 1];
channel.ReceiveAntennaArray.Size=[1 1 2 1 1];
channel.RandomStream='mt19937ar with seed'; channel.Seed=1042;
rngBefore=rng;
[~,gains1]=channel(complex(ones(32,2)));
[~,gains2]=channel(complex(ones(32,2)));
actual=info(channel);
assert(size(gains1,1)==32 && size(gains2,1)==32);
first=segment(actual,gains1,1,0,false);
second=segment(actual,gains2,2,32,false);
manifest=struct('Contract',"actual_shared_channel_observation/v2", ...
    'Source',"same_executed_NR_channel_path_gains_and_filters", ...
    'ReceiverEstimatorInput',false,'ObservationStartSample',0, ...
    'ObservationEndSampleExclusive',64,'SampleRateHz',channel.SampleRate, ...
    'InactiveIntervals',zeros(0,2),'Segments',[first;second]);
base=rowFor(manifest);
[bound,context]=sixgr.truth.bindSharedChannelAngleEvidence(base,manifest);
assert(context.RuntimeChannelAngleEvidenceAvailable && ...
    context.RuntimeChannelAngleVectorsInvariant && bound.RuntimeChannelAnglePathCount==24 && ...
    bound.RuntimeChannelAngleSegmentCount==2 && ...
    bound.RuntimeChannelAngleValueRole=="executed_channel_model_parameter_not_receiver_estimate");
for name=["AoD","AoA","ZoD","ZoA"]
    assert(isequal(context.("RuntimeChannelAngles"+name+"_deg"),actual.("Angles"+name)));
end
assert(isequaln(bound,sixgr.truth.bindSharedChannelAngleEvidence(bound,manifest)) && ...
    isequal(rngBefore,rng) && bound.EVM_rms==base.EVM_rms && bound.CRCPass==base.CRCPass);

% The native reverse-link object owns angle reversal; the binder must not
% swap a second time based on a guessed direction or physical-array size.
swapTransmitAndReceive(channel);
[~,reverseGains]=channel(complex(ones(32,2)));
reverseInfo=info(channel);
reverse=manifest; reverse.ObservationStartSample=64; reverse.ObservationEndSampleExclusive=96;
reverse.Segments=segment(reverseInfo,reverseGains,1,64,true);
[~,reverseContext]=sixgr.truth.bindSharedChannelAngleEvidence(rowFor(reverse),reverse);
assert(isequal(reverseContext.RuntimeChannelAnglesAoD_deg,reverseInfo.AnglesAoD) && ...
    isequal(reverseInfo.AnglesAoD,actual.AnglesAoA));

% Deliberately changed metadata fixtures test preservation/validation only;
% they are not exported as actual physical measurements.
varying=manifest;
changed=actual.AnglesAoD; changed(1)=changed(1)+1;
varying.Segments(2).RuntimeChannelAnglesAoD_degJSON=string(jsonencode(changed));
[varyingRow,varyingContext]=sixgr.truth.bindSharedChannelAngleEvidence(rowFor(varying),varying);
assert(~varyingContext.RuntimeChannelAngleVectorsInvariant && ...
    ~varyingContext.RuntimeChannelAngleEvidenceAvailable && ...
    varyingContext.RuntimeChannelAngleSegmentEvidenceAvailable && ...
    isempty(varyingContext.RuntimeChannelAnglesAoD_deg));
retained=jsondecode(varyingRow.RuntimeChannelAngleSegmentsJSON);
assert(retained(2).AnglesAoD_deg(1)==changed(1) && ...
    retained(1).AnglesAoD_deg(1)==actual.AnglesAoD(1));

tdl=manifest;
for k=1:2
    tdl.Segments(k).ChannelModelApplied="TDL-C";
    tdl.Segments(k).ChannelFadingObjectClass="nrTDLChannel";
    tdl.Segments(k).RuntimeChannelAngleEvidenceAvailable=false;
    tdl.Segments(k).RuntimeChannelAngleEvidenceSource="";
    tdl.Segments(k).RuntimeChannelAngleCoordinateFrame="";
    for name=["AoD","AoA","ZoD","ZoA"]
        tdl.Segments(k).("RuntimeChannelAngles"+name+"_degJSON")="[]";
    end
end
[tdlRow,tdlContext]=sixgr.truth.bindSharedChannelAngleEvidence(rowFor(tdl),tdl);
assert(~tdlContext.RuntimeChannelAngleEvidenceAvailable && tdlRow.RuntimeChannelAnglePathCount==0);

bad=manifest; bad.Segments(2).RuntimeChannelAnglesAoD_degJSON="[0]"; rejects(bad);
bad=manifest; invalidZenith=actual.AnglesZoA; invalidZenith(1)=181;
bad.Segments(2).RuntimeChannelAnglesZoA_degJSON=string(jsonencode(invalidZenith)); rejects(bad);
bad=manifest; bad.Segments(2).RuntimeChannelAngleEvidenceSource="yaml_geometry"; rejects(bad);
bad=manifest; bad.Segments(2).RuntimeChannelAngleCoordinateFrame="local_panel_frame"; rejects(bad);
bad=manifest; bad.Segments(2).RuntimeChannelAngleEvidenceAvailable=false; rejects(bad);
bad=manifest; bad.Segments(2).StartSample=33;
bad.Segments(2).PathGainDimensions="[31,24,2,2]"; rejects(bad);
bad=manifest; bad.Segments(2).ExecutionStartSample=33; rejects(bad);
bad=manifest; bad.Segments(2).SegmentIndex=1; rejects(bad);
bad=manifest; bad.Segments(2).PathGainDimensions="[32,23,2,2]"; rejects(bad);
bad=manifest; bad.InactiveIntervals=[0 1]; rejects(bad);
bad=manifest; bad.Source="geometry_proxy"; rejects(bad);
bad=manifest; bad.ReceiverEstimatorInput=true; rejects(bad);
bad=manifest; bad.Segments=rmfield(bad.Segments,'RuntimeChannelAnglesZoD_degJSON'); rejects(bad);
wrong=base; wrong.ChannelObservationManifestSHA256="wrong";
mustReject(@()sixgr.truth.bindSharedChannelAngleEvidence(wrong,manifest));
wrong=base; wrong.ChannelObservationManifestJSON="{}";
mustReject(@()sixgr.truth.bindSharedChannelAngleEvidence(wrong,manifest));
assert(isequal(rngBefore,rng));
ok=true;
fprintf('SHARED_CHANNEL_ANGLE_BINDING_PASS native_directions=2 negative_cases=15 receiver_angle_qualification=0\n');
end

function value=segment(info,gains,index,start,swapped)
value=struct('SegmentIndex',index,'StartSample',start,'EndSampleExclusive',start+size(gains,1), ...
    'ExecutionStartSample',start,'ExecutionEndSampleExclusive',start+size(gains,1), ...
    'PathGainDimensions',string(jsonencode([size(gains,1) size(gains,2) size(gains,3) size(gains,4)])), ...
    'RuntimeChannelPathDelays_sJSON',string(jsonencode(info.PathDelays)), ...
    'RuntimeChannelAngleEvidenceAvailable',true, ...
    'RuntimeChannelAngleEvidenceSource',"info_on_same_executed_runtime_channel_object", ...
    'RuntimeChannelAngleCoordinateFrame',"3gpp_tr38901_global_coordinate_system", ...
    'ChannelModelApplied',"CDL-C",'ChannelFadingObjectClass',"nrCDLChannel", ...
    'RuntimeChannelTransmitAndReceiveSwapped',swapped);
for name=["AoD","AoA","ZoD","ZoA"]
    value.("RuntimeChannelAngles"+name+"_degJSON")=string(jsonencode(info.("Angles"+name)));
end
end

function row=rowFor(manifest)
row=table(.04,true,'VariableNames',{'EVM_rms','CRCPass'});
row.ChannelObservationManifestJSON=string(jsonencode(manifest));
row.ChannelObservationManifestSHA256=sixgr.phy.waveform.WaveformHash.bytes(row.ChannelObservationManifestJSON);
end

function rejects(manifest)
mustReject(@()sixgr.truth.bindSharedChannelAngleEvidence(rowFor(manifest),manifest));
end

function mustReject(call)
try
    call();
catch cause
    assert(strcmp(cause.identifier,'sixgr:truth:InvalidSharedChannelAngleEvidence'), ...
        'Unexpected failure %s: %s',cause.identifier,cause.message);
    return;
end
error('sixgr:test:UnrejectedSharedChannelAngleCorruption','Corrupt metadata must be rejected.');
end
