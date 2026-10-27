function ok=testProtocolIntegrityFailureDisposition()
% Original signed MAC/RLC/PDCP bytes, configured peer-key mismatch.
% Codec boundary only: no RF CRC result or received RRC activation claimed.
setup6GRSimToolkit('Verbose',false);
c=struct('UEID',"UE-001",'BearerID',"DRB-1",'QFI',9,'DRBID',1, ...
 'PduSessionID',1,'LCID',4,'PDCPSNBits',18,'RLCSNBits',18, ...
 'ConfigurationEpoch',1,'Direction',"UL",'SampleRateHz',1000,'ClockEpoch',1, ...
 'CipherAlgorithm',"NEA0",'IntegrityAlgorithm',"128-NIA2", ...
 'IntegrityKey',uint8(0:15),'CipherKey',zeros(1,16,'uint8'),'SecurityActive',true);
tx=sixgr.protocol.ProtocolRuntime(c);other=c;other.IntegrityKey=uint8(16:31);
rx=sixgr.protocol.ProtocolRuntime(other);
p=tx.transmit('original',uint8(1:19),0);
% Explicit clock event precedes observation. A rejected PDU cannot consume
% current PDCP COUNT or fabricate completion of this original application.
rx.advance(.001);before=rx.securityState();
[delivered,completed,~,status]=rx.receive(p,.001);after=rx.securityState();
assert(~delivered&&isempty(completed)&&status=="integrity_failed_discarded");
assert(isequaln(before.RXState,after.RXState)&&rx.PacketsDelivered==0);
rows=rx.takeSecurityIndications();assert(isscalar(rows)&&rows.InferredPDCPCount==0&& ...
 ~rows.PDCPCountAccepted&&~rows.TerminalApplicationDrop&&rows.ApplicationBytesDelivered==0&& ...
 rows.Sample==1&&rows.SampleRateHz==1000&&rows.ClockEpoch==1&&rows.SampleClockQualified&& ...
 rows.MACSHA256==p.MACSHA256&&rows.RLCEncodedSHA256==p.EncodedSHA256);
assert(isequaln(rx.originalSecurityIndication(rows.IndicationID),rows)&&isempty(rx.takeSecurityIndications()));
[delivered,completed]=rx.receive(p,.002);
assert(~delivered&&isempty(completed)&&isempty(rx.takeSecurityIndications()), ...
 'Duplicate lower-layer bytes must not mint another integrity observation.');
% Regression for the lost-completion bug: actual correctly signed COUNT1
% is buffered behind missing COUNT0. Its timer expires at the same receive
% call as a later COUNT2 with a damaged MAC-I at a declared codec boundary.
clocked=c;clocked.ReorderingTime_s=.002;
r=sixgr.protocol.ProtocolRuntime(clocked);
r.transmit('missing-count-zero',uint8([7 8]),0);
valid=r.transmit('buffered-valid',uint8([21 22 23]),0);
current=r.transmit('bad-current',uint8([31 32 33]),0);
[delivered,completed]=r.receive(valid,.001);
bufferedState=r.securityState();
assert(~delivered&&isempty(completed)&&bufferedState.RXState.RX_DELIV==0);
% This is explicit lower-layer codec corruption, not claimed successful PHY.
% Preserve original data bytes/COUNT; change only its transmitted MAC-I and
% rebuild exact enclosing MAC byte/hash receipts for this received input.
current.Bytes(end)=bitxor(current.Bytes(end),uint8(1));
current.EncodedSHA256=sixgr.protocol.ProtocolHash.bytes(current.Bytes);
mac=sixgr.l2.mac.MACPDUAssembler.assemble('UL', ...
    struct('LCID',current.LCID,'Payload',current.Bytes,'OwnerID',"declared_codec_MACI_damage"),numel(current.MACBytes));
current.MACBytes=mac.Bytes;current.MACSHA256=mac.SHA256;
[delivered,completed,~,status]=r.receive(current,.004);
assert(~delivered&&status=="integrity_failed_discarded"&&isscalar(completed)&& ...
    completed.PacketID=="buffered-valid"&&completed.PDCPCount==1&& ...
    isequal(completed.Payload,uint8([21 22 23]))&&completed.DeliveryTime_s==.004);
releasedState=r.securityState();
assert(r.PacketsDelivered==1&&releasedState.RXState.RX_DELIV==2&& ...
    isempty(releasedState.RXState.Buffered)&&isempty(r.advance(.004)));
failed=r.takeSecurityIndications();assert(isscalar(failed)&&failed.InferredPDCPCount==2&& ...
    failed.PacketID=="bad-current"&&~failed.PDCPCountAccepted);
% Serialize the actual original indication; do not invent app/HARQ rows.
folder=tempname;mkdir(folder);persistence=sixgr.util.persistenceScope(true); %#ok<NASGU>
T=struct2table(failed,'AsArray',true);
[~,paths]=sixgr.truth.publishPacketDeliveryLedgers(struct('ProtocolSecurityIndicationsTable',T),folder);
written=sixgr.util.csvReadTable(paths.ProtocolSecurityIndicationsTable,'TextType','string');
assert(height(written)==1&&string(written.IndicationID)==failed.IndicationID&& ...
    string(written.PDCPPDUSHA256)==failed.PDCPPDUSHA256&&written.ApplicationBytesDelivered==0&& ...
    ~written.TerminalApplicationDrop&&~written.PDCPCountAccepted);
% Read-only inventory cannot lazily create a protocol owner.
b=sixgr.protocol.WaveformProtocolBridge(struct('enabled',true,'strict',true),2);
assert(~b.hasInstalledRuntime(1)&&~b.hasInstalledRuntime(2)&&~b.hasInstalledRuntime(1));
fprintf('PROTOCOL_INTEGRITY_FAILURE_DISPOSITION_PASS original_signed_bytes=1 key_mismatch=1 codec_only=1 no_RF_claim=1 no_app_credit=1\n');
ok=true;
end
