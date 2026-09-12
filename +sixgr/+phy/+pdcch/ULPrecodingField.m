classdef ULPrecodingField
    % Configuration-owned TS 38.212 7.3.1.1.2 tables -4 and -5.
    % Bounded to ordinary two-port codebook transmission, not fullpowerMode1,
    % multi-panel, non-codebook or 4/8-port signaling.
    methods (Static)
        function out=resolve(data)
            p=data.ULPrecoding;
            required={'num_ports','max_rank','codebook_subset','transmission_scheme','full_power_mode'};
            assert(isstruct(p) && isscalar(p) && all(isfield(p,required)), ...
                'sixgr:phy:pdcch:MissingULPrecodingContext','UL precoding requires explicit higher-layer configuration.');
            assert(isequal(double(p.num_ports),2) && any(double(p.max_rank)==[1 2]) && ...
                string(p.transmission_scheme)=="codebook" && string(p.full_power_mode)=="not_configured", ...
                'sixgr:phy:pdcch:UnsupportedULPrecodingContext','This mapping supports ordinary two-port codebook operation only.');
            subset=string(p.codebook_subset);
            assert(any(subset==["fullyAndPartialAndNonCoherent","nonCoherent"]), ...
                'sixgr:phy:pdcch:UnsupportedULPrecodingContext','Unsupported two-port codebook subset.');
            singleRank=logical(data.TransformPrecodingEnabled) || double(p.max_rank)==1;
            if singleRank
                pairs=[ones(6,1) (0:5).']; width=3; clause="7.3.1.1.2-5";
                if subset=="nonCoherent", pairs=pairs(1:2,:); width=1; end
            else
                pairs=[1 0;1 1;2 0;1 2;1 3;1 4;1 5;2 1;2 2];
                width=4; clause="7.3.1.1.2-4";
                if subset=="nonCoherent", pairs=pairs(1:3,:); width=2; end
            end
            out=struct('Width',width,'RankTPMI',pairs,'MaxValue',size(pairs,1)-1, ...
                'StandardClause',"3GPP TS 38.212 V18.8.0 Table "+clause);
        end

        function value=encode(data,rank,tpmi)
            out=sixgr.phy.pdcch.ULPrecodingField.resolve(data);
            index=find(out.RankTPMI(:,1)==rank & out.RankTPMI(:,2)==tpmi);
            assert(isscalar(index),'sixgr:phy:pdcch:InvalidULPrecodingSelection', ...
                'Scheduled rank/TPMI is not in the configured 38.212 table.');
            value=index-1;
        end

        function [rank,tpmi]=decode(data,value)
            out=sixgr.phy.pdcch.ULPrecodingField.resolve(data);
            assert(isscalar(value) && isfinite(value) && value==fix(value) && ...
                value>=0 && value<=out.MaxValue, ...
                'sixgr:phy:pdcch:ReservedULPrecodingCodepoint','Reserved UL precoding codepoint.');
            rank=out.RankTPMI(value+1,1); tpmi=out.RankTPMI(value+1,2);
        end
    end
end
