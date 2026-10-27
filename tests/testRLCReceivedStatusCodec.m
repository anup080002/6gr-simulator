function ok=testRLCReceivedStatusCodec()
% Literal layouts from TS38.322 V18.2.0 Figure6.2.2.5-1/-2.
n=struct('NACKSN',3,'SOstart',4,'SOend',7,'NACKRange',[]);
for width=[12 18]
    e=sixgr.l2.rlc18.RLCStatusCodec.encodeReport(width,5,n);
    if width==12, literal=uint8([0 5 128 0 52 0 4 0 7]);
    else,literal=uint8([0 0 22 0 0 208 0 4 0 7]);end
    assert(isequal(e.Bytes,literal));
    d=sixgr.l2.rlc18.RLCStatusCodec.decodeReport(literal,width);
    assert(d.ACKSN==5 && isequal(d.NACKs,n));
    % R fields are ignored; CPT is still mandatory and unambiguously parsed.
    changed=literal;
    if width==12,changed(3)=bitor(changed(3),uint8(127));changed(5)=bitor(changed(5),uint8(1));
    else,changed(3)=bitor(changed(3),uint8(1));changed(6)=bitor(changed(6),uint8(7));end
    d=sixgr.l2.rlc18.RLCStatusCodec.decodeReport(changed,width);assert(isequal(d.NACKs,n));
    bad=literal;bad(1)=bitor(bad(1),uint8(16));rejects(@()sixgr.l2.rlc18.RLCStatusCodec.decodeReport(bad,width));
    rejects(@()sixgr.l2.rlc18.RLCStatusCodec.decodeReport(literal(1:end-1),width));
    rejects(@()sixgr.l2.rlc18.RLCStatusCodec.decodeReport([literal uint8(0)],width));
    wrapped=struct('NACKSN',2^width-2,'SOstart',[],'SOend',[],'NACKRange',3);
    e=sixgr.l2.rlc18.RLCStatusCodec.encodeReport(width,2,wrapped);
    d=sixgr.l2.rlc18.RLCStatusCodec.decodeReport(e.Bytes,width);assert(isequal(d.NACKs,wrapped));
    wrapped.NACKRange=5;rejects(@()sixgr.l2.rlc18.RLCStatusCodec.encodeReport(width,2,wrapped));
    empty=repmat(n,1,0);e=sixgr.l2.rlc18.RLCStatusCodec.encodeReport(width,5,empty);
    d=sixgr.l2.rlc18.RLCStatusCodec.decodeReport(e.Bytes,width);assert(isempty(d.NACKs)&&d.ACKSN==5);
end
ok=true;
end
function rejects(f)
thrown=false;try,f();catch e,thrown=strcmp(e.identifier,'sixgr:rlc:StatusEncodingFailed');end
assert(thrown,'Malformed STATUS must not change ARQ state.');
end
