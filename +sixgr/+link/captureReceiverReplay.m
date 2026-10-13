function evidence = captureReceiverReplay(cfg,direction,waveform,receiverArgs,rx,context)
%CAPTURERECEIVERREPLAY Bounded exact RX inputs, saved only after reception.
% This diagnostic neither reconstructs samples nor changes a receiver result.
% The cap is shared by all points/UEs using one run folder, per direction.
% Run artifacts have one writer, as do the raw trial tables in these runners.
evidence=struct('Status',"disabled",'MATFile',"",'SHA256',"",'WaveformSHA256',"");
policy=string(sixgr.util.structGet(cfg,'outputs.receiverReplayCapturePolicy','none'));
assert(isscalar(policy) && any(policy==["none","failed","all"]), ...
    'sixgr:link:ReceiverReplayPolicy','Use receiver replay policy none, failed or all.');
if policy=="none", return; end
limit=double(sixgr.util.structGet(cfg,'outputs.receiverReplayCaptureMaxTrials',0));
validateattributes(limit,{'numeric'},{'scalar','integer','positive','finite'});
direction=string(direction);
assert(isscalar(direction) && any(direction==["DL","UL"]), ...
    'sixgr:link:ReceiverReplayDirection','Use DL or UL.');
assert(isfield(rx,'TBCRCPass') && isscalar(rx.TBCRCPass), ...
    'sixgr:link:ReceiverReplayCRC','Capture selection needs an actual receiver CRC outcome.');
if policy=="failed" && logical(rx.TBCRCPass)
    evidence.Status="not_selected_crc_pass"; return;
end
root=string(sixgr.util.structGet(cfg,'run.rootRunFolder',''));
assert(strlength(root)>0 && isfolder(root), ...
    'sixgr:link:ReceiverReplayRoot','Enabled replay capture requires an existing run.rootRunFolder.');
relative=fullfile('air_interface','mat','receiver_replay',lower(direction));
folder=fullfile(root,relative);
existing=dir(fullfile(folder,'capture_*.mat'));
if numel(existing)>=limit
    evidence.Status="capture_limit_reached"; return;
end
assert(isnumeric(waveform) && isfloat(waveform) && ismatrix(waveform) && ...
    ~isempty(waveform) && all(isfinite(waveform),'all') && iscell(receiverArgs), ...
    'sixgr:link:ReceiverReplayInput','Capture exact finite received samples and the actual receiver argument cell.');
name=sprintf('capture_%06d.mat',numel(existing)+1);
path=fullfile(folder,name);
assert(~isfile(path),'sixgr:link:ReceiverReplayOverwrite','Never overwrite an existing receiver capture.');
receiver="sixgr.phy.dl.PDSCH_Rx";
if direction=="UL", receiver="sixgr.phy.ul.PUSCH_Rx"; end
waveHash=string(sixgr.channel.ChannelFactory.runtimeNumericArraySHA256(waveform));
capture=struct('Contract',"exact_receiver_replay/v1",'Direction',direction, ...
    'Source',"executed_receiver_input_not_reconstructed", ...
    'ReceiverFunction',receiver,'ReceiverSourceSHA256',string(sixgr.util.sha256File(which(receiver))), ...
    'Config',cfg,'Waveform',waveform,'WaveformSHA256',waveHash, ...
    'ReceiverArguments',{receiverArgs},'ReceiverResult',rx,'Context',context, ...
    'CapturePolicy',policy,'CaptureLimitPerDirection',limit, ...
    'CaptureUsedByReceiver',false,'AdditionalChannelExecutions',0);
sixgr.util.matSave(path,struct('ReceiverReplay',capture),'UseArtifactStore',false);
evidence.Status="captured_exact_receiver_input";
evidence.MATFile=string(fullfile(relative,name));
evidence.SHA256=string(sixgr.util.sha256File(path));
evidence.WaveformSHA256=waveHash;
end
