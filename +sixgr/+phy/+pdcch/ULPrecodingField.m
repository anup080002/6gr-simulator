classdef ULPrecodingField
    % Configuration-owned TS 38.212 7.3.1.1.2 tables -2/-3/-4/-5.
    % Ordinary two/four-port codebooks; not fullpowerMode1, multi-panel,
    % non-codebook or eight-port signaling.
    methods (Static)
        function out=resolve(data)
            p=data.ULPrecoding;
            required={'num_ports','max_rank','codebook_subset','transmission_scheme','full_power_mode'};
            assert(isstruct(p) && isscalar(p) && all(isfield(p,required)), ...
                'sixgr:phy:pdcch:MissingULPrecodingContext','UL precoding requires explicit higher-layer configuration.');
            assert(isscalar(p.num_ports) && any(double(p.num_ports)==[2 4]) && ...
                isscalar(p.max_rank) && any(double(p.max_rank)==1:double(p.num_ports)) && ...
                string(p.transmission_scheme)=="codebook" && string(p.full_power_mode)=="not_configured", ...
                'sixgr:phy:pdcch:UnsupportedULPrecodingContext','This mapping supports ordinary two/four-port codebook operation only.');
            subset=string(p.codebook_subset);
            assert(any(subset==["fullyAndPartialAndNonCoherent","nonCoherent"]) || ...
                (p.num_ports==4 && subset=="partialAndNonCoherent"), ...
                'sixgr:phy:pdcch:UnsupportedULPrecodingContext','Unsupported codebook subset.');
            singleRank=logical(data.TransformPrecodingEnabled) || double(p.max_rank)==1;
            if p.num_ports==4
                if singleRank
                    pairs=[ones(28,1) (0:27).']; width=5; clause="7.3.1.1.2-3";
                    if subset=="partialAndNonCoherent", pairs=pairs(1:12,:); width=4; end
                    if subset=="nonCoherent", pairs=pairs(1:4,:); width=2; end
                else
                    % Do not compact/reindex when maxRank is 2 or 3. The
                    % table's higher-rank codepoints remain unselectable.
                    pairs=[ones(4,1) (0:3).';2*ones(6,1) (0:5).';3 0;4 0; ...
                        ones(8,1) (4:11).';2*ones(8,1) (6:13).';3 1;3 2;4 1;4 2; ...
                        ones(16,1) (12:27).';2*ones(8,1) (14:21).'; ...
                        3*ones(4,1) (3:6).';4 3;4 4];
                    width=6; clause="7.3.1.1.2-2";
                    if subset=="partialAndNonCoherent", pairs=pairs(1:32,:); width=5; end
                    if subset=="nonCoherent", pairs=pairs(1:12,:); width=4; end
                end
            elseif singleRank
                pairs=[ones(6,1) (0:5).']; width=3; clause="7.3.1.1.2-5";
                if subset=="nonCoherent", pairs=pairs(1:2,:); width=1; end
            else
                pairs=[1 0;1 1;2 0;1 2;1 3;1 4;1 5;2 1;2 2];
                width=4; clause="7.3.1.1.2-4";
                if subset=="nonCoherent", pairs=pairs(1:3,:); width=2; end
            end
            maxRank=double(p.max_rank); if singleRank, maxRank=1; end
            out=struct('Width',width,'RankTPMI',pairs,'MaxValue',size(pairs,1)-1,'MaxRank',maxRank, ...
                'StandardClause',"3GPP TS 38.212 V18.8.0 Table "+clause);
        end

        function value=encode(data,rank,tpmi)
            out=sixgr.phy.pdcch.ULPrecodingField.resolve(data);
            index=find(out.RankTPMI(:,1)==rank & out.RankTPMI(:,2)==tpmi);
            assert(isscalar(index) && rank<=out.MaxRank,'sixgr:phy:pdcch:InvalidULPrecodingSelection', ...
                'Scheduled rank/TPMI is not in the configured 38.212 table.');
            value=index-1;
        end

        function [rank,tpmi]=decode(data,value)
            out=sixgr.phy.pdcch.ULPrecodingField.resolve(data);
            assert(isscalar(value) && isfinite(value) && value==fix(value) && ...
                value>=0 && value<=out.MaxValue, ...
                'sixgr:phy:pdcch:ReservedULPrecodingCodepoint','Reserved UL precoding codepoint.');
            rank=out.RankTPMI(value+1,1); tpmi=out.RankTPMI(value+1,2);
            assert(rank<=out.MaxRank,'sixgr:phy:pdcch:InvalidULPrecodingSelection', ...
                'Received rank exceeds the installed maximum; codepoints must not be renumbered.');
        end
    end
end
