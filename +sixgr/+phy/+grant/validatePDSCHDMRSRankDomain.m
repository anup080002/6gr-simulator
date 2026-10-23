function evidence = validatePDSCHDMRSRankDomain(cfg)
%VALIDATEPDSCHDMRSRANKDOMAIN Preflight the configured DL resource contract.
% This is configuration validation, not received CSI or a scheduled grant.
% Use the same port resolver/native factory as exact scheduler accounting;
% do not infer required CDM groups from rank or widen the configured count.
evidence=struct('Ranks',zeros(1,0),'PortSets',{{}},'CDMGroups',{{}}, ...
    'NumCDMGroupsWithoutData',zeros(1,0));
if ~logical(sixgr.util.structGet(cfg,'phy.pdsch.enable',false)), return; end
bootstrap=double(sixgr.util.structGet(cfg,'phy.pdsch.numLayers', ...
    sixgr.util.structGet(cfg,'phy.pdsch.nLayers',NaN)));
ceiling=double(sixgr.util.structGet(cfg,'phy.pdsch.maxLayers',bootstrap));
validateattributes(bootstrap,{'numeric'},{'scalar','finite','integer','>=',1,'<=',8});
validateattributes(ceiling,{'numeric'},{'scalar','finite','integer','>=',bootstrap,'<=',8});
policy=sixgr.mimo.resolveRankPolicy(cfg);
ranks=bootstrap;
if policy.AdaptiveRank
    % CSI_Feedback.localRankSearchDomain intersects the raw search and
    % installed serialized-report restrictions. Neither one overrides the
    % other. Here only static limits are known, not measured channel rank.
    for path=["phy.csi.maxRank","phy.csi.reportConfiguration.MaxRank", ...
            "phy.csi.reportConfiguration.Ports"]
        limit=sixgr.util.structGet(cfg,path,[]);
        if isempty(limit), continue; end
        validateattributes(limit,{'numeric'},{'scalar','finite','integer','positive'});
        ceiling=min(ceiling,double(limit));
    end
    domain=1:ceiling;
    for path=["phy.csi.rankDomain","phy.csi.reportConfiguration.AllowedRanks"]
        restriction=sixgr.util.structGet(cfg,path,[]);
        if isempty(restriction), continue; end
        validateattributes(restriction,{'numeric'},{'vector','nonempty','finite','integer','>=',1,'<=',8});
        domain=intersect(domain,reshape(double(restriction),1,[]),'stable');
    end
    assert(~isempty(domain),'sixgr:phy:csi:EmptyRankDomain', ...
        'Installed CSI restrictions and the PDSCH scheduler capability have no common rank.');
    ranks=unique([bootstrap,domain]);
end
carrier=sixgr.phy.grid.makeCarrier(cfg);
for rank=ranks
    try
        % Codeword modulation is selected per grant, not by this DM-RS
        % check. Repeat the configured first modulation only in the local
        % validation call so a scalar bootstrap does not reject rank >4.
        % No runtime configuration, coding policy or grant is rewritten.
        modulation=string(sixgr.util.structGet(cfg,'phy.pdsch.modulation',""));
        if ~isempty(modulation), modulation=repmat(modulation(1),1,1+(rank>4)); end
        pdsch=sixgr.phy.grid.pdschConfigFromConfig(carrier,cfg, ...
            'NumLayers',rank,'Modulation',modulation);
        indices=nrPDSCHDMRSIndices(carrier,pdsch);
        assert(~isempty(indices),'sixgr:phy:grant:EmptyConfiguredPDSCHDMRS', ...
            'The configured PDSCH allocation contains no DM-RS.');
    catch cause
        failure=MException('sixgr:lls6g:config:PDSCHDMRSRankDomainInvalid', ...
            ['Configured PDSCH rank %d in executable domain %s is incompatible ' ...
             'with its installed allocation/DM-RS reservation: %s'], ...
            rank,mat2str(ranks),cause.message);
        throw(addCause(failure,cause));
    end
    evidence.Ranks(end+1)=rank;
    evidence.PortSets{end+1}=double(pdsch.DMRS.DMRSPortSet);
    evidence.CDMGroups{end+1}=double(pdsch.DMRS.CDMGroups);
    evidence.NumCDMGroupsWithoutData(end+1)=double(pdsch.DMRS.NumCDMGroupsWithoutData);
end
end
