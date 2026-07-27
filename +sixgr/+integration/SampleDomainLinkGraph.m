classdef SampleDomainLinkGraph
    %SAMPLEDOMAINLINKGRAPH Sum immutable link waveforms before receiver noise.
    methods (Static)
        function [composite,ledger] = compose(contributions)
            if ~iscell(contributions) || isempty(contributions)
                error("sixgr:integration:WaveformInterferenceRequired", ...
                    "At least one sample-domain link contribution is required.");
            end
            lengths = cellfun(@(x)size(x.Samples,1),contributions);
            columns = cellfun(@(x)size(x.Samples,2),contributions);
            if numel(unique(lengths)) ~= 1 || numel(unique(columns)) ~= 1
                error("sixgr:integration:WaveformInterferenceRequired", ...
                    "All link contributions must share a sample-domain shape.");
            end
            composite = complex(zeros(lengths(1),columns(1)));
            rows = repmat(struct("LinkID","","ContributionPower",NaN, ...
                "ContributionSHA256","","CompositePower",NaN, ...
                "SumError",NaN,"Status",""),numel(contributions),1);
            for ii = 1:numel(contributions)
                samples = complex(double(contributions{ii}.Samples));
                composite = composite + samples;
                rows(ii).LinkID = string(contributions{ii}.LinkID);
                rows(ii).ContributionPower = mean(abs(samples(:)).^2);
                rows(ii).ContributionSHA256 = ...
                    sixgr.integration.IntegrationHash.data( ...
                    struct("Real",real(samples(:)).',"Imag",imag(samples(:)).'));
                rows(ii).Status = "PASS";
            end
            reconstructed = complex(zeros(size(composite)));
            for ii = 1:numel(contributions)
                reconstructed = reconstructed + contributions{ii}.Samples;
            end
            errorValue = max(abs(composite(:)-reconstructed(:)));
            compositePower = mean(abs(composite(:)).^2);
            for ii = 1:numel(rows)
                rows(ii).CompositePower = compositePower;
                rows(ii).SumError = errorValue;
            end
            if errorValue > 1e-12
                error("sixgr:integration:WaveformInterferenceRequired", ...
                    "Sample-domain contribution sum did not reconcile.");
            end
            ledger = struct2table(rows,"AsArray",true);
        end
    end
end
