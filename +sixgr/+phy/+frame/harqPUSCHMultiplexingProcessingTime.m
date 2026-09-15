function budget=harqPUSCHMultiplexingProcessingTime(dlCarrier,pdsch,ulCarrier,pusch,numerologies,controlOverlapSymbols)
% TS 38.213 9.2.5 / TS 38.214 5.3, 6.4 capability-1 allocation terms.
% This is a duration calculation, NOT an admission or receiver-availability
% decision. The caller must check the earliest advanced UL symbol against
% every PDSCH/PDCCH endpoint in the overlapping group. Switching, BWP-change
% d2,2 and aperiodic-CSI budgets are not implemented by this helper.
arguments
    dlCarrier (1,1) nrCarrierConfig
    pdsch (1,1) nrPDSCHConfig
    ulCarrier (1,1) nrCarrierConfig
    pusch (1,1) nrPUSCHConfig
    numerologies (1,:) double
    controlOverlapSymbols (1,1) double {mustBeInteger,mustBeNonnegative}
end
assert(~isempty(numerologies) && all(isfinite(numerologies)) && ...
    all(numerologies==fix(numerologies)) && all(numerologies>=0), ...
    'sixgr:phy:frame:InvalidMultiplexingNumerologies', ...
    'Supply all actual PDCCH/PDSCH/PUCCH/PUSCH numerologies in the group.');
mus=[numerologies,log2(double(dlCarrier.SubcarrierSpacing)/15), ...
    log2(double(ulCarrier.SubcarrierSpacing)/15)];
% Unlike standalone processing, 38.213 9.2.5 selects the smallest SCS.
mu=min(mus);
row=sixgr.phy.frame.TimingPolicyCatalog.capability1(mu);
allocation=double(pdsch.SymbolAllocation);
assert(controlOverlapSymbols<=allocation(2), ...
    'sixgr:phy:frame:InvalidPDCCHPDSCHOverlap','Control overlap cannot exceed PDSCH duration.');
dmrs=nrPDSCHDMRSIndices(dlCarrier,pdsch,'IndexStyle','subscript','IndexBase','0based');
symbols=unique(double(dmrs(:,2))).';
assert(~isempty(symbols),'sixgr:phy:frame:MissingProcessingDMRS', ...
    'PDSCH processing terms require a real DM-RS allocation.');
% For double-symbol DM-RS, l1 is the first symbol of the additional pair,
% not the second symbol merely happening to have index 12.
dmrsStarts=symbols(1:double(pdsch.DMRS.DMRSLength):end);
additionalAt12=any(dmrsStarts(2:end)==12);
n1=row.PDSCHN1Symbols;
if pdsch.DMRS.DMRSAdditionalPosition~=0
    supported=[0 1 2 3 5 6];
    other=[13+double(additionalAt12),13,20,24,96,192];
    n1=other(supported==mu);
end
if string(pdsch.MappingType)=="A"
    last=allocation(1)+allocation(2)-1;
    d11=max(0,7-last);
elseif allocation(2)>=7
    d11=0;
elseif allocation(2)>=4
    d11=7-allocation(2);
elseif allocation(2)==3
    d11=3+min(controlOverlapSymbols,1);
elseif allocation(2)==2
    d11=3+controlOverlapSymbols;
else
    error('sixgr:phy:frame:UnsupportedPDSCHProcessingAllocation', ...
        'Capability-1 mapping-B processing requires at least two PDSCH symbols.');
end
ul=sixgr.phy.frame.puschPreparationProcessingTime(ulCarrier,pusch,mu);
budget=struct('Mu',mu,'N1Symbols',n1,'D11Symbols',d11, ...
    'N2Symbols',ul.N2Symbols,'D21Symbols',ul.D21Symbols, ...
    'PDSCHTicks',sixgr.phy.frame.TimingPolicyCatalog.processingSymbolTicks(n1+d11+1,mu), ...
    'PDCCHTicks',sixgr.phy.frame.TimingPolicyCatalog.processingSymbolTicks(ul.N2Symbols+ul.D21Symbols+1,mu), ...
    'DMRSAdditionalPosition',double(pdsch.DMRS.DMRSAdditionalPosition), ...
    'AdditionalDMRSStartsAt12',additionalAt12,'PDSCHDMRSSymbols',symbols, ...
    'PDCCHPDSCHOverlapSymbols',controlOverlapSymbols, ...
    'PUSCHAllocationTerms',ul,'Unit',"Tc_ticks", ...
    'StandardReference',"TS38.213-v18.8.0-9.2.5_TS38.214-v18.8.0-5.3_6.4", ...
    'Scope',"cap1_N1_d11_N2_d21_plus1_excludes_switching_d22_and_aperiodic_CSI");
end
