function conn = connectMySQLJDBC(opts)
%CONNECTMYSQLJDBC Open a JDBC connection to MySQL without Database Toolbox.
%
%   conn = sixgr.util.connectMySQLJDBC()
%   conn = sixgr.util.connectMySQLJDBC("Username","root","Password","secret")
%
% Defaults are sourced from environment variables when available:
%   MYSQL_HOST, MYSQL_PORT, MYSQL_DATABASE, MYSQL_USER, MYSQL_PASSWORD

arguments
    opts.Host {mustBeTextScalar} = localEnvOrDefault("MYSQL_HOST", "localhost")
    opts.Port (1,1) double = str2double(localEnvOrDefault("MYSQL_PORT", "3306"))
    opts.Database {mustBeTextScalar} = localEnvOrDefault("MYSQL_DATABASE", "")
    opts.Username {mustBeTextScalar} = localEnvOrDefault("MYSQL_USER", "")
    opts.Password {mustBeTextScalar} = localEnvOrDefault("MYSQL_PASSWORD", "")
    opts.DriverVersion {mustBeTextScalar} = "8.4.0"
    opts.UseSSL (1,1) logical = true
    opts.AllowPublicKeyRetrieval (1,1) logical = true
    opts.ConnectTimeoutMs (1,1) double = 10000
end

host = string(opts.Host);
databaseName = string(opts.Database);
username = string(opts.Username);
password = string(opts.Password);

if strlength(username) == 0
    error("sixgr:util:connectMySQLJDBC:MissingUsername", ...
        "MySQL username is required. Set MYSQL_USER or pass 'Username'.");
end
if strlength(password) == 0
    error("sixgr:util:connectMySQLJDBC:MissingPassword", ...
        "MySQL password is required. Set MYSQL_PASSWORD or pass 'Password'.");
end

sixgr.util.ensureMySQLConnectorJ(Version=opts.DriverVersion);
try
    driver = javaObject("com.mysql.cj.jdbc.Driver");
catch ME
    error("sixgr:util:connectMySQLJDBC:DriverLoadFailed", ...
        "Failed to load the MySQL JDBC driver class: %s", ME.message);
end

dbSuffix = "";
if strlength(databaseName) > 0
    dbSuffix = "/" + databaseName;
end
url = "jdbc:mysql://" + host + ":" + string(opts.Port) + dbSuffix;

props = java.util.Properties;
props.setProperty("user", char(username));
props.setProperty("password", char(password));
props.setProperty("useSSL", localLogicalString(opts.UseSSL));
props.setProperty("allowPublicKeyRetrieval", ...
    localLogicalString(opts.AllowPublicKeyRetrieval));
props.setProperty("connectTimeout", string(opts.ConnectTimeoutMs));
props.setProperty("socketTimeout", string(opts.ConnectTimeoutMs));
props.setProperty("serverTimezone", "UTC");
props.setProperty("characterEncoding", "UTF-8");
props.setProperty("rewriteBatchedStatements", "true");
props.setProperty("useServerPrepStmts", "true");
props.setProperty("cachePrepStmts", "true");
props.setProperty("prepStmtCacheSize", "256");
props.setProperty("prepStmtCacheSqlLimit", "2048");
props.setProperty("maintainTimeStats", "false");
props.setProperty("useLocalSessionState", "true");

try
    conn = driver.connect(char(url), props);
    if isempty(conn)
        error("sixgr:util:connectMySQLJDBC:NullConnection", ...
            "Connector/J returned an empty connection for %s.", url);
    end
catch ME
    error("sixgr:util:connectMySQLJDBC:ConnectionFailed", ...
        "Failed to connect to %s as %s: %s", url, username, ME.message);
end

end

function value = localEnvOrDefault(name, defaultValue)
value = getenv(name);
if isempty(value)
    value = defaultValue;
end
end

function out = localLogicalString(tf)
if tf
    out = "true";
else
    out = "false";
end
end

function mustBeTextScalar(x)
if ~(ischar(x) || (isstring(x) && isscalar(x)))
    error("sixgr:util:connectMySQLJDBC:BadType", ...
        "Input must be a char vector or string scalar.");
end
end
