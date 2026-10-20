function ok=testBroadcastReceiveContextOwnership()
setup6GRSimToolkit('Verbose',false);
% Deterministic ownership fixture, not a physical performance claim.
wave=complex(reshape(1:2048,512,4),-1);
tx=struct('Waveform',wave,'SSBWaveform',2*wave,'Symbols',[1;1i]);
p=struct('Tx',tx,'RuntimeTx',tx,'TransmitSamples',wave,'NumSamples',512, ...
    'TxInfo',struct('PortGrid',ones(24,14,4),'PowerContext',struct('EPRE',1)));
c=struct('Prepared',p,'Prototype',struct('PreparedBroadcast',p,'Status',"PREPARED"));
out=sixgr.truth.compactBroadcastReceiveContext(c);
assert(~isfield(out.Prototype,'PreparedBroadcast') && ~isfield(out.Prepared,'RuntimeTx') && ...
    ~isfield(out.Prepared.TxInfo,'PortGrid') && isequal(out.Prepared.Tx,tx) && ...
    isequal(out.Prepared.TransmitSamples,wave) && out.Prototype.Status==c.Prototype.Status);
assert(isequal(out,sixgr.truth.compactBroadcastReceiveContext(out)));
bad=c; bad.Prototype.PreparedBroadcast.TransmitSamples(1)=0;
try
    sixgr.truth.compactBroadcastReceiveContext(bad); error('test:MissingGuard','Expected mismatch guard.');
catch cause
    assert(strcmp(cause.identifier,'sixgr:truth:BroadcastDuplicateMismatch'));
end
path=[tempname '.mat']; save(path,'out','-v7.3'); restored=load(path,'out');
assert(isequal(restored.out,out));
ok=true;
end
