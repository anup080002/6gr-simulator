function [reference,heldout,proof]=readGrantCalibrationReference(folder,referenceKey,targetKey,rvSequence)
%READGRANTCALIBRATIONREFERENCE Measured AWGN grid for a matched fading key.
% Channel identities remain distinct. Only coding/allocation/receiver-matched
% populations can share a fitting comparison; no waveform is relabeled TDL.
arguments
    folder (1,1) string
    referenceKey (1,1) struct
    targetKey (1,1) struct
    rvSequence (1,:) double {mustBeInteger}
end
assert(~isempty(rvSequence) && rvSequence(1)==0 && all(ismember(rvSequence,0:3)), ...
    'sixgr:calibration:ReferenceRV','Require the actual ordered HARQ RV history.');
assert(string(referenceKey.ChannelProfile)=="AWGN" && ...
    startsWith(string(referenceKey.ChannelProfileID),"AWGN_") && ...
    any(startsWith(string(targetKey.ChannelProfile),["TDL-","CDL-"])), ...
    'sixgr:calibration:ReferenceChannel','Require explicit AWGN reference and concrete fading target identities.');
channelFields={'ChannelProfile','ChannelProfileID'};
assert(isequaln(rmfield(referenceKey,channelFields),rmfield(targetKey,channelFields)), ...
    'sixgr:calibration:ReferenceKeyMismatch', ...
    'Reference and target must match every coding, allocation, port, RF and executed receiver key field.');
attempt=numel(rvSequence);
[rows,proof]=sixgr.calibration.readGrantCalibrationFeatureRows(folder,referenceKey,attempt);
assert(proof.AllPlannedEpisodesPresent && ~isempty(rows), ...
    'sixgr:calibration:ReferenceCollection','Complete the frozen reference plan before fitting.');
assert(all(cellfun(@(v)isequal(v,rvSequence),rows.RVSequence)), ...
    'sixgr:calibration:ReferenceRV','Do not combine different HARQ RV sequences.');
% For an identity reference every data-layer RE must have the same spatial
% SINR. Use this executed power/noise/precoder plane, NOT configured Es/N0.
configured=vertcat(rows.ConfiguredSNRHistory_dB{:});
actual=zeros(height(rows),attempt);
for k=1:height(rows)
    history=rows.SINRHistory{k};
    for a=1:attempt
        v=double(history{a}(:)); anchor=mean(v);
        assert(isfinite(anchor) && anchor>0 && ...
            max(abs(v-anchor))<=1e-9*anchor, ...
            'sixgr:calibration:NonflatAWGNReference', ...
            'Unequal layer powers or interference need a different reference, not one scalar SNR label.');
        actual(k,a)=10*log10(anchor);
    end
end
axes=cell(1,attempt); digits=zeros(height(rows),attempt);
for a=1:attempt
    levels=unique(configured(:,a)); measured=zeros(size(levels));
    for k=1:numel(levels)
        ix=configured(:,a)==levels(k); values=actual(ix,a);
        assert(max(values)-min(values)<=1e-8, ...
            'sixgr:calibration:ReferencePowerPlane','One configured point has inconsistent executed SINR.');
        measured(k)=mean(values); digits(ix,a)=k;
    end
    assert(numel(measured)>=2 && all(diff(measured)>0), ...
        'sixgr:calibration:ReferenceAxis','At least two measured ordered reference points per attempt are required.');
    axes{a}=measured;
end
shape=cellfun(@numel,axes); strides=[1 cumprod(shape(1:end-1))];
index=1+sum((digits-1).*strides,2);
if isscalar(shape), shape=[shape 1]; end
counts=cell(1,2); errors=cell(1,2); roles=["fit","validation"];
for k=1:2
    ix=rows.Role==roles(k);
    counts{k}=reshape(accumarray(index(ix),1,[prod(shape) 1]),shape);
    errors{k}=reshape(accumarray(index(ix),double(rows.CRCError(ix)),[prod(shape) 1]),shape);
end
% Empty conditional cells remain zero counts, never invented observations.
% Statistical support is decided by the frozen qualification policy later.
reference=struct('SINRAxes_dB',{axes},'TrialCount',counts{1},'ErrorCount',errors{1}, ...
    'ConfigurationSHA256',localHash(targetKey), ...
    'ReferencePhysicalKey',referenceKey,'TargetRuntimeKey',targetKey, ...
    'ReferencePhysicalKeySHA256',localHash(referenceKey),'RVSequence',rvSequence, ...
    'AxisSource',"executed_identity_awgn_nominal_pre_sync_per_data_layer_re_spatial_sinr", ...
    'SourceClassification',"executed_awgn_reference_for_fading_link_abstraction", ...
    'CalibrationQualified',false,'PrimaryStudyAccepted',false);
heldout=struct('TrialCount',counts{2},'ErrorCount',errors{2});
proof.ReferencePhysicalKeySHA256=localHash(referenceKey);
proof.TargetRuntimeKeySHA256=localHash(targetKey);
proof.ReferenceChannelRelabeledAsTarget=false;
end

function hash=localHash(value)
hash=string(sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(value),'UTF-8'))));
end
