function ok=testSharedDataRXTransportIdentity()
% Constructed TX-ledger negatives, not measured PHY qualification.
g=struct('RNTI',4660,'UEIndex',1,'Slot',41,'TransportBlockId',"tb-epoch1", ...
    'TBId',"tb-epoch1",'PHYGrant',struct('GrantContextId',"attempt-41"), ...
    'HARQ',struct('HarqID',0,'NDI',true,'RV',0,'NDIEpoch',1));
identity=struct('TransmissionID',"physical-attempt-41",'UEIndex',1, ...
    'Direction',"DL",'RNTI',4660,'PHYGrantContextId',"attempt-41");
bits=int8(mod((1:64)',2));
record=struct('Identity',identity,'Grant',g,'TransportBlockBits',bits);
state=struct('SharedDataTXLedger',{{record}});
h=struct('SharedTransmissionID',identity.TransmissionID);
sixgr.truth.validateSharedDataReceptionTX(state,h,g,bits,1,'DL',41);
bad=g; bad.TransportBlockId="tb-epoch2"; bad.TBId="tb-epoch2";
reject(@()sixgr.truth.validateSharedDataReceptionTX(state,h,bad,bits,1,'DL',41));
bad=g; bad.HARQ.NDIEpoch=2;
reject(@()sixgr.truth.validateSharedDataReceptionTX(state,h,bad,bits,1,'DL',41));
ok=true;
end
function reject(f)
try, f(); catch ex
    assert(strcmp(ex.identifier,'sixgr:truth:SharedDataRXTXBindingMismatch'),ex.message); return;
end
error('test:MissingTransportIdentityRejection','RX replaced the actual transmitted TB or NDI epoch.');
end
