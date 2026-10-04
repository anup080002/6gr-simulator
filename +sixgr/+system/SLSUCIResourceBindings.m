classdef SLSUCIResourceBindings < handle
    % Modeled installed UE/cell/BWP resources; never decoded RRC evidence.
    % Frequency bundles are an explicit simulator policy. IDs/PRI ordinals,
    % formats and calendars remain those of the configured PUCCH template.
    properties (SetAccess=private)
        Trace table = table()
    end
    properties (Access=private)
        Cfg struct
        Policy struct
        Active struct = struct([])
        NextEpoch double
        LastSlot double = -1
        RNTIByUE double = []
    end
    methods
        function obj=SLSUCIResourceBindings(cfg)
            obj.Cfg=cfg;
            p=cfg.system.linkAbstraction.dynamicPUCCH.resourceBinding;
            assert(string(p.mode)=="per_cell_frequency_pool", ...
                'sixgr:system:UCIResourceBindingPolicy','Unsupported installed resource-pool policy.');
            for name=["firstPRB","stridePRB","capacityPerCell"]
                assert(isfield(p,name),'sixgr:system:UCIResourceBindingPolicy','Missing resourceBinding.%s.',name);
                validateattributes(p.(name),{'numeric'},{'scalar','integer','finite','nonnegative'});
            end
            assert(p.stridePRB>0 && p.capacityPerCell>0, ...
                'sixgr:system:UCIResourceBindingPolicy','Resource stride and capacity must be positive.');
            resources=cfg.validation.pucch_resources.resources;
            assert(isstruct(resources) && ~isempty(resources), ...
                'sixgr:system:UCIResourceBindingPolicy','Install a PUCCH resource template first.');
            id=cfg.phy.frame.DefaultIdentity;
            carriers=cfg.phy.frame.ComponentCarriers;
            cc=carriers([carriers.CCID]==id.ScheduledCCID);
            assert(isscalar(cc),'sixgr:system:UCIResourcePoolGrid','Select one installed carrier.');
            bwp=cc.BWPs([cc.BWPs.BWPID]==id.ULBWPID & upper(string({cc.BWPs.Direction}))=="UL");
            assert(isscalar(bwp),'sixgr:system:UCIResourcePoolGrid','Select one installed UL BWP.');
            last=0;
            for r=reshape(resources,1,[])
                starts=double(r.starting_prb);
                if r.intra_slot_hopping, starts=[starts double(r.second_hop_start_prb)]; end
                assert(all(isfinite(starts) & starts>=0 & starts==fix(starts)), ...
                    'sixgr:system:UCIResourceBindingPolicy','Invalid template PRB positions.');
                last=max(last,max(starts)+double(r.nrof_prbs));
            end
            assert(last<=p.stridePRB && ...
                p.firstPRB+(p.capacityPerCell-1)*p.stridePRB+last<=bwp.NSizeBWP && ...
                bwp.NStartBWP>=cfg.phy.carrier.NStartGrid && ...
                bwp.NStartBWP+bwp.NSizeBWP<=cfg.phy.carrier.NStartGrid+cfg.phy.carrier.NSizeGrid, ...
                'sixgr:system:UCIResourcePoolGrid','PUCCH bundles overlap or exceed the configured BWP/carrier.');
            obj.Policy=p;
            obj.NextEpoch=double(cfg.validation.pucch_resources.configuration_epoch);
        end
        function configureUEIdentities(obj,rntis)
            validateattributes(rntis,{'numeric'},{'vector','integer','finite','positive','<=',65535});
            assert(isempty(obj.Active),'sixgr:system:UCIIdentityAlreadyIssued', ...
                'Install protocol identities before allocating UCI resources.');
            obj.RNTIByUE=double(rntis(:));
        end
        function update(obj,serving,slot,protectedPairs)
            % protectedPairs [UE,cell] come only from actual issued grants.
            validateattributes(slot,{'numeric'},{'scalar','integer','nonnegative','finite'});
            validateattributes(serving,{'numeric'},{'vector','integer','positive','finite'});
            assert(slot>=obj.LastSlot,'sixgr:system:UCIResourceClock','No backward installation clock.');
            assert(isnumeric(protectedPairs) && size(protectedPairs,2)==2 && ...
                all(isfinite(protectedPairs) & protectedPairs>=1 & protectedPairs==fix(protectedPairs),'all') && ...
                all(protectedPairs(:,1)<=numel(serving)), ...
                'sixgr:system:UCIResourceIdentity','Invalid protected grant ownership.');
            required=unique([(1:numel(serving)).' serving(:);protectedPairs],'rows','stable');
            pending=obj.Active; changes=table(); next=obj.NextEpoch;
            % Release only when association AND outstanding grant ownership
            % have ended. All modifications commit together after admission.
            for k=numel(pending):-1:1
                b=pending(k);
                if ~ismember([b.UEIndex b.CellID],required,'rows')
                    changes=[changes;event(b,slot,"released")]; %#ok<AGROW>
                    pending(k)=[];
                end
            end
            for k=1:size(required,1)
                u=required(k,1); c=required(k,2);
                if ~isempty(pending) && any([pending.UEIndex]==u & [pending.CellID]==c), continue; end
                used=[];
                if ~isempty(pending), used=[pending([pending.CellID]==c).PoolIndex0]; end
                free=setdiff(0:obj.Policy.capacityPerCell-1,used,'stable');
                assert(~isempty(free),'sixgr:system:UCIResourcePoolExhausted', ...
                    'Cell %d cannot admit UE %d without overlapping installed PUCCH resources.',c,u);
                id=obj.Cfg.phy.frame.DefaultIdentity;
                rnti=u;
                if ~isempty(obj.RNTIByUE)
                    assert(u<=numel(obj.RNTIByUE),'sixgr:system:UCIIdentityMissing','Missing protocol identity.');
                    rnti=obj.RNTIByUE(u);
                end
                b=struct('UEIndex',u,'RNTI',rnti,'CellID',c,'ComponentCarrier',id.ScheduledCCID, ...
                    'ULBWP',id.ULBWPID,'PoolIndex0',free(1), ...
                    'PRBOffset',obj.Policy.firstPRB+free(1)*obj.Policy.stridePRB, ...
                    'ConfigurationEpoch',next,'InstalledAbsoluteSlot0',slot,'RRCContextDigest',"");
                next=next+1;
                ue=identity(b);
                projected=project(obj.Cfg,b);
                rrc=sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(projected,ue);
                b.RRCContextDigest=rrc.Digest;
                pending=[pending b]; %#ok<AGROW>
                changes=[changes;event(b,slot,"installed")]; %#ok<AGROW>
            end
            obj.Active=pending; obj.NextEpoch=next; obj.LastSlot=slot;
            obj.Trace=[obj.Trace;changes];
        end
        function cfg=configForUE(obj,ue)
            assert(~isempty(obj.Active),'sixgr:system:MissingUCIResourceBinding','Install association before querying UCI resources.');
            matches=find([obj.Active.UEIndex]==ue.UEID & [obj.Active.CellID]==ue.PUCCHCell & ...
                [obj.Active.ComponentCarrier]==ue.ComponentCarrier & [obj.Active.ULBWP]==ue.ActiveULBWP);
            validateattributes(ue.RNTI,{'numeric'},{'scalar','integer','finite','positive','<=',65535});
            assert(isscalar(matches) && ue.ServingCell==ue.PUCCHCell && obj.Active(matches).RNTI==ue.RNTI, ...
                'sixgr:system:MissingUCIResourceBinding','No exact installed UE/cell/carrier/BWP UCI binding.');
            cfg=project(obj.Cfg,obj.Active(matches));
        end
    end
end

function ue=identity(b)
ue=struct('UEID',b.UEIndex,'RNTI',b.RNTI,'ServingCell',b.CellID, ...
    'PUCCHCell',b.CellID,'ComponentCarrier',b.ComponentCarrier,'ActiveULBWP',b.ULBWP);
end

function cfg=project(cfg,b)
s=cfg.validation.pucch_resources;
for k=1:numel(s.resources)
    s.resources(k).starting_prb=s.resources(k).starting_prb+b.PRBOffset;
    if s.resources(k).intra_slot_hopping
        s.resources(k).second_hop_start_prb=s.resources(k).second_hop_start_prb+b.PRBOffset;
    end
end
s.configuration_epoch=b.ConfigurationEpoch;
s.installed_absolute_slot0=b.InstalledAbsoluteSlot0;
cfg.validation.pucch_resources=s;
end

function row=event(b,slot,action)
row=struct2table(b,'AsArray',true);
row.EventAbsoluteSlot0=slot; row.Action=action;
row.Source="modeled_installed_UCI_resources_not_decoded_RRC";
row.WaveformBacked=false;
end
