function [llr,evidence]=demapFormat2EqualizerOutput(carrier,pucch,result)
% Exact non-interlaced Format-2 QPSK likelihood and TS 38.211 descrambling.
% No transmission-presence or word-acceptance decision is made here. Callers
% must retain their independent detector, configured coding and CRC gates.
assert(isa(carrier,'nrCarrierConfig') && isscalar(carrier) && ...
    isa(pucch,'nrPUCCH2Config') && isscalar(pucch), ...
    'sixgr:phy:pucch:InvalidFormat2DemapperContext', ...
    'Use the installed carrier and Format-2 reception resource.');
assert(~(isprop(pucch,'Interlacing') && pucch.Interlacing), ...
    'sixgr:phy:pucch:UnsupportedInterlacedLikelihood', ...
    'Interlaced OCC despreading requires its own response/covariance transform.');
[indices,info]=nrPUCCHIndices(carrier,pucch);
[llr,evidence]=sixgr.phy.rx.demapQPSKEqualizerOutput(result);
assert(numel(indices)==numel(result.EqualizedSymbols) && numel(llr)==double(info.G), ...
    'sixgr:phy:pucch:Format2EqualizerAllocationMismatch', ...
    'Equalized REs and soft-bit count must match the independent receive allocation.');
nid=pucch.NID;
if isempty(nid), nid=carrier.NCellID; end % Defined identity inheritance, not a rescue.
scrambling=nrPUCCHPRBS(nid,pucch.RNTI,numel(llr),'MappingType','signed');
llr=llr.*scrambling;
evidence.ScramblingIdentity=double(nid);
evidence.RNTI=double(pucch.RNTI);
evidence.CodedBitCount=numel(llr);
evidence.ScramblingSource="installed_PUCCH_identity_TS_38_211_6_3_2_5_1";
evidence.SignalPresenceDecisionMade=false;
end
