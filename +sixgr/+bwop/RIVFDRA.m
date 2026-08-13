classdef RIVFDRA
    %RIVFDRA Exact NR-reference bandwidth, RIV and CCE arithmetic.

    methods (Static)
        function tableOut = rivTable(referenceBandwidths)
            n = double(referenceBandwidths(:));
            if any(n < 1 | n ~= round(n))
                error("sixgr:bwop:InvalidReferenceBandwidth", ...
                    "N_S values must be positive integer RB counts.");
            end
            combinations = n.*(n+1)/2;
            bits = ceil(log2(combinations));
            tableOut = table(n,combinations,bits, ...
                repmat("ANALYTICAL_EXACT",numel(n),1), ...
                'VariableNames',{'NS_RB','RIVCombinations','FDRABits','EvidenceClass'});
        end

        function tableOut = cceTable(coresetRB,durations,aggregationLevels)
            nc = double(coresetRB(:)); durations = double(durations(:));
            al = double(aggregationLevels(:));
            rows = cell(numel(nc)*numel(durations)*numel(al),1); index = 0;
            for i=1:numel(nc)
                for j=1:numel(durations)
                    nCCE=floor(nc(i)*durations(j)/6);
                    for k=1:numel(al)
                        index=index+1;
                        feasible=al(k)<=nCCE;
                        occupancy=al(k)/max(nCCE,1);
                        rows{index}=table(nc(i),durations(j),nCCE,al(k), ...
                            feasible,occupancy,"ANALYTICAL_EXACT", ...
                            'VariableNames',{'NC_RB','DurationSymbols','NCCE', ...
                            'AggregationLevel','Feasible','CandidateOccupancy', ...
                            'EvidenceClass'});
                    end
                end
            end
            tableOut=vertcat(rows{:});
        end

        function riv = encode(nSizeBWP,startRB,lengthRB)
            N=double(nSizeBWP); S=double(startRB); L=double(lengthRB);
            sixgr.bwop.RIVFDRA.validateAllocation(N,S,L);
            if (L-1) <= floor(N/2)
                riv=N*(L-1)+S;
            else
                riv=N*(N-L+1)+(N-1-S);
            end
        end

        function [startRB,lengthRB] = decode(nSizeBWP,riv)
            N=double(nSizeBWP); R=double(riv);
            if ~(isscalar(N)&&N>=1&&N==round(N)&&isscalar(R)&&R>=0&&R==round(R))
                error("sixgr:bwop:InvalidRIV", ...
                    "RIV decode inputs must be nonnegative integers and N_S positive.");
            end
            q=floor(R/N); remValue=mod(R,N);
            if q <= floor(N/2) && q+1 <= N-remValue
                lengthRB=q+1; startRB=remValue;
            else
                lengthRB=N-q+1; startRB=N-1-remValue;
            end
            sixgr.bwop.RIVFDRA.validateAllocation(N,startRB,lengthRB);
        end
    end

    methods (Static,Access=private)
        function validateAllocation(N,S,L)
            values=[N S L];
            if any(~isfinite(values))||any(values~=round(values))||N<1||S<0||L<1||S+L>N
                error("sixgr:bwop:InvalidRIVAllocation", ...
                    "RIV allocation requires integer N_S>=1, start>=0, length>=1 and start+length<=N_S.");
            end
        end
    end
end
