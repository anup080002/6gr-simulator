classdef QualificationAtomicWriter
    %QUALIFICATIONATOMICWRITER Same-directory validated atomic writes.
    methods (Static)
        function writeTable(path,T)
            path = string(path);
            sixgr.util.ensureDir(path);
            temporary = localTemporary(path);
            cleanup = onCleanup(@()localDelete(temporary)); %#ok<NASGU>
            writetable(T,temporary,"Delimiter",",","QuoteStrings",true);
            readtable(temporary,"Delimiter",",","TextType","string", ...
                "VariableNamingRule","preserve");
            localReplace(temporary,path);
        end

        function writeText(path,text)
            path = string(path);
            sixgr.util.ensureDir(path);
            temporary = localTemporary(path);
            cleanup = onCleanup(@()localDelete(temporary)); %#ok<NASGU>
            fid = fopen(char(temporary),"w","n","UTF-8");
            if fid<0
                error("FULLSTACK:AtomicWriteOpenFailed", ...
                    "Cannot open temporary finalization artifact: %s",temporary);
            end
            fileCleanup = onCleanup(@()localClose(fid)); %#ok<NASGU>
            fwrite(fid,char(string(text)),"char");
            fclose(fid);
            info = dir(temporary);
            if isempty(info)
                error("FULLSTACK:AtomicWriteValidationFailed", ...
                    "Temporary finalization artifact was not written.");
            end
            localReplace(temporary,path);
        end

        function writeJSON(path,payload)
            try
                text = jsonencode(payload,"PrettyPrint",true);
            catch
                text = jsonencode(payload);
            end
            sixgr.integration.qualification.QualificationAtomicWriter. ...
                writeText(path,string(text)+newline);
        end
    end
end

function temporary=localTemporary(path)
[folder,name,extension]=fileparts(char(path));
temporary=string(fullfile(folder,"."+name+"."+ ...
    char(java.util.UUID.randomUUID())+".tmp"+extension));
end

function localReplace(source,target)
if isfile(target)
    delete(target);
end
[ok,message]=movefile(source,target,"f");
if ~ok
    error("FULLSTACK:AtomicRenameFailed", ...
        "Cannot atomically publish %s: %s",target,message);
end
end

function localDelete(path)
if isfile(path)
    delete(path);
end
end

function localClose(fid)
try
    fclose(fid);
catch
end
end
