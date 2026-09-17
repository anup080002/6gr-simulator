function receipts=exportLabIQ(root,wave,fs,fc,direction,point,keysight)
%EXPORTLABIQ Preserve exact TX/RX separately; normalize only playback copies.
assert(any(string(point)==["TX","RX"]) && any(string(direction)==["DL","UL"]));
assert(ismatrix(wave) && ~isempty(wave) && all(isfinite(wave(:))));
folder=fullfile(root,'waveform',lower(direction+"_"+point));
mkdir(folder);
raw=fullfile(folder,'raw_iq.mat');
sixgr.util.matSave(raw,struct('Waveform',wave,'SampleRateHz',fs,'CenterFrequencyHz',fc, ...
    'Direction',direction,'CapturePoint',point,'StandardNR',false),UseArtifactStore=false);
saved=load(raw,'Waveform');
assert(isequal(saved.Waveform,wave),'sixgr:research:IQReadback','Exact IQ MAT readback differs.');
clear saved
scale=max(abs([real(wave(:));imag(wave(:))]));
assert(isfinite(scale) && scale>0,'sixgr:research:EmptyPlayback','Cannot normalize a silent endpoint.');
receipts=struct([]);
for port=1:size(wave,2)
    row=struct('Direction',direction,'CapturePoint',point,'Port',port, ...
        'SampleCount',size(wave,1),'SampleRateHz',fs,'CenterFrequencyHz',fc, ...
        'CommonEndpointFullScale',scale,'RawMAT',string(raw),'RawSHA256',localHash(raw), ...
        'WIQFile',"",'WIQSHA256',"",'VSAMATFile',"",'VSAMATSHA256',"", ...
        'QuantizationMaxError',NaN,'ClippedComponents',0, ...
        'InstrumentImportVerified',false,'StandardNR',false);
    if keysight
        normalized=wave(:,port)/scale;
        pair=[real(normalized),imag(normalized)];
        assert(all(abs(pair(:))<=1),'sixgr:research:PlaybackClipping','Unexpected playback clipping.');
        quantized=int16(round(pair*32767));
        file=fullfile(folder,sprintf('port_%d.wiq',port));
        fid=fopen(file,'w','ieee-le'); assert(fid>=0); closer=onCleanup(@()fclose(fid));
        written=fwrite(fid,quantized.','int16');
        assert(written==numel(quantized)); clear closer
        fid=fopen(file,'r','ieee-le'); assert(fid>=0); closer=onCleanup(@()fclose(fid));
        back=fread(fid,[2 Inf],'*int16').'; clear closer
        assert(isequal(back,quantized),'sixgr:research:WIQReadback','WIQ readback differs.');
        err=max(abs(double(back(:))/32767-pair(:)));
        assert(err<=.5/32767+eps,'sixgr:research:WIQQuantization','WIQ exceeds quantization bound.');
        vsa=fullfile(folder,sprintf('port_%d_vsa.mat',port));
        sixgr.util.matSave(vsa,struct('Y',single(normalized),'XDelta',1/fs, ...
            'InputCenter',fc,'InputZoom',1,'XDomain',2),UseArtifactStore=false);
        v=load(vsa);
        assert(isequal(v.Y,single(normalized)) && v.XDelta==1/fs);
        row.WIQFile=string(file); row.WIQSHA256=localHash(file);
        row.VSAMATFile=string(vsa); row.VSAMATSHA256=localHash(vsa);
        row.QuantizationMaxError=err;
    end
    if isempty(receipts), receipts=row; else, receipts(port)=row; end %#ok<AGROW>
end
end

function hash=localHash(path)
fid=fopen(path,'r'); assert(fid>=0); closer=onCleanup(@()fclose(fid)); %#ok<NASGU>
hash=string(sixgr.util.sha256Hex(fread(fid,Inf,'*uint8')));
end
