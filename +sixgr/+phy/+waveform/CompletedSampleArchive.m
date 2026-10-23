classdef CompletedSampleArchive
    % Lossless sample backing for completed observation-buffer owners only.
    % No channel/RF/RNG/decoder state is recreated from these samples.
    methods (Static)
        function receipt=write(root,samples)
            root=string(sixgr.util.canonicalPath(root));
            hash=sixgr.phy.waveform.WaveformHash.runtimeArray(samples);
            relative="air_interface/mat/completed_observation_samples/"+hash+".mat";
            path=fullfile(root,relative);
            manifest=struct('Schema',"CompletedSampleArchive/v1", ...
                'SampleSHA256',hash,'SampleClass',string(class(samples)),'SampleSize',size(samples));
            if ~isfile(path)
                sixgr.util.matSave(path,struct('Samples',samples,'Manifest',manifest), ...
                    'UseArtifactStore',false,'ForceV73',true);
            end
            info=dir(path);
            receipt=struct('Root',root,'RelativePath',relative, ...
                'FileSHA256',string(sixgr.util.sha256File(path)), ...
                'Bytes',info.bytes,'Manifest',manifest);
            restored=sixgr.phy.waveform.CompletedSampleArchive.read(receipt);
            assert(isequaln(restored,samples),'WAVEFORM:ArchiveSamplesChanged', ...
                'Completed samples must independently reload exactly before memory is released.');
        end

        function samples=read(receipt)
            [m,path]=sixgr.phy.waveform.CompletedSampleArchive.validateReceipt(receipt);
            data=sixgr.util.loadVerifiedMAT(path,receipt.FileSHA256,["Manifest","Samples"]);
            assert(isequaln(data.Manifest,m) && string(class(data.Samples))==m.SampleClass && ...
                isequal(size(data.Samples),m.SampleSize) && ...
                sixgr.phy.waveform.WaveformHash.runtimeArray(data.Samples)==m.SampleSHA256, ...
                'WAVEFORM:ArchiveSamplesChanged','Archived samples or their identity changed.');
            samples=data.Samples;
        end

        function digest=verifyFile(receipt)
            % For an already validated immutable sample owner, verify the
            % entire backing file without deserializing/re-hashing its IQ.
            % File length or modification time alone is never sufficient.
            [m,path]=sixgr.phy.waveform.CompletedSampleArchive.validateReceipt(receipt);
            assert(string(sixgr.util.sha256File(path))==string(receipt.FileSHA256), ...
                'sixgr:util:VerifiedMATHashMismatch', ...
                'Completed sample archive bytes differ from their validated receipt.');
            digest=m.SampleSHA256;
        end
    end
    methods (Static,Access=private)
        function [m,path]=validateReceipt(receipt)
            m=receipt.Manifest;
            % Receipts are also persisted in CSV JSON. JSON preserves the
            % values but not MATLAB string/char or row/column-vector types.
            % Canonicalize only those representations before the exact
            % manifest/content comparison; never alter a hash or dimension.
            assert(isstruct(m) && isscalar(m) && ...
                all(isfield(m,{'Schema','SampleSHA256','SampleClass','SampleSize'})), ...
                'WAVEFORM:ArchiveIdentity','A complete sample manifest is required.');
            for name=["Schema","SampleSHA256","SampleClass"]
                value=m.(name);
                assert((ischar(value) && isrow(value)) || ...
                    (isstring(value) && isscalar(value) && ~ismissing(value)), ...
                    'WAVEFORM:ArchiveIdentity','Manifest text fields must be scalar.');
                m.(name)=string(value);
            end
            validateattributes(m.SampleSize,{'numeric'}, ...
                {'real','finite','vector','integer','nonnegative'});
            assert(numel(m.SampleSize)>=2,'WAVEFORM:ArchiveIdentity', ...
                'Retain every declared sample dimension.');
            m.SampleSize=double(m.SampleSize(:).');
            assert(string(m.Schema)=="CompletedSampleArchive/v1" && ...
                ~isempty(regexp(char(m.SampleSHA256),'^[a-f0-9]{64}$','once')) && ...
                string(receipt.RelativePath)== ...
                "air_interface/mat/completed_observation_samples/"+m.SampleSHA256+".mat", ...
                'WAVEFORM:ArchiveIdentity','Invalid completed-sample archive identity.');
            path=fullfile(receipt.Root,receipt.RelativePath);
            info=dir(path);
            assert(isscalar(info) && info.bytes==receipt.Bytes, ...
                'WAVEFORM:ArchiveMissing','Exact completed samples must remain available.');
        end
    end
end
