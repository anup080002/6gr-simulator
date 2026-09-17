function package_two_channel_vsa(sourceRoot,outputRoot)
% Repackage existing normalized port arrays; do not execute or alter PHY.
% Keysight documents Y1/Y2 for two-channel recordings. Import is unverified.
assert(isfolder(sourceRoot) && ~isfolder(outputRoot),'Use an existing source and a new output directory.');
iq=readtable(fullfile(sourceRoot,'waveform','iq_manifest.csv'), ...
    'Delimiter',',','ReadVariableNames',true,'TextType','string');
assert(height(iq)==8 && all(iq.Port==1 | iq.Port==2));
mkdir(outputRoot);
receipts=struct([]);
for direction=["DL","UL"]
    for point=["TX","RX"]
        rows=sortrows(iq(iq.Direction==direction & iq.CapturePoint==point,:),'Port');
        assert(height(rows)==2 && isequal(rows.Port,[1;2]));
        assert(rows.CommonEndpointFullScale(1)==rows.CommonEndpointFullScale(2));
        a=load(rows.VSAMATFile(1)); b=load(rows.VSAMATFile(2));
        fields={'XDelta','InputCenter','InputZoom','XDomain'};
        for k=1:numel(fields), assert(isequal(a.(fields{k}),b.(fields{k}))); end
        assert(isa(a.Y,'single') && isa(b.Y,'single') && iscolumn(a.Y) && iscolumn(b.Y));
        assert(numel(a.Y)==rows.SampleCount(1) && numel(b.Y)==rows.SampleCount(2));
        assert(numel(a.Y)==numel(b.Y) && all(isfinite(a.Y)) && all(isfinite(b.Y)));
        assert(a.XDelta==1/rows.SampleRateHz(1) && a.InputCenter==rows.CenterFrequencyHz(1));
        recording=struct('Y1',a.Y,'Y2',b.Y,'XDelta',a.XDelta,'XStart',0, ...
            'InputCenter',a.InputCenter,'InputZoom',a.InputZoom,'XDomain',a.XDomain);
        file=fullfile(outputRoot,lower(direction+"_"+point+"_two_channel_vsa.mat"));
        assert(~isfile(file));
        save(file,'-struct','recording','-v7');
        back=load(file);
        assert(isequal(back,recording),'Two-channel recording does not match the original port arrays.');
        row=struct('Direction',direction,'CapturePoint',point,'Channels',2, ...
            'SamplesPerChannel',numel(a.Y),'SampleRateHz',1/a.XDelta, ...
            'CenterFrequencyHz',a.InputCenter,'StartSample',0, ...
            'CommonEndpointFullScale',rows.CommonEndpointFullScale(1), ...
            'SourcePort1',rows.VSAMATFile(1),'SourcePort2',rows.VSAMATFile(2), ...
            'JointRecording',string(file),'ExactPortArrayReadback',true, ...
            'Resampled',false,'AdditionalNoiseApplied',false, ...
            'WaveformRegenerated',false,'KeysightImportVerified',false, ...
            'Representation',"normalized_playback_not_dBm");
        if isempty(receipts), receipts=row; else, receipts(end+1)=row; end %#ok<AGROW>
        fprintf('TWO_CHANNEL_VSA_READBACK_PASS %s %s samples_per_channel=%d file=%s\n',direction,point,numel(a.Y),file);
        clear a b recording back
    end
end
writetable(struct2table(receipts),fullfile(outputRoot,'two_channel_manifest.csv'));
fprintf('TWO_CHANNEL_VSA_PACKAGE_PASS recordings=4 source_IQ_unchanged=1 keysight_import_verified=0\n');
end
