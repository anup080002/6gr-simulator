function ok=testNRTemporaryCRNTIRange()
% TS 38.321 Release 18 Table 7.1-1: temporary C-RNTI 0001..FFF2.
cfg=raStrictAnchorConfig(); ra=sixgr.mac.ra.RAConfig(cfg);
grant=sixgr.mac.ra.buildRARULGrant(ra);
base=sixgr.mac.ra.encodeMACRAR('RAPID',ra.PreambleIndex,'ULGrant',grant);
for value=[1 65519 65520 65521 65522]
    tx=sixgr.mac.ra.encodeMACRAR('RAPID',ra.PreambleIndex,'ULGrant',grant,'TemporaryCRNTI',value);
    bytes=base.Bytes;
    bytes(end-1:end)=uint8([floor(value/256);mod(value,256)]);
    assert(isequal(tx.Bytes,bytes),'RAR identity occupies the final two network-order octets.');
    decoded=sixgr.mac.ra.decodeMACRAR(bytes,ra);
    assert(decoded.TemporaryCRNTI==value && ...
        sixgr.mac.ra.validateRARULGrant(decoded.ULGrant,ra).Valid);
    bound=sixgr.mac.ra.bindReceivedRARIdentity(ra,decoded.ULGrant);
    assert(bound.TempCRNTI==value);
    timer=sixgr.mac.ra.ContentionResolutionState('001122334455',value,int64(0),int64(100));
    assert(timer.TemporaryCRNTI==value);
end
for value=[0 65523:65535]
    bytes=base.Bytes; bytes(end-1:end)=uint8([floor(value/256);mod(value,256)]);
    rejected=false;
    try, sixgr.mac.ra.decodeMACRAR(bytes,ra);
    catch ME, rejected=string(ME.identifier)=="sixgr:mac:ra:InvalidMACRARField"; end
    assert(rejected,'Reserved/common RNTI must not be accepted as temporary C-RNTI.');
end
ok=true; disp('NR_TEMPORARY_CRNTI_RANGE_PASS: independent octets, legal 0001..FFF2 and reserved rejection.');
end
