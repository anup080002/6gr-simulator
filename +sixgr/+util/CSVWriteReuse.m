classdef CSVWriteReuse
    % Scoped, exact live-table reuse. No retained table copies, timestamp
    % shortcuts, sampled hashes, omitted rows or changed CSV schemas.
    methods (Static)
        function cleanup=scope(root)
            state=localState();
            previous=state.ActiveRoot;
            state.ActiveRoot=string(sixgr.util.canonicalPath(root));
            localState(state);
            cleanup=onCleanup(@()localRestore(previous));
        end

        function [skip,ticket]=check(path,T,roundTrip,mirrors)
            skip=false; ticket=struct();
            state=localState();
            if strlength(state.ActiveRoot)==0 || sixgr.db.isArtifactStoreActive(), return; end
            canonical=string(sixgr.util.canonicalPath(path));
            if ~startsWith(lower(canonical),lower(state.ActiveRoot+filesep)), return; end
            % Arbitrary custom-object serialization can have side effects.
            % Unknown column classes retain the ordinary writer.
            for name=string(T.Properties.VariableNames)
                value=T.(name);
                if ~(isnumeric(value)||islogical(value)||isstring(value)||ischar(value)|| ...
                        iscellstr(value)||iscategorical(value)||isdatetime(value)||isduration(value))
                    return;
                end
            end
            if ~isempty(T.Properties.UserData), return; end
            scope=sixgr.runtime.ExecutionStageProfiler.scope("publication","live_table_fingerprint"); %#ok<NASGU>
            digest=java.security.MessageDigest.getInstance('SHA-256');
            digest.update(getByteStreamFromArray({T([],:),height(T),roundTrip}));
            for first=1:1024:height(T)
                digest.update(getByteStreamFromArray(T(first:min(first+1023,height(T)),:)));
            end
            hash=lower(string(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[])));
            paths=[canonical;reshape(string(mirrors),[],1)];
            for k=2:numel(paths), paths(k)=sixgr.util.canonicalPath(paths(k)); end
            key=char(canonical); if ispc, key=lower(key); end
            ticket=struct('Key',key,'TableHash',hash,'Paths',paths);
            if ~isKey(state.Entries,key), return; end
            old=state.Entries(key);
            if old.TableHash~=hash || ~isequal(old.Paths,paths), return; end
            for k=1:numel(paths)
                if ~isfile(paths(k)) || string(sixgr.util.sha256File(paths(k)))~=old.FileHashes(k)
                    return;
                end
            end
            state.Hits=state.Hits+1; localState(state); skip=true;
        end

        function commit(ticket)
            if isempty(fieldnames(ticket)), return; end
            hashes=strings(size(ticket.Paths));
            for k=1:numel(hashes), hashes(k)=sixgr.util.sha256File(ticket.Paths(k)); end
            state=localState();
            if state.Entries.Count>=4096 && ~isKey(state.Entries,ticket.Key)
                % Eviction changes performance only. Never retain tables.
                state.Entries=containers.Map('KeyType','char','ValueType','any');
            end
            ticket.FileHashes=hashes;
            state.Entries(ticket.Key)=ticket;
            state.Writes=state.Writes+1; localState(state);
        end

        function stats=statistics()
            state=localState();
            stats=struct('ReusedWrites',state.Hits,'PublishedWrites',state.Writes, ...
                'CachedPaths',state.Entries.Count);
        end
    end
end

function state=localState(varargin)
persistent saved
if isempty(saved)
    saved=struct('ActiveRoot',"",'Entries',containers.Map('KeyType','char','ValueType','any'), ...
        'Hits',0,'Writes',0);
end
if nargin, saved=varargin{1}; end
state=saved;
end

function localRestore(root)
state=localState(); state.ActiveRoot=root; localState(state);
end
