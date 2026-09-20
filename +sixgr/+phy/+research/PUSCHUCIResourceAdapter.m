classdef PUSCHUCIResourceAdapter
    % Explicit-Qm UL-SCH/UCI map, including experimental Qm=10.
    % With a positive UL-SCH TB, UCI symbol budgets depend on its coding
    % segmentation, beta and available REs, not Qm (38.212 6.3.2.4.1).
    % Lift the public QPSK mapping at whole-symbol boundaries. No waveform,
    % received metric or payload content is approximated by this operation.
    % Qm=10 is an explicitly experimental extension, not native NR PUSCH.
    properties (SetAccess=private)
        ScenarioPolicy
        Geometry
        Modulation
        NumLayers
        NumCodewords = 1
        Qm
    end
    methods
        function obj=PUSCHUCIResourceAdapter(s,geometry,modulation)
            assert(isa(geometry,'nrPUSCHConfig') && isscalar(geometry) && geometry.NumCodewords==1, ...
                'sixgr:research:UnsupportedUCIGeometry','Retain one native geometry-only codeword.');
            obj.ScenarioPolicy=s; obj.Geometry=geometry;
            obj.Modulation=string(modulation); obj.NumLayers=geometry.NumLayers;
            catalog=sixgr.lls6g.config.loadParameterCatalog('scenario');
            rows=catalog.value_maps.modulation_order_to_name;
            obj.Qm=double([rows(string({rows.name})==obj.Modulation).order]);
            assert(isscalar(obj.Qm) && any(obj.Qm==[2 4 6 8 10]), ...
                'sixgr:research:UnsupportedUCIModulation','An explicit square-QAM transport is required.');
        end
        function plan=resourcePlan(obj,tcr,tbs,lengths)
            plan=sixgr.phy.research.PUSCHUCIResourceAdapter.resolve( ...
                obj.ScenarioPolicy,obj.Geometry,tcr,tbs,lengths,obj.Modulation);
        end
        function [account,info]=resourceAccounting(obj,carrier,indices,tcr,overhead)
            [expected,info]=nrPUSCHIndices(carrier,obj.Geometry);
            assert(isequal(indices,expected),'sixgr:research:TransportGeometryMismatch', ...
                'Executed indices must match the independently installed transport geometry.');
            info.G=double(info.Gd)*obj.NumLayers*obj.Qm;
            view=struct('Modulation',obj.Modulation,'NumLayers',obj.NumLayers, ...
                'NumCodewords',1,'PRBSet',obj.Geometry.PRBSet, ...
                'SymbolAllocation',obj.Geometry.SymbolAllocation,'TransformPrecoding',false, ...
                'EnablePTRS',false);
            account=sixgr.phy.resource.computeResourceAccounting('PUSCH',carrier,view, ...
                'ChannelIndices',indices,'AllocationInfo',info, ...
                'DMRSIndices',nrPUSCHDMRSIndices(carrier,obj.Geometry), ...
                'TargetCodeRate',tcr,'XOverhead',overhead);
            account.Source="native_PUSCH_RE_geometry_with_explicit_experimental_Qm";
            account.StandardNR=false;
        end
        function [llr,symbols]=demodulate(obj,layers,noise,carrier,rate,tbs,context,report)
            assert(isa(context,'sixgr.phy.ul.pusch.PUSCHUCIReceiveContext'), ...
                'sixgr:pusch:MissingUCIReceiveContext', ...
                'Research waveform reception requires an independently installed UCI context, even if empty.');
            budget=context.bitBudget(report);
            % CSI may be absent. Before RI is decoded only placeholder maps
            % common to all configured possibilities may affect descrambling.
            lengths=[budget.OACK 0 budget.OCGUCI];
            if ~isempty(report)
                counts=report.part2BitCountCandidates();
                lengths=[lengths;repmat([budget.OACK budget.OCSI1],numel(counts),1), ...
                    counts(:)+budget.OCGUCI];
            end
            for k=1:size(lengths,1)
                plan=obj.resourcePlan(rate,tbs,lengths(k,:));
                [xk,yk]=obj.placeholderIndices(plan);
                if k==1, x=xk; y=yk;
                else
                    assert(isequal(x,xk) && isequal(y,yk), ...
                        'sixgr:research:UnresolvedPlaceholderMapping', ...
                        'Cannot use TX CSI size to select a received placeholder map.');
                end
            end
            symbols=sixgr.phy.ul.pusch.PUSCHLayerMapper.demap(layers,obj.NumLayers);
            raw=nrSymbolDemodulate(symbols,char(obj.Modulation),noise);
            nid=obj.Geometry.NID; if isempty(nid), nid=carrier.NCellID; end
            llr=nrPUSCHDescramble(raw,nid,obj.Geometry.RNTI,x,y);
            % Fixed x tags carry no observed information. Erase them instead
            % of promoting known filler to infinite measured confidence.
            llr(x)=0;
        end
    end
    methods (Static)
        function plan=resolve(s,pusch,tcr,tbs,lengths,modulation)
            assert(string(sixgr.util.structGet(s,'meta.research_class',''))== ...
                "optional_research_experiment" && ...
                string(sixgr.util.structGet(s,'research_pusch_uci.resource_mapping',''))== ...
                "symbol_preserving_single_codeword_ulsch", ...
                'sixgr:research:ExplicitUCIAdapterRequired','Install the explicit research UCI mapping policy.');
            assert(isa(pusch,'nrPUSCHConfig') && isscalar(pusch) && ...
                pusch.NumCodewords==1 && ~pusch.TransformPrecoding && ...
                ~pusch.EnablePTRS && ~pusch.Interlacing && ...
                strcmpi(pusch.FrequencyHopping,'neither'), ...
                'sixgr:research:UnsupportedUCIGeometry', ...
                'This adapter requires one-codeword CP-OFDM, no PTRS/interlacing/hopping.');
            validateattributes(tbs,{'numeric'},{'scalar','real','finite','integer','positive'});
            validateattributes(tcr,{'numeric'},{'scalar','real','finite','>',0,'<',1});
            validateattributes(lengths,{'numeric'},{'vector','numel',3,'real','finite','integer','nonnegative'});
            catalog=sixgr.lls6g.config.loadParameterCatalog('scenario');
            rows=catalog.value_maps.modulation_order_to_name;
            names=string({rows.name}); orders=double([rows.order]);
            qm=orders(names==string(modulation));
            assert(isscalar(qm) && any(qm==[2 4 6 8 10]), ...
                'sixgr:research:UnsupportedUCIModulation','Select a square QAM modulation with Qm=2,4,6,8,10.');
            base=pusch; base.Modulation='QPSK';
            info=nrULSCHInfo(base,tcr,tbs,lengths(1),lengths(2),lengths(3));
            capacity=nrULSCHInfo(base,tcr,tbs,0,0,0);
            g=double(capacity.GULSCH);
            % Labelled input LLRs expose native bit positions, not bits or
            % TX knowledge. The receiver independently reconstructs this
            % same map from its installed scheduling/receive context.
            [u,a,c1,c2]=nrULSCHDemultiplex(base,tcr,tbs, ...
                lengths(1),lengths(2),lengths(3),(1:g).');
            source={u,a,c1,c2}; maps=cell(1,4);
            for k=1:4, maps{k}=localLift(source{k},qm); end
            budgets=double([info.GULSCH info.GACK info.GCSI1 info.GCSI2])*qm/2;
            assert(isequal(cellfun(@numel,maps),budgets), ...
                'sixgr:research:UCIBudgetMismatch','Lifted stream sizes must equal Qm-owned coded budgets.');
            allIndices=vertcat(maps{:}); positive=allIndices(allIndices>0);
            assert(isequal(sort(positive),(1:g*qm/2).'), ...
                'sixgr:research:UCIMappingPartition','UL-SCH/UCI must cover each transmitted bit exactly once.');
            plan=struct('Modulation',string(modulation),'Qm',qm,'NumLayers',pusch.NumLayers, ...
                'TransportBlockSize',double(tbs),'TargetCodeRate',double(tcr), ...
                'PayloadLengths',double(lengths(:).'),'G',g*qm/2, ...
                'GULSCH',budgets(1),'GACK',budgets(2),'GCSI1',budgets(3),'GCSI2',budgets(4), ...
                'StreamIndices',{maps},'ResearchClass',"optional_research_experiment", ...
                'StandardNR',false,'Source',"explicit_Qm_symbol_preserving_ULSCH_UCI_resource_map");
        end

        function bits=multiplex(plan,ulsch,ack,csi1,csi2)
            streams={ulsch,ack,csi1,csi2}; bits=zeros(plan.G,1,'int8');
            for k=1:4
                v=streams{k}(:); index=plan.StreamIndices{k};
                assert(numel(v)==numel(index) && all(isfinite(v)) && ...
                    all(ismember(v,[-2 -1 0 1])) && (k~=1 || all(ismember(v,[0 1]))), ...
                    'sixgr:research:InvalidUCIStream','Supply exact coded stream sizes and legal bits/placeholders.');
                selected=index>0; bits(index(selected))=int8(v(selected));
            end
        end

        function [ulsch,ack,csi1,csi2]=demultiplex(plan,llr)
            % Descrambling may supply infinite known-x filler LLRs. Keep
            % them for the UCI codec, whose confidence ignores fixed filler.
            validateattributes(llr,{'numeric'},{'vector','real','nonnan','numel',plan.G});
            streams=cell(1,4);
            for k=1:4
                index=plan.StreamIndices{k}; selected=index>0;
                streams{k}=zeros(size(index),'like',llr);
                streams{k}(selected)=llr(index(selected));
            end
            [ulsch,ack,csi1,csi2]=deal(streams{:});
        end

        function [x,y]=placeholderIndices(plan)
            % Reconstruct from receive lengths, never from transmitted bits.
            x=zeros(0,1); y=zeros(0,1);
            for k=1:3
                n=plan.PayloadLengths(k);
                if n==0, continue; end
                map=plan.StreamIndices{k+1};
                tags=sixgr.phy.research.encodePUSCHUCI(zeros(n,1,'int8'),numel(map),plan.Modulation);
                x=[x;map(tags==-1 & map>0)]; %#ok<AGROW>
                y=[y;map(tags==-2 & map>0)]; %#ok<AGROW>
            end
            x=sort(x); y=sort(y);
        end
    end
end

function index=localLift(base,qm)
base=double(base(:));
assert(mod(numel(base),2)==0,'sixgr:research:NonSymbolUCIMap','QPSK map must contain complete symbols.');
pairs=reshape(base,2,[]); used=pairs(1,:)>0;
assert(all(all(pairs(:,~used)==0)) && ...
    all(mod(pairs(1,used),2)==1 & pairs(2,used)==pairs(1,used)+1), ...
    'sixgr:research:NonSymbolUCIMap','Do not expand partial/punctured individual bits as whole symbols.');
out=zeros(qm,size(pairs,2));
out(:,used)=(1:qm).'+qm*((pairs(1,used)-1)/2);
index=out(:);
end
