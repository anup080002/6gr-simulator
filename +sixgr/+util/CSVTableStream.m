classdef CSVTableStream < handle
    % Bounded serialization of one complete, atomically published CSV.
    % Chunking changes neither sample population nor numeric precision.
    properties (SetAccess=private)
        RowsWritten = 0
        MaxSerializedRows = 0
        ChunkRows = 8192
    end
    properties (Access=private)
        Target
        Temporary
        RoundTrip
        Names = {}
        Classes = {}
        Sizes = {}
        Started = false
        Published = false
    end
    methods
        function obj=CSVTableStream(path,roundTrip)
            assert(ischar(path)||(isstring(path)&&isscalar(path)), ...
                'sixgr:util:csvWriteTable:BadType','CSV path must be scalar text.');
            assert(islogical(roundTrip)&&isscalar(roundTrip), ...
                'sixgr:util:CSVTableStream:BadPrecision','Round-trip policy must be logical.');
            obj.Target=char(path); obj.RoundTrip=roundTrip;
            sixgr.util.ensureDir(obj.Target);
            folder=fileparts(obj.Target);
            if isempty(folder), folder=pwd; end
            obj.Temporary=[tempname(folder),'.csv'];
        end
        function append(obj,T)
            assert(~obj.Published && istable(T), ...
                'sixgr:util:CSVTableStream:BadAppend','Append a table before publication.');
            names=T.Properties.VariableNames;
            classes=cellfun(@(n)class(T.(n)),names,'UniformOutput',false);
            sizes=cellfun(@(n)localColumnSize(T.(n)),names,'UniformOutput',false);
            if obj.Started
                assert(isequal(names,obj.Names)&&isequal(classes,obj.Classes)&&isequal(sizes,obj.Sizes), ...
                    'sixgr:util:CSVTableStream:SchemaChanged', ...
                    'Chunk boundaries must not change CSV column names, types or shapes.');
            else
                obj.Names=names; obj.Classes=classes; obj.Sizes=sizes;
            end
            % Include a typed zero-row table once to preserve its header.
            for first=1:obj.ChunkRows:max(1,height(T))
                last=min(height(T),first+obj.ChunkRows-1);
                wire=T(first:last,:);
                if obj.RoundTrip
                    for name=string(names)
                        values=wire.(name);
                        if isfloat(values)
                            assert(isreal(values),'sixgr:util:csvWriteTable:ComplexRoundTrip', ...
                                'RoundTripNumericText requires real floating-point columns.');
                            wire.(name)=compose('%.17g',double(values));
                        end
                    end
                end
                if obj.Started
                    writetable(wire,obj.Temporary,'Delimiter',',','QuoteStrings',true, ...
                        'WriteMode','append','WriteVariableNames',false);
                else
                    writetable(wire,obj.Temporary,'Delimiter',',','QuoteStrings',true);
                    obj.Started=true;
                end
                obj.RowsWritten=obj.RowsWritten+height(wire);
                obj.MaxSerializedRows=max(obj.MaxSerializedRows,height(wire));
            end
        end
        function finish(obj,mirrorPaths)
            assert(obj.Started && ~obj.Published, ...
                'sixgr:util:CSVTableStream:Incomplete','Publish a complete table exactly once.');
            if nargin<2, mirrorPaths=strings(0,1); end
            assert(isstring(mirrorPaths)||ischar(mirrorPaths)||iscellstr(mirrorPaths), ...
                'sixgr:util:CSVTableStream:BadMirrorPaths','Mirror destinations must be text paths.');
            mirrorPaths=reshape(string(mirrorPaths),[],1);
            paths=[string(obj.Target);mirrorPaths];
            canonical=strings(size(paths));
            for k=1:numel(paths)
                canonical(k)=sixgr.util.canonicalPath(paths(k));
                assert(~ismissing(paths(k)) && strlength(strtrim(paths(k)))>0 && ~isfolder(paths(k)), ...
                    'sixgr:util:CSVTableStream:BadMirrorPaths','Each CSV destination must name a file.');
            end
            if ispc, canonical=lower(canonical); end
            assert(numel(unique(canonical))==numel(canonical), ...
                'sixgr:util:CSVTableStream:DuplicateDestination','CSV destinations must be distinct.');
            localPublishWithRetry(obj.Temporary,obj.Target);
            obj.Published=true;
            sourceHash="";
            if ~isempty(mirrorPaths), sourceHash=string(sixgr.util.sha256File(obj.Target)); end
            for destination=reshape(paths,1,[])
                if destination~=string(obj.Target)
                    sixgr.util.copyFileVerified(string(obj.Target),destination,sourceHash);
                end
                obj.registerArtifact(destination);
            end
        end
        function delete(obj)
            % Never delete or truncate the previous canonical artifact on
            % a validation/write failure partway through the next version.
            if ~isempty(obj.Temporary) && isfile(obj.Temporary)
                delete(obj.Temporary);
            end
        end
    end
    methods (Access=private)
        function registerArtifact(obj,destination)
            if sixgr.db.isArtifactStoreActive()
                try
                    metadata=struct('row_count',obj.RowsWritten, ...
                        'column_names',{obj.Names},'variable_count',numel(obj.Names), ...
                        'source_path',char(destination));
                    % Mirror the SAME CSV bytes with bounded file reads. Do
                    % not reconstruct a giant typed table or uint8 vector.
                    handled=sixgr.db.artifactStore('store_file',char(destination),char(destination), ...
                        'table_csv','text/csv; charset=UTF-8',metadata);
                    assert(handled,'sixgr:util:CSVTableStream:MirrorNotStored', ...
                        'Active artifact store did not persist the CSV.');
                catch cause
                    warning('sixgr:util:csvWriteTable:ArtifactStoreMirrorFailed', ...
                        'Local CSV ''%s'' was written, but DB artifact mirroring failed: %s', ...
                        destination,cause.message);
                end
            end
        end
    end
end

function shape=localColumnSize(value)
shape=size(value); shape=shape(2:end);
end

function localPublishWithRetry(source,target)
maxAttempts=12; message=""; identifier="";
for attempt=1:maxAttempts
    [ok,message,identifier]=movefile(source,target,'f');
    if ok, return; end
    if attempt<maxAttempts, pause(min(.05*2^(attempt-1),1)); end
end
error('sixgr:util:csvWriteTable:AtomicPublishFailed', ...
    'Unable to atomically publish CSV ''%s'' after %d attempts (%s): %s', ...
    target,maxAttempts,identifier,message);
end
