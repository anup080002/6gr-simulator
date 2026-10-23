function budget=pdschProcessingTime(carrier,pdsch,numerologies,controlOverlapSymbols)
%PDSCHPROCESSINGTIME Capability-1 N1+d1,1 for the scheduled PDSCH.
% TS 38.214 V18.7.0 5.3/Table 5.3-1 (Release 18). This is a scheduling
% requirement, not measured decoder latency. The catalog's pos0 base is
% not the applicable N1 column when additional DM-RS is configured.
% Scope: one installed mapping configuration, ordinary licensed-spectrum
% HARQ. Priority/switching, multiple PDSCH occasions and capability 2 need
% their own procedure terms. UCI multiplexing adds its separate +1 term.
arguments
    carrier (1,1) nrCarrierConfig
    pdsch (1,1) nrPDSCHConfig
    numerologies (1,:) double
    controlOverlapSymbols (1,1) double {mustBeInteger,mustBeNonnegative}
end
assert(~isempty(numerologies) && all(isfinite(numerologies)) && ...
    all(numerologies==fix(numerologies)) && all(numerologies>=0), ...
    'sixgr:phy:frame:InvalidProcessingNumerologies', ...
    'PDSCH processing requires actual PDCCH, PDSCH and feedback numerologies.');
allocation=double(pdsch.SymbolAllocation);
assert(controlOverlapSymbols<=allocation(2), ...
    'sixgr:phy:frame:InvalidPDCCHPDSCHOverlap', ...
    'Control overlap cannot exceed the PDSCH duration.');
dmrs=nrPDSCHDMRSIndices(carrier,pdsch,'IndexStyle','subscript','IndexBase','0based');
symbols=unique(double(dmrs(:,2))).';
assert(~isempty(symbols),'sixgr:phy:frame:MissingProcessingDMRS', ...
    'PDSCH processing terms require a real DM-RS allocation.');
% Table 7.4.1.1.2-3's l1=12 is a single-symbol, mapping-A position;
% a mapping-B offset or the second symbol of a pair is not that l1.
additionalAt12=string(pdsch.MappingType)=="A" && pdsch.DMRS.DMRSLength==1 && ...
    any(symbols(2:end)==12);
if string(pdsch.MappingType)=="A"
    d11=max(0,7-(allocation(1)+allocation(2)-1));
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
budget=struct('Ticks',int64(-1),'Mu',NaN,'N1Symbols',NaN,'D11Symbols',d11, ...
    'DMRSAdditionalPosition',double(pdsch.DMRS.DMRSAdditionalPosition), ...
    'AdditionalDMRSStartsAt12',additionalAt12,'PDSCHDMRSSymbols',symbols, ...
    'PDCCHPDSCHOverlapSymbols',controlOverlapSymbols, ...
    'MappingType',string(pdsch.MappingType),'SymbolAllocation',allocation, ...
    'Source',"scheduled_pdsch_config_and_nr_dmrs_indices",'Unit',"Tc_ticks", ...
    'StandardReference',"TS38.214-v18.7.0-5.3_Table5.3-1", ...
    'Scope',"cap1_N1_plus_d11_excludes_priority_switching_and_UCI_mux_terms");
supported=[0 1 2 3 5 6];
nonPos0=[13+double(additionalAt12),13,20,24,96,192];
for mu=numerologies
    row=sixgr.phy.frame.TimingPolicyCatalog.capability1(mu);
    n1=row.PDSCHN1Symbols;
    if pdsch.DMRS.DMRSAdditionalPosition~=0, n1=nonPos0(supported==mu); end
    ticks=sixgr.phy.frame.TimingPolicyCatalog.processingSymbolTicks(n1+d11,mu);
    if ticks>budget.Ticks
        budget.Ticks=ticks; budget.Mu=mu; budget.N1Symbols=n1;
    end
end
end
