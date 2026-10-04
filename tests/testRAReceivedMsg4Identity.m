function ok=testRAReceivedMsg4Identity()
% Codec/ownership guards, not a physical or full NR MAC/RRC qualification.
tx=sixgr.mac.ra.buildMsg4ContentionResolution("001122334455",'FinalCRNTI',4660);
decoded=sixgr.mac.ra.parseMsg4ContentionResolution(tx.PayloadBits);
identity=sixgr.mac.ra.receivedMsg4Identity(decoded,true,true,"001122334455");
assert(identity.RNTI==4660 && ~identity.MACRRCStandardsQualified && ...
    identity.Source=="decoded_msg4_payload_after_contention_match");
for transaction=0:3
    for lcid=[1 32]
        issued=sixgr.mac.ra.buildMsg4ContentionResolution("001122334455", ...
            'FinalCRNTI',4660,'TransactionID',transaction,'SRB1LCID',lcid);
        message=sixgr.mac.ra.parseMsg4ContentionResolution(issued.PayloadBits);
        setup=sixgr.mac.ra.receivedRRCSetup(message,true,true,"001122334455");
        assert(setup.TransactionID==transaction && setup.SRB1LCID==lcid && ...
            setup.RNTI==4660 && ~setup.MACRRCStandardsQualified);
    end
end
bad=decoded; bad.RRCSetupPresent=false;
reject(@()sixgr.mac.ra.receivedRRCSetup(bad,true,true,"001122334455"), ...
    'sixgr:mac:ra:MissingReceivedRRCSetup');
for value=[NaN Inf -1 .5 4]
    bad=decoded; bad.RRCSetup.TransactionID=value;
    reject(@()sixgr.mac.ra.receivedRRCSetup(bad,true,true,"001122334455"), ...
        'sixgr:mac:ra:InvalidReceivedRRCSetup');
end
for value=[NaN Inf 0 .5 33]
    bad=decoded; bad.RRCSetup.SRB1LCID=value;
    reject(@()sixgr.mac.ra.receivedRRCSetup(bad,true,true,"001122334455"), ...
        'sixgr:mac:ra:InvalidReceivedRRCSetup');
end
reject(@()sixgr.mac.ra.receivedMsg4Identity(decoded,false,true,"001122334455"), ...
    'sixgr:mac:ra:UnacceptedMsg4Identity');
reject(@()sixgr.mac.ra.receivedMsg4Identity(decoded,true,false,"001122334455"), ...
    'sixgr:mac:ra:UnacceptedMsg4Identity');
reject(@()sixgr.mac.ra.receivedMsg4Identity(decoded,true,true,"112233445566"), ...
    'sixgr:mac:ra:Msg4IdentityMismatch');
for value=[NaN Inf 0 -1 1.5 65523:65536]
    bad=decoded; bad.FinalCRNTI=value;
    reject(@()sixgr.mac.ra.receivedMsg4Identity(bad,true,true,"001122334455"), ...
        'sixgr:mac:ra:InvalidReceivedCRNTI');
    rejected=false;
    try, sixgr.mac.ra.buildMsg4ContentionResolution("001122334455",'FinalCRNTI',value);
    catch, rejected=true; end
    assert(rejected,'Malformed identity must not be saturated/rounded into valid transmitted bytes.');
end
for value=[1 65522]
    boundary=sixgr.mac.ra.buildMsg4ContentionResolution("001122334455",'FinalCRNTI',value);
    boundary=sixgr.mac.ra.parseMsg4ContentionResolution(boundary.PayloadBits);
    accepted=sixgr.mac.ra.receivedMsg4Identity(boundary,true,true,"001122334455");
    assert(accepted.RNTI==value);
end
bad=rmfield(decoded,'FinalCRNTI');
reject(@()sixgr.mac.ra.receivedMsg4Identity(bad,true,true,"001122334455"), ...
    'sixgr:mac:ra:InvalidReceivedCRNTI');
bad=decoded; bad.EncodingProfile="unqualified_other_codec";
reject(@()sixgr.mac.ra.receivedMsg4Identity(bad,true,true,"001122334455"), ...
    'sixgr:mac:ra:UnsupportedMsg4IdentityEncoding');
ok=true;
end
function reject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Expected %s got %s',id,ME.identifier); return; end
error('test:MissingRejection','Expected %s',id);
end
