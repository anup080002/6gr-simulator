function reference = sib1FrequencyReference(carrier,cfg)
%SIB1FREQUENCYREFERENCE SI-RNTI FDRA authority from resolved MIB/CORESET0.
% TS 38.212 7.3.1.2.1: SI-RNTI uses CORESET0, not the connected DL BWP.
% RBStart is CRB-relative; waveform allocations use carrier-relative PRBs.
coreset=sixgr.util.structGet(cfg,'phy.sib1.resolvedCORESET0',struct());
if ~isstruct(coreset) || ~isscalar(coreset) || ...
        ~all(isfield(coreset,{'RBStart','NumRB'}))
    error('sixgr:phy:broadcast:MissingSIB1CORESET0', ...
        'SIB1 DCI requires MIB-derived CORESET0 RBStart and NumRB; the carrier size is not its FDRA reference.');
end
start=double(coreset.RBStart); count=double(coreset.NumRB);
validateattributes(start,{'numeric'},{'scalar','integer','finite','nonnegative'});
validateattributes(count,{'numeric'},{'scalar','integer','finite','positive','<=',275});
relative=start-double(carrier.NStartGrid);
if relative<0 || relative+count>double(carrier.NSizeGrid)
    error('sixgr:phy:broadcast:SIB1CORESET0OutsideCarrier', ...
        'The complete SIB1 CORESET0 frequency reference must lie inside the observed carrier.');
end
shared=sixgr.util.structGet(cfg,'phy.sib1.sharedSpectrum',false);
if ~(isscalar(shared) && (islogical(shared) || isnumeric(shared)) && ...
        ismember(double(shared),[0 1]))
    error('sixgr:phy:broadcast:InvalidSIB1SpectrumContext','SIB1 shared-spectrum context must be boolean.');
end
width=ceil(log2(count*(count+1)/2));
reserved=15+2*double(shared);
reference=struct('RBStart',start,'NumRB',count,'CarrierRelativeStart',relative, ...
    'RIVWidth',width,'ReservedBitCount',reserved,'PayloadLengthBits',width+13+reserved, ...
    'SharedSpectrum',logical(shared),'Source',"mib_derived_coreset0_SI_RNTI_TS38.212_7.3.1.2.1");
end
