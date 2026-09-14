function ok=testChannelCarrierFrequencyAuthority()
% Config/identity authority, not a waveform or 12 dB qualification.
setup6GRSimToolkit('Verbose',false);
cfg=sixgr.config.defaultConfig();
assert(~isfield(cfg.phy,'fc_Hz'), ...
    'This regression must exercise the unnormalized catalog frequency.');
catalogFrequency=cfg.channel.fc_Hz;
assert(sixgr.channel.ChannelFactory.resolveCarrierFrequency(cfg)==catalogFrequency);
key=sixgr.channel.ChannelFactory.runtimeChannelKey(cfg,'DL');
assert(contains(string(key),':fc='+string(catalogFrequency)));
[~,meta]=sixgr.channel.ChannelFactory.create(cfg,'Model','AWGN');
assert(meta.Fc_Hz==catalogFrequency);
normalized=sixgr.config.normalizeConfig(cfg);
assert(sixgr.channel.ChannelFactory.resolveCarrierFrequency(normalized)==catalogFrequency);
assert(strcmp(key,sixgr.channel.ChannelFactory.runtimeChannelKey(normalized,'DL')));

% A resolved PHY frequency overrides the catalog default, as normalizeConfig
% already specifies. An old alias must not override either canonical field.
cfg.carrier.fc_Hz=2.1e9;
assert(sixgr.channel.ChannelFactory.resolveCarrierFrequency(cfg)==catalogFrequency);
cfg.phy.fc_Hz=6.1e9;
assert(sixgr.channel.ChannelFactory.resolveCarrierFrequency(cfg)==6.1e9);
[~,meta]=sixgr.channel.ChannelFactory.create(cfg,'Model','AWGN');
assert(meta.Fc_Hz==6.1e9);
assert(~strcmp(key,sixgr.channel.ChannelFactory.runtimeChannelKey(cfg,'DL')));
cfg.phy=rmfield(cfg.phy,'fc_Hz'); cfg.channel=rmfield(cfg.channel,'fc_Hz');
assert(sixgr.channel.ChannelFactory.resolveCarrierFrequency(cfg)==2.1e9);
[~,meta]=sixgr.channel.ChannelFactory.create(cfg,'Model','AWGN');
assert(meta.Fc_Hz==2.1e9);
cfg.carrier=rmfield(cfg.carrier,'fc_Hz');
expectError(@()sixgr.channel.ChannelFactory.runtimeChannelKey(cfg,'DL'), ...
    'ChannelFactory:MissingCarrierFrequency');
expectError(@()sixgr.channel.ChannelFactory.create(cfg,'Model','AWGN'), ...
    'ChannelFactory:MissingCarrierFrequency');
% Explicit standalone factory options retain their existing authority.
[~,meta]=sixgr.channel.ChannelFactory.create(cfg,'Model','AWGN','Fc_Hz',5.8e9);
assert(meta.Fc_Hz==5.8e9);

bad={NaN,Inf,-Inf,0,-1,[],[1e9 2e9],1e9+1i,'4e9',true};
for k=1:numel(bad)
    invalid=cfg; invalid.channel.fc_Hz=4e9; invalid.phy.fc_Hz=bad{k};
    expectError(@()sixgr.channel.ChannelFactory.resolveCarrierFrequency(invalid), ...
        'ChannelFactory:InvalidCarrierFrequency');
    expectError(@()sixgr.channel.ChannelFactory.runtimeChannelKey(invalid,'DL'), ...
        'ChannelFactory:InvalidCarrierFrequency');
    expectError(@()sixgr.channel.ChannelFactory.create(invalid,'Model','AWGN'), ...
        'ChannelFactory:InvalidCarrierFrequency');
end
ok=true;
fprintf('CHANNEL_CARRIER_FREQUENCY_AUTHORITY_PASS config_identity_only=1 waveform_qualification=0\n');
end

function expectError(action,id)
try
    action();
catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, received %s: %s', ...
        id,cause.identifier,cause.message);
    return;
end
error('testChannelCarrierFrequencyAuthority:MissingError','Expected %s.',id);
end
