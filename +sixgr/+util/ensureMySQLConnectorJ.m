function jarPath = ensureMySQLConnectorJ(opts)
%ENSUREMYSQLCONNECTORJ Ensure the MySQL Connector/J driver is available.
%
%   jarPath = sixgr.util.ensureMySQLConnectorJ()
%   jarPath = sixgr.util.ensureMySQLConnectorJ("Version","8.4.0")
%
% The driver is downloaded once into a local cache folder and added to the
% dynamic Java class path for the current MATLAB session.

arguments
    opts.Version {mustBeTextScalar} = "8.4.0"
    opts.CacheRoot {mustBeTextScalar} = localDefaultCacheRoot()
    opts.DownloadIfMissing (1,1) logical = true
end

version = string(opts.Version);
cacheRoot = char(opts.CacheRoot);
jarName = "mysql-connector-j-" + version + ".jar";
jarPath = fullfile(cacheRoot, char(jarName));

if ~isfile(jarPath)
    if ~opts.DownloadIfMissing
        error("sixgr:util:ensureMySQLConnectorJ:MissingDriver", ...
            "MySQL Connector/J not found: %s", jarPath);
    end
    sixgr.util.ensureDir(jarPath);
    url = "https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/" + ...
        version + "/" + jarName;
    try
        websave(jarPath, char(url), weboptions("Timeout", 60));
    catch ME
        error("sixgr:util:ensureMySQLConnectorJ:DownloadFailed", ...
            "Failed to download MySQL Connector/J from %s: %s", url, ME.message);
    end
end

dynamicPath = string(javaclasspath("-dynamic"));
staticPath = string(javaclasspath("-static"));
if ~any(dynamicPath == string(jarPath)) && ~any(staticPath == string(jarPath))
    javaaddpath(jarPath);
end

end

function cacheRoot = localDefaultCacheRoot()
localAppData = getenv("LOCALAPPDATA");
if ~isempty(localAppData)
    cacheRoot = fullfile(localAppData, "sixgr", "jdbc");
else
    cacheRoot = fullfile(tempdir, "sixgr", "jdbc");
end
end

function mustBeTextScalar(x)
if ~(ischar(x) || (isstring(x) && isscalar(x)))
    error("sixgr:util:ensureMySQLConnectorJ:BadType", ...
        "Input must be a char vector or string scalar.");
end
end
