function ra=bindReceivedRARIdentity(ra,grant)
% Called only after matching CRC-valid RAR/grant acceptance. TS 38.321 5.1.4.
% Never consult the gNB allocator or the configured temporary identity.
rnti=sixgr.util.structGet(grant,'TemporaryCRNTI',NaN);
validateattributes(rnti,{'numeric'},{'scalar','real','finite','integer','>=',1,'<=',65522});
ra.TempCRNTI=double(rnti);
% This is the prospective CCCH contention identity, not connected-state
% adoption. Existing contention-success guards remain mandatory.
ra.FinalCRNTI=double(rnti);
end
