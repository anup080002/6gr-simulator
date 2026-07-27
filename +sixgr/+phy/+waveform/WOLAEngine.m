classdef WOLAEngine
    %WOLAENGINE Stateful square-root complementary overlap-add study engine.
    methods (Static)
        function [output,state,metadata]=process(blocks,profile,state)
            if nargin<3||isempty(state)
                state=sixgr.phy.waveform.WindowOverlapState( ...
                    profile.OverlapSamples,size(blocks,3));
            end
            n=size(blocks,1); symbols=size(blocks,2); ports=size(blocks,3);
            overlap=profile.OverlapSamples;
            if overlap==0
                output=reshape(permute(blocks,[1 2 3]),n*symbols,ports);
                metadata=struct("OverlapSamples",0,"GroupDelaySamples",0, ...
                    "CoefficientSHA256",profile.CoefficientSHA256);
                return;
            end
            pieces=cell(symbols,1); previous=state.take();
            for s=1:symbols
                block=reshape(blocks(:,s,:),n,ports);
                head=block(1:overlap,:).*profile.Rise+previous;
                core=block(overlap+1:n-overlap,:);
                pieces{s}=[head;core];
                previous=block(n-overlap+1:n,:).*profile.Fall;
            end
            state.set(previous);
            output=vertcat(pieces{:});
            metadata=struct("OverlapSamples",overlap, ...
                "GroupDelaySamples",profile.GroupDelaySamples, ...
                "CoefficientSHA256",profile.CoefficientSHA256);
        end
        function output=flush(state)
            output=state.take();
            state.set(complex(zeros(size(output))));
        end
    end
end
