/*
Summary:
    Host the local named-pipe endpoint for approved SelfX System actions.

Description:
    Installed by Install.ps1 as SelfXService running as LOCAL SYSTEM. Accepts local
    authenticated users through the default named pipe "SelfX.Service"; network clients
    are denied and users cannot create additional server instances through its ACL.
    PING returns PONG with the service protocol version. RUN accepts only a validated
    script filename listed with Context=System in the installed Issues_List.xml and
    present under the installed Scripts_to_run folder; user actions are not elevated.
    RUN children receive the SID of the requesting pipe client in SELFX_CALLER_SID, read
    from the client token (identification level), so scripts can deliver results only to
    that user. The variable is absent when the caller cannot be identified.
    HEALTH accepts no arguments and invokes only the installed HealthStatus.ps1 collector,
    returning bounded JSON as UTF-8/base64. It shares the repair lock and has a 240-second
    limit. Optional checks are configured in the administrator-protected Health_Config.xml.
    Every health run also updates the status cache ProgramData\SelfX\Cache\Health.json
    (readable by SYSTEM and administrators only). A background thread runs the full health
    collection at the interval of <Background> in Health_Config.xml (default every 15 minutes,
    first run 120 seconds after the start). It pauses on battery power, postpones while the
    processor load is above MaxCpuPercent or a repair is running, and runs PowerShell with
    below-normal priority. STATUS returns the cached result with its time, the interval and
    the background state without running anything, so the GUI and the tray icon show the
    status immediately.
    Starts non-interactive Windows PowerShell with the service identity and captures
    bounded output in ProgramData\SelfX\Logs by default, rotating SelfXService.log.
    Once a day (also while the background checks are disabled) the log housekeeping deletes
    *.log and *.old files in that folder that are older than Log_Retention_Days of
    Tool_Config.xml (1-3650, default 90). Subfolders such as Logs\Users are never cleaned by
    the service: users can create folders there, and SYSTEM must not follow links they could
    create (the users clean their own log folder, SelfXLog.ps1).
    Runs one action at a time; concurrent requests return BUSY. The default timeout is
    900 seconds, with positive catalog overrides (and TimeoutSeconds on a Health_Config
    Remediation) capped at 7200 seconds. A timeout
    attempts to kill the child process tree and returns TIMEOUT; completed actions
    return DONE with their exit code. ERROR reports request/authorization failures.
    Action side effects may include application closure, network/service interruption
    or disk-check scheduling; termination cannot undo completed changes. The service
    does not itself restart Windows. /console runs with the invoking user's rights;
    /pipe: and /logdir: override the endpoint and log location for troubleshooting.
    Program.Main returns 0 after normal service/console completion, not an action code.
    Compiled locally using the .NET Framework compiler (C# 5); no remote API is used.

Notes:
    Name    : SelfXService.cs
    Package : SelfX Service
    Context : System (LOCAL SYSTEM service; current user in /console mode)
    Version : 2.6.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.0.0    2026-10-28  Wolfgang Baeck       Initial version for SelfX Service
    2.2.0    2026-10-28  Wolfgang Baeck       Added description, history and comments
    2.3.0    2026-10-28  Wolfgang Baeck       Fixed HEALTH endpoint for protected local status checks
    2.3.1    2026-10-28  Wolfgang Baeck       Allow installed remediation scripts from protected health config
    2.3.2    2026-10-28  Wolfgang Baeck       Validated single-check HEALTH <Id> [base64 name] request
    2.3.3    2026-10-29  Wolfgang Baeck       Allow PendingReboot and Updates check Ids
    2.4.0    2026-11-02  Wolfgang Baeck       Pass the caller SID to RUN scripts (SELFX_CALLER_SID)
    2.5.0    2026-11-04  Wolfgang Baeck       Background health checks, status cache and STATUS request
    2.5.3    2026-11-04  Wolfgang Baeck       Log uses the current time zone (cache cleared after time zone changes)
    2.5.6    2026-11-05  Wolfgang Baeck       Optional TimeoutSeconds on Health_Config remediations (max. 7200)
    2.6.0    2026-11-06  Wolfgang Baeck       Daily log housekeeping (Log_Retention_Days in Tool_Config.xml, default 90)
    2.6.10   2026-11-22  fubu2k               Pipe hardening: deadline for reading the request and writing the answer, thread per
                                              connection, limits of 64 connections (8 per user), pause after HEALTH (3 s) and
                                              after a RUN of the same action by the same user (15 s)
    2.6.10   2026-11-22  fubu2k               Log hardening: request text is cleaned and shortened, rejected requests are rate limited;
                                              regex anchors use \z instead of $
    2.6.10   2026-11-22  fubu2k               RUN children also receive SELFX_CALLER_ADMIN (1 = elevated administrator, from the client token)
    2.6.10   2026-11-22  fubu2k               OtherSessions=Block (catalog element / Health_Config attribute): a normal user cannot start
                                              such an action while another user has an active session (answer ERROR OtherSessions)
*/

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using System.ServiceProcess;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using Microsoft.Win32.SafeHandles;
using System.Xml;

namespace SelfX
{
    /// <summary>
    /// Host local requests and serialize execution of catalog-approved System scripts.
    /// </summary>
    public class SelfXService : ServiceBase
    {
        public const string DefaultServiceName = "SelfXService";
        public const string DefaultPipeName = "SelfX.Service";
        public const string Version = "1.1.0";

        const int DefaultTimeoutSeconds = 900;
        const int MaxTimeoutSeconds = 7200;
        const int MaxRequestLength = 512;
        const int MaxOutputLength = 20000;
        const int MaxCacheLength = 60000;
        const int HealthTimeoutSeconds = 240;
        const long MaxLogBytes = 5 * 1024 * 1024;
        // Log hardening: text from requests is shortened and cleaned; rejected requests are rate limited so that a user
        // cannot flood the log and rotate older entries out (the log keeps only one .old file).
        const int MaxLogMessageLength = 600;
        const int MaxRejectedLogsPerWindow = 20;
        static readonly TimeSpan RejectedLogWindow = TimeSpan.FromMinutes(1);
        DateTime rejectedWindowStart = DateTime.MinValue;
        int rejectedInWindow = 0;
        int rejectedSuppressed = 0;
        const int DefaultLogRetentionDays = 90;
        // Pipe hardening: every local user can open the pipe, so a connection that sends nothing (or never reads the
        // answer) must not hold a thread forever, and one user must not use up all connections or the run slot.
        const int RequestReadTimeoutMs = 5000;
        const int ResponseWriteTimeoutMs = 10000;
        const int ClientCloseTimeoutMs = 10000;
        const int MaxConnections = 64;
        const int MaxConnectionsPerUser = 8;
        const int RunCooldownSeconds = 15;
        const int HealthCooldownSeconds = 3;
        readonly object limitLock = new object();
        readonly Dictionary<string, int> connectionsPerUser = new Dictionary<string, int>();
        readonly Dictionary<string, DateTime> cooldowns = new Dictionary<string, DateTime>();
        int activeConnections;

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool CancelIoEx(SafePipeHandle handle, IntPtr overlapped);

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool GetNamedPipeClientSessionId(SafePipeHandle pipe, out uint clientSessionId);

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool CloseHandle(IntPtr handle);

        [StructLayout(LayoutKind.Sequential)]
        struct WtsSessionInfo
        {
            public int SessionId;
            public IntPtr WinStationName;
            public int State;
        }

        [DllImport("wtsapi32.dll", SetLastError = true)]
        static extern bool WTSEnumerateSessions(IntPtr server, int reserved, int version, out IntPtr sessionInfo, out int count);

        [DllImport("wtsapi32.dll")]
        static extern void WTSFreeMemory(IntPtr memory);

        [DllImport("wtsapi32.dll", SetLastError = true)]
        static extern bool WTSQueryUserToken(int sessionId, out IntPtr token);

        const int WtsActive = 0;

        static readonly Regex ScriptNamePattern = new Regex(@"^[A-Za-z0-9_\-\.]{1,100}\.ps1\z", RegexOptions.IgnoreCase);
        static readonly Regex HealthRequestPattern = new Regex(
            @"^HEALTH(?: (IME|Defender|Compliance|Applications|Disk|BitLocker|PendingReboot|Updates|Service|Custom)(?: ([A-Za-z0-9+/]{2,400}={0,2}))?)?\z",
            RegexOptions.CultureInvariant);

        readonly string installRoot;
        readonly string scriptsRoot;
        readonly string catalogPath;
        readonly string logDirectory;
        readonly string cacheFile;
        readonly string pipeName;
        readonly object logLock = new object();
        readonly SemaphoreSlim runLock = new SemaphoreSlim(1, 1);
        // Serializes all health runs, because each of them writes the status cache.
        readonly SemaphoreSlim healthLock = new SemaphoreSlim(1, 1);
        readonly ManualResetEvent stopEvent = new ManualResetEvent(false);
        volatile bool stopping;
        volatile string backgroundState = "Active";
        volatile int backgroundInterval = 15;
        volatile int backgroundProcessId;
        DateTime lastBackgroundAttempt = DateTime.MinValue;
        DateTime lastHousekeeping = DateTime.MinValue;
        string lastBackgroundNote = "";
        Thread listener;
        Thread background;

        /// <summary>
        /// Settings of the background health check (Health_Config.xml, element Background).
        /// </summary>
        sealed class BackgroundSettings
        {
            public bool Enabled = true;
            public int IntervalMinutes = 15;
            public bool PauseOnBattery = true;
            public int MaxCpuPercent = 75;
            public int StartDelaySeconds = 120;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct SystemPowerStatus
        {
            public byte ACLineStatus;
            public byte BatteryFlag;
            public byte BatteryLifePercent;
            public byte SystemStatusFlag;
            public int BatteryLifeTime;
            public int BatteryFullLifeTime;
        }

        [DllImport("kernel32.dll")]
        static extern bool GetSystemPowerStatus(out SystemPowerStatus status);

        [DllImport("kernel32.dll")]
        static extern bool GetSystemTimes(out long idleTime, out long kernelTime, out long userTime);

        /// <summary>
        /// Resolve installed payload paths and configure the service endpoint and logging.
        /// </summary>
        public SelfXService(string pipeName, string logDirectory)
        {
            ServiceName = DefaultServiceName;
            CanStop = true;
            CanShutdown = true;
            AutoLog = true;

            installRoot = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\');
            scriptsRoot = Path.Combine(installRoot, "Scripts_to_run");
            catalogPath = Path.Combine(installRoot, "Issues_List.xml");
            this.pipeName = pipeName;
            this.logDirectory = logDirectory;
            // The cache folder is a sibling of the log folder (default ProgramData\SelfX\Cache).
            string dataRoot = Path.GetDirectoryName(logDirectory.TrimEnd('\\'));
            cacheFile = Path.Combine(Path.Combine(string.IsNullOrEmpty(dataRoot) ? logDirectory : dataRoot, "Cache"), "Health.json");
        }

        /// <summary>
        /// Start the pipe listener when the Service Control Manager starts the service.
        /// </summary>
        protected override void OnStart(string[] args)
        {
            StartListening();
        }

        /// <summary>
        /// Stop accepting connections when the Service Control Manager stops the service.
        /// </summary>
        protected override void OnStop()
        {
            StopListening();
        }

        /// <summary>
        /// Stop accepting connections when Windows notifies the service of shutdown.
        /// </summary>
        protected override void OnShutdown()
        {
            StopListening();
        }

        /// <summary>
        /// Start a background listener without blocking the service start callback.
        /// </summary>
        public void StartListening()
        {
            stopping = false;
            stopEvent.Reset();
            try { Directory.CreateDirectory(Path.GetDirectoryName(cacheFile)); } catch { }
            listener = new Thread(ListenLoop);
            listener.IsBackground = true;
            listener.Name = "SelfXPipeListener";
            listener.Start();
            background = new Thread(BackgroundLoop);
            background.IsBackground = true;
            background.Name = "SelfXBackgroundHealth";
            background.Start();
            Log("Service started. Version " + Version + ", pipe '" + pipeName + "', root '" + installRoot + "'.");
        }

        /// <summary>
        /// Wake the blocked listener and wait briefly for it to stop accepting connections.
        /// </summary>
        public void StopListening()
        {
            stopping = true;
            stopEvent.Set();
            // A running background collection is only reading; stop it with the service.
            int pid = backgroundProcessId;
            if (pid != 0)
            {
                KillProcessTree(pid);
            }
            // Unblock WaitForConnection.
            try
            {
                using (NamedPipeClientStream client = new NamedPipeClientStream(".", pipeName, PipeDirection.InOut))
                {
                    client.Connect(1000);
                }
            }
            catch { }
            if (listener != null)
            {
                listener.Join(5000);
            }
            if (background != null)
            {
                background.Join(5000);
            }
            Log("Service stopped.");
        }

        /// <summary>
        /// Allow local requests while denying network clients and user-owned pipe instances.
        /// </summary>
        PipeSecurity CreatePipeSecurity()
        {
            PipeSecurity security = new PipeSecurity();
            // Remote clients are never allowed.
            security.AddAccessRule(new PipeAccessRule(new SecurityIdentifier(WellKnownSidType.NetworkSid, null), PipeAccessRights.FullControl, AccessControlType.Deny));
            security.AddAccessRule(new PipeAccessRule(new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null), PipeAccessRights.FullControl, AccessControlType.Allow));
            security.AddAccessRule(new PipeAccessRule(new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null), PipeAccessRights.FullControl, AccessControlType.Allow));
            security.AddAccessRule(new PipeAccessRule(WindowsIdentity.GetCurrent().User, PipeAccessRights.FullControl, AccessControlType.Allow));
            // ReadWrite does not include CreateNewInstance, so users cannot add their own server instance.
            security.AddAccessRule(new PipeAccessRule(new SecurityIdentifier(WellKnownSidType.AuthenticatedUserSid, null), PipeAccessRights.ReadWrite, AccessControlType.Allow));
            return security;
        }

        /// <summary>
        /// Accept pipe connections and dispatch each connection to the thread pool.
        /// </summary>
        void ListenLoop()
        {
            PipeSecurity security = CreatePipeSecurity();
            while (!stopping)
            {
                NamedPipeServerStream server = null;
                try
                {
                    server = new NamedPipeServerStream(pipeName, PipeDirection.InOut, NamedPipeServerStream.MaxAllowedServerInstances,
                        PipeTransmissionMode.Byte, PipeOptions.None, 4096, 4096, security);
                    server.WaitForConnection();
                    if (stopping)
                    {
                        server.Dispose();
                        break;
                    }
                    NamedPipeServerStream connection = server;
                    server = null;
                    if (Interlocked.Increment(ref activeConnections) > MaxConnections)
                    {
                        Interlocked.Decrement(ref activeConnections);
                        connection.Dispose();
                        LogRejected("Connection limit (" + MaxConnections + ") reached; a connection was refused.");
                    }
                    else
                    {
                        // A thread of its own, so that waiting connections cannot starve the thread pool.
                        Thread worker = new Thread(delegate() { HandleConnection(connection); });
                        worker.IsBackground = true;
                        worker.Name = "SelfX.Pipe";
                        worker.Start();
                    }
                }
                catch (Exception ex)
                {
                    if (server != null)
                    {
                        server.Dispose();
                    }
                    if (!stopping)
                    {
                        Log("Listener error: " + ex.Message);
                        Thread.Sleep(1000);
                    }
                }
            }
        }

        /// <summary>
        /// Run a blocking pipe operation with a deadline. When the deadline passes, the pending I/O of the pipe is
        /// cancelled (CancelIoEx), so the operation ends and the connection can be closed. Returns false on a timeout.
        /// </summary>
        static bool RunWithDeadline(NamedPipeServerStream pipe, int milliseconds, Action operation)
        {
            bool[] timedOut = new bool[1];
            using (ManualResetEvent finished = new ManualResetEvent(false))
            using (Timer watchdog = new Timer(delegate(object state)
            {
                try
                {
                    if (!finished.WaitOne(0))
                    {
                        Volatile.Write(ref timedOut[0], true);
                        CancelIoEx(pipe.SafePipeHandle, IntPtr.Zero);
                    }
                }
                catch { }
            }, null, milliseconds, 250))
            {
                try
                {
                    operation();
                }
                catch (IOException)
                {
                    if (!Volatile.Read(ref timedOut[0])) throw;
                }
                catch (ObjectDisposedException)
                {
                    if (!Volatile.Read(ref timedOut[0])) throw;
                }
                finally
                {
                    finished.Set();
                }
            }
            return !Volatile.Read(ref timedOut[0]);
        }

        /// <summary>
        /// Key for the per-user limits: the SID from the client token, or the user name when the SID is unknown.
        /// </summary>
        static string LimitKey(string user, string callerSid)
        {
            return callerSid != null ? callerSid : "user:" + user;
        }

        bool EnterUser(string key)
        {
            lock (limitLock)
            {
                int count;
                connectionsPerUser.TryGetValue(key, out count);
                if (count >= MaxConnectionsPerUser) return false;
                connectionsPerUser[key] = count + 1;
                return true;
            }
        }

        void LeaveUser(string key)
        {
            lock (limitLock)
            {
                int count;
                if (!connectionsPerUser.TryGetValue(key, out count)) return;
                if (count <= 1) connectionsPerUser.Remove(key);
                else connectionsPerUser[key] = count - 1;
            }
        }

        bool InCooldown(string key)
        {
            lock (limitLock)
            {
                DateTime until;
                return cooldowns.TryGetValue(key, out until) && DateTime.UtcNow < until;
            }
        }

        void StartCooldown(string key, int seconds)
        {
            lock (limitLock)
            {
                DateTime now = DateTime.UtcNow;
                if (cooldowns.Count > 500)
                {
                    List<string> expired = new List<string>();
                    foreach (KeyValuePair<string, DateTime> entry in cooldowns)
                    {
                        if (entry.Value <= now) expired.Add(entry.Key);
                    }
                    foreach (string expiredKey in expired) cooldowns.Remove(expiredKey);
                }
                cooldowns[key] = now.AddSeconds(seconds);
            }
        }

        /// <summary>
        /// Read one UTF-8 request, identify its caller and return one protocol response.
        /// </summary>
        void HandleConnection(NamedPipeServerStream pipe)
        {
            string user = "unknown";
            string limitKey = null;
            try
            {
                using (pipe)
                {
                    UTF8Encoding encoding = new UTF8Encoding(false);
                    StreamReader reader = new StreamReader(pipe, encoding, false, 1024, true);
                    StreamWriter writer = new StreamWriter(pipe, encoding, 1024, true);
                    writer.AutoFlush = true;

                    string request = null;
                    bool received = RunWithDeadline(pipe, RequestReadTimeoutMs, delegate { request = ReadLine(reader, MaxRequestLength); });
                    if (!received || request == null)
                    {
                        LogRejected("No complete request within " + (RequestReadTimeoutMs / 1000) + " s; the connection was closed.");
                        return;
                    }
                    try { user = pipe.GetImpersonationUserName(); } catch { }
                    string callerSid = GetCallerSid(pipe);
                    bool callerIsAdmin = GetCallerIsAdmin(pipe);
                    long callerSession = -1;
                    try { uint sessionId; if (GetNamedPipeClientSessionId(pipe.SafePipeHandle, out sessionId)) callerSession = sessionId; } catch { }

                    string key = LimitKey(user, callerSid);
                    string response;
                    if (EnterUser(key))
                    {
                        limitKey = key;
                        response = ProcessRequest(request, user, callerSid, callerIsAdmin, callerSession);
                    }
                    else
                    {
                        LogRejected("Rate limit: more than " + MaxConnectionsPerUser + " open connections from " + user + "; request refused.");
                        response = "BUSY";
                    }
                    // A client that does not read the answer must not block this thread: the write has a deadline, and
                    // the connection is kept until the client has read the answer and closed its end (replaces
                    // WaitForPipeDrain, which cannot be cancelled).
                    if (RunWithDeadline(pipe, ResponseWriteTimeoutMs, delegate { writer.WriteLine(response); }))
                    {
                        RunWithDeadline(pipe, ClientCloseTimeoutMs, delegate { while (pipe.ReadByte() >= 0) { } });
                    }
                }
            }
            catch (Exception ex)
            {
                Log("Connection error (" + user + "): " + ex.Message);
            }
            finally
            {
                if (limitKey != null) LeaveUser(limitKey);
                Interlocked.Decrement(ref activeConnections);
            }
        }

        /// <summary>
        /// True only when the pipe client token has the local Administrators group enabled
        /// (an elevated administrator). Any error returns false (fail closed: reduced view).
        /// </summary>
        static bool GetCallerIsAdmin(NamedPipeServerStream pipe)
        {
            bool isAdmin = false;
            try
            {
                pipe.RunAsClient(delegate
                {
                    using (WindowsIdentity client = WindowsIdentity.GetCurrent(true))
                    {
                        if (client != null)
                        {
                            isAdmin = new WindowsPrincipal(client).IsInRole(WindowsBuiltInRole.Administrator);
                        }
                    }
                });
            }
            catch
            {
                return false;
            }
            return isAdmin;
        }

        /// <summary>
        /// Return the SID of the pipe client, or null when it cannot be read.
        /// </summary>
        static string GetCallerSid(NamedPipeServerStream pipe)
        {
            string sid = null;
            try
            {
                // Identification-level impersonation is enough to query the client token.
                // GetCurrent(true) returns null without a thread token, never the service identity.
                pipe.RunAsClient(delegate
                {
                    using (WindowsIdentity client = WindowsIdentity.GetCurrent(true))
                    {
                        if (client != null && client.User != null)
                        {
                            sid = client.User.Value;
                        }
                    }
                });
            }
            catch
            {
                return null;
            }
            return sid;
        }

        /// <summary>
        /// Read a bounded request line and remove surrounding whitespace.
        /// </summary>
        static string ReadLine(StreamReader reader, int maxLength)
        {
            StringBuilder line = new StringBuilder();
            while (line.Length < maxLength)
            {
                int c = reader.Read();
                if (c < 0 || c == '\n')
                {
                    break;
                }
                if (c != '\r')
                {
                    line.Append((char)c);
                }
            }
            return line.ToString().Trim();
        }

        /// <summary>
        /// Validate a request and run one approved action, or return a protocol rejection.
        /// </summary>
        string ProcessRequest(string request, string user, string callerSid, bool callerIsAdmin, long callerSession)
        {
            if (string.IsNullOrEmpty(request))
            {
                return "ERROR Empty request";
            }
            if (request == "PING")
            {
                return "PONG " + Version;
            }
            if (request == "STATUS")
            {
                return GetStatusResponse();
            }
            Match healthMatch = HealthRequestPattern.Match(request);
            if (healthMatch.Success)
            {
                string healthScript = Path.Combine(installRoot, "HealthStatus.ps1");
                if (!File.Exists(healthScript)) return "ERROR Health collector not installed";
                // Single-check filter: Id is whitelisted, Name is base64 so no quoting reaches the command line.
                string filter = "";
                if (healthMatch.Groups[1].Success)
                {
                    filter = " -OnlyId " + healthMatch.Groups[1].Value;
                    if (healthMatch.Groups[2].Success)
                    {
                        try { Convert.FromBase64String(healthMatch.Groups[2].Value); }
                        catch (FormatException) { return "ERROR Invalid health check name"; }
                        filter += " -OnlyName " + healthMatch.Groups[2].Value;
                    }
                }
                // Per user, a short pause after each check: one user cannot keep the run slot busy for everybody.
                string healthKey = "HEALTH|" + LimitKey(user, callerSid);
                if (InCooldown(healthKey))
                {
                    LogRejected("Rate limit: HEALTH request from " + user + " refused.");
                    return "BUSY";
                }
                if (!runLock.Wait(0)) return "BUSY";
                try
                {
                    // A running background collection finishes first (at most HealthTimeoutSeconds).
                    if (!healthLock.Wait(TimeSpan.FromSeconds(HealthTimeoutSeconds + 10))) return "BUSY";
                    try
                    {
                        return RunScript(healthScript, "HealthStatus.ps1", HealthTimeoutSeconds, user, true, filter);
                    }
                    finally { healthLock.Release(); }
                }
                finally
                {
                    runLock.Release();
                    StartCooldown(healthKey, HealthCooldownSeconds);
                }
            }
            if (request.StartsWith("HEALTH", StringComparison.Ordinal))
            {
                return "ERROR Invalid health request";
            }
            if (!request.StartsWith("RUN ", StringComparison.Ordinal))
            {
                return "ERROR Unknown command";
            }

            string scriptName = request.Substring(4).Trim();
            if (!ScriptNamePattern.IsMatch(scriptName) || scriptName.Contains(".."))
            {
                LogRejected("Rejected invalid request from " + user + ": '" + scriptName + "'.");
                return "ERROR Invalid action";
            }

            int timeoutSeconds;
            bool blockOtherSessions;
            // Elevation is granted only to System entries, never arbitrary client-supplied scripts.
            if (!TryGetSystemAction(scriptName, out timeoutSeconds, out blockOtherSessions))
            {
                LogRejected("Rejected request from " + user + ": '" + scriptName + "' is not a System action in the catalog.");
                return "ERROR Action is not allowed";
            }

            string scriptPath = Path.GetFullPath(Path.Combine(scriptsRoot, scriptName));
            if (!scriptPath.StartsWith(scriptsRoot + "\\", StringComparison.OrdinalIgnoreCase) || !File.Exists(scriptPath))
            {
                LogRejected("Rejected request from " + user + ": script '" + scriptName + "' not found.");
                return "ERROR Script not found";
            }

            // Disruptive actions (restart, network, disk check, updates): a normal user may not start them while another
            // user has an active session. Elevated administrators are not restricted. Fail closed if sessions cannot be read.
            if (blockOtherSessions && !callerIsAdmin)
            {
                int others = CountOtherUserSessions(callerSid, callerSession);
                if (others != 0)
                {
                    LogRejected("Request from " + user + " for '" + scriptName + "' refused: " + (others < 0 ? "sessions could not be checked" : "another user is signed in") + ".");
                    return "ERROR OtherSessions";
                }
            }

            // The same user cannot start the same action again right after it ended (the run slot is shared by all users).
            string runKey = "RUN|" + LimitKey(user, callerSid) + "|" + scriptName.ToLowerInvariant();
            if (InCooldown(runKey))
            {
                LogRejected("Rate limit: request from " + user + " for '" + scriptName + "' refused.");
                return "BUSY";
            }
            // Refuse concurrent repairs rather than queueing potentially conflicting changes.
            if (!runLock.Wait(0))
            {
                Log("Busy: request from " + user + " for '" + scriptName + "' refused.");
                return "BUSY";
            }
            try
            {
                return RunScript(scriptPath, scriptName, timeoutSeconds, user, false, "", callerSid, false, callerIsAdmin);
            }
            finally
            {
                runLock.Release();
                StartCooldown(runKey, RunCooldownSeconds);
            }
        }

        /// <summary>
        /// Check the installed System-action whitelist and resolve a bounded execution timeout.
        /// </summary>
        bool TryGetSystemAction(string scriptName, out int timeoutSeconds, out bool blockOtherSessions)
        {
            timeoutSeconds = DefaultTimeoutSeconds;
            blockOtherSessions = false;
            XmlReaderSettings settings = new XmlReaderSettings();
            // Catalog loading must not resolve external entities or fetch network resources.
            settings.DtdProcessing = DtdProcessing.Prohibit;
            settings.XmlResolver = null;

            XmlDocument catalog = new XmlDocument();
            catalog.XmlResolver = null;
            using (XmlReader reader = XmlReader.Create(catalogPath, settings))
            {
                catalog.Load(reader);
            }

            // scriptName is validated by ScriptNamePattern, so it contains no quotes.
            XmlNode action = catalog.SelectSingleNode(
                "//Action[normalize-space(Context)='System' and normalize-space(Script)='" + scriptName + "']");
            if (action == null)
            {
                string healthConfig = Path.Combine(installRoot, "Health_Config.xml");
                if (!File.Exists(healthConfig)) return false;
                XmlDocument health = new XmlDocument();
                health.XmlResolver = null;
                using (XmlReader reader = XmlReader.Create(healthConfig, settings)) { health.Load(reader); }
                XmlNode remediation = health.SelectSingleNode("/HealthConfig/Remediations/Remediation[@Script='" + scriptName + "']");
                if (remediation == null) return false;
                XmlAttribute remediationSessions = remediation.Attributes["OtherSessions"];
                blockOtherSessions = remediationSessions != null && remediationSessions.Value.Trim() == "Block";
                // Optional TimeoutSeconds attribute (long repairs such as installing updates), bounded like catalog actions.
                XmlAttribute remediationTimeout = remediation.Attributes["TimeoutSeconds"];
                int remediationConfigured;
                if (remediationTimeout != null && int.TryParse(remediationTimeout.Value.Trim(), out remediationConfigured) && remediationConfigured > 0)
                {
                    timeoutSeconds = Math.Min(remediationConfigured, MaxTimeoutSeconds);
                }
                return true;
            }

            // A script can have several catalog entries: Block applies when any System entry of the script says Block.
            blockOtherSessions = catalog.SelectSingleNode(
                "//Action[normalize-space(Context)='System' and normalize-space(Script)='" + scriptName + "' and normalize-space(OtherSessions)='Block']") != null;

            XmlNode timeoutNode = action.SelectSingleNode("TimeoutSeconds");
            int configured;
            if (timeoutNode != null && int.TryParse(timeoutNode.InnerText.Trim(), out configured) && configured > 0)
            {
                timeoutSeconds = Math.Min(configured, MaxTimeoutSeconds);
            }
            return true;
        }

        /// <summary>
        /// Number of ACTIVE sessions of other users (not the caller's session, not session 0, not the caller's own SID).
        /// Returns -1 when the sessions cannot be determined, so that the caller fails closed.
        /// </summary>
        static int CountOtherUserSessions(string callerSid, long callerSession)
        {
            if (callerSid == null || callerSession < 0) return -1;
            IntPtr info = IntPtr.Zero;
            int count;
            if (!WTSEnumerateSessions(IntPtr.Zero, 0, 1, out info, out count)) return -1;
            try
            {
                int others = 0;
                int size = Marshal.SizeOf(typeof(WtsSessionInfo));
                for (int i = 0; i < count; i++)
                {
                    WtsSessionInfo session = (WtsSessionInfo)Marshal.PtrToStructure(new IntPtr(info.ToInt64() + (long)i * size), typeof(WtsSessionInfo));
                    if (session.State != WtsActive || session.SessionId == 0 || session.SessionId == callerSession) continue;
                    IntPtr token;
                    if (!WTSQueryUserToken(session.SessionId, out token)) return -1;
                    try
                    {
                        using (WindowsIdentity identity = new WindowsIdentity(token))
                        {
                            if (identity.User == null || identity.User.Value != callerSid) others++;
                        }
                    }
                    catch { return -1; }
                    finally { CloseHandle(token); }
                }
                return others;
            }
            catch { return -1; }
            finally { WTSFreeMemory(info); }
        }

        /// <summary>
        /// Run PowerShell under the service identity and log bounded output and completion.
        /// </summary>
        string RunScript(string scriptPath, string scriptName, int timeoutSeconds, string user, bool health = false, string healthFilter = "", string callerSid = null, bool background = false, bool callerIsAdmin = false)
        {
            string powershell = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe");
            // Health runs also update the status cache; the path contains no quotes.
            ProcessStartInfo startInfo = new ProcessStartInfo(powershell,
                "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"" + scriptPath + "\"" +
                (health ? " -Collect" + healthFilter + " -CacheFile \"" + cacheFile + "\"" : ""));
            startInfo.UseShellExecute = false;
            startInfo.CreateNoWindow = true;
            startInfo.RedirectStandardOutput = true;
            startInfo.RedirectStandardError = true;
            if (health)
            {
                startInfo.StandardOutputEncoding = Encoding.UTF8;
                startInfo.StandardErrorEncoding = Encoding.UTF8;
            }
            startInfo.WorkingDirectory = health ? installRoot : scriptsRoot;
            // Remove any inherited value so only a SID read from the client token reaches the script.
            startInfo.EnvironmentVariables.Remove("SELFX_CALLER_SID");
            startInfo.EnvironmentVariables.Remove("SELFX_CALLER_ADMIN");
            if (!health && callerSid != null)
            {
                startInfo.EnvironmentVariables["SELFX_CALLER_SID"] = callerSid;
                // 1 only for an elevated administrator (read from the client token); scripts treat anything else as a normal user.
                startInfo.EnvironmentVariables["SELFX_CALLER_ADMIN"] = callerIsAdmin ? "1" : "0";
            }

            StringBuilder output = new StringBuilder();
            bool outputOverflow = false;
            object outputLock = new object();
            DataReceivedEventHandler collect = delegate(object sender, DataReceivedEventArgs e)
            {
                if (e.Data == null) return;
                lock (outputLock)
                {
                    if (output.Length + e.Data.Length + Environment.NewLine.Length <= MaxOutputLength)
                    {
                        output.AppendLine(e.Data);
                    }
                    else { outputOverflow = true; }
                }
            };

            if (!background)
            {
                Log("Start '" + scriptName + "' requested by " + user + " (timeout " + timeoutSeconds + " s).");
            }
            Stopwatch watch = Stopwatch.StartNew();
            string result;
            using (Process process = new Process())
            {
                process.StartInfo = startInfo;
                process.OutputDataReceived += collect;
                process.ErrorDataReceived += collect;
                process.Start();
                if (background)
                {
                    backgroundProcessId = process.Id;
                    // Background checks must not slow down the user's work.
                    try { process.PriorityClass = ProcessPriorityClass.BelowNormal; } catch { }
                }
                // Drain both redirected streams asynchronously to avoid pipe-buffer deadlocks.
                process.BeginOutputReadLine();
                process.BeginErrorReadLine();

                if (!process.WaitForExit(timeoutSeconds * 1000))
                {
                    // Descendants may outlive PowerShell; attempt tree termination on timeout.
                    KillProcessTree(process.Id);
                    result = "TIMEOUT";
                }
                else
                {
                    // Finish asynchronous output callbacks before reading the captured output.
                    process.WaitForExit();
                    result = "DONE " + process.ExitCode;
                }
                if (background)
                {
                    backgroundProcessId = 0;
                }
            }

            string text;
            lock (outputLock)
            {
                text = output.ToString().Trim();
            }
            if (background)
            {
                // Only a summary: the result is in the status cache and would fill the log every interval.
                Log("Background health check: " + result + " after " + (int)watch.Elapsed.TotalSeconds + " s.");
                return result;
            }
            Log("End '" + scriptName + "' requested by " + user + ": " + result + " after " + (int)watch.Elapsed.TotalSeconds + " s." +
                (text.Length > 0 ? Environment.NewLine + "    " + text.Replace(Environment.NewLine, Environment.NewLine + "    ") : ""));
            if (health && result == "DONE 0")
            {
                if (outputOverflow) return "ERROR Health response exceeds size limit";
                return "HEALTH " + Convert.ToBase64String(Encoding.UTF8.GetBytes(text));
            }
            return result;
        }

        /// <summary>
        /// Return the cached health result: STATUS &lt;time UTC|NONE&gt; &lt;interval minutes&gt; &lt;state&gt; &lt;base64 JSON|-&gt;.
        /// </summary>
        string GetStatusResponse()
        {
            string state = backgroundState;
            string prefix = "STATUS ";
            string suffix = " " + backgroundInterval.ToString(CultureInfo.InvariantCulture) + " " + state + " ";
            for (int attempt = 0; attempt < 3; attempt++)
            {
                try
                {
                    if (!File.Exists(cacheFile)) return prefix + "NONE" + suffix + "-";
                    DateTime written = File.GetLastWriteTimeUtc(cacheFile);
                    byte[] bytes = File.ReadAllBytes(cacheFile);
                    if (bytes.Length == 0 || bytes.Length > MaxCacheLength) return prefix + "NONE" + suffix + "-";
                    return prefix + written.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture) + suffix + Convert.ToBase64String(bytes);
                }
                catch (IOException)
                {
                    // The cache is replaced by a rename; retry once it is complete.
                    Thread.Sleep(100);
                }
            }
            return "ERROR Status cache not readable";
        }

        /// <summary>
        /// Read the Background element of Health_Config.xml; missing or invalid values use the defaults.
        /// </summary>
        BackgroundSettings ReadBackgroundSettings()
        {
            BackgroundSettings result = new BackgroundSettings();
            try
            {
                string healthConfig = Path.Combine(installRoot, "Health_Config.xml");
                if (!File.Exists(healthConfig)) return result;
                XmlReaderSettings settings = new XmlReaderSettings();
                settings.DtdProcessing = DtdProcessing.Prohibit;
                settings.XmlResolver = null;
                XmlDocument document = new XmlDocument();
                document.XmlResolver = null;
                using (XmlReader reader = XmlReader.Create(healthConfig, settings)) { document.Load(reader); }
                XmlElement node = document.SelectSingleNode("/HealthConfig/Background") as XmlElement;
                if (node == null) return result;
                int value;
                if (node.HasAttribute("Enabled")) result.Enabled = !string.Equals(node.GetAttribute("Enabled"), "false", StringComparison.OrdinalIgnoreCase);
                if (node.HasAttribute("PauseOnBattery")) result.PauseOnBattery = !string.Equals(node.GetAttribute("PauseOnBattery"), "false", StringComparison.OrdinalIgnoreCase);
                if (int.TryParse(node.GetAttribute("IntervalMinutes"), NumberStyles.Integer, CultureInfo.InvariantCulture, out value) && value >= 5 && value <= 1440) result.IntervalMinutes = value;
                if (int.TryParse(node.GetAttribute("MaxCpuPercent"), NumberStyles.Integer, CultureInfo.InvariantCulture, out value) && value >= 10 && value <= 100) result.MaxCpuPercent = value;
                if (int.TryParse(node.GetAttribute("StartDelaySeconds"), NumberStyles.Integer, CultureInfo.InvariantCulture, out value) && value >= 0 && value <= 3600) result.StartDelaySeconds = value;
            }
            catch (Exception ex)
            {
                LogBackgroundNote("Background settings not readable, defaults are used: " + ex.Message);
            }
            return result;
        }

        /// <summary>
        /// True when the device runs on battery (AC line offline).
        /// </summary>
        static bool IsOnBattery()
        {
            SystemPowerStatus status;
            return GetSystemPowerStatus(out status) && status.ACLineStatus == 0;
        }

        /// <summary>
        /// Processor load in percent over one second, or 0 when it cannot be measured.
        /// </summary>
        int GetCpuPercent()
        {
            long idle1, kernel1, user1, idle2, kernel2, user2;
            if (!GetSystemTimes(out idle1, out kernel1, out user1)) return 0;
            if (stopEvent.WaitOne(1000)) return 0;
            if (!GetSystemTimes(out idle2, out kernel2, out user2)) return 0;
            // Kernel time includes idle time.
            long total = (kernel2 - kernel1) + (user2 - user1);
            if (total <= 0) return 0;
            return (int)Math.Round(100.0 * (total - (idle2 - idle1)) / total);
        }

        /// <summary>
        /// Log a background note only when it differs from the previous one (no repeated lines every minute).
        /// </summary>
        void LogBackgroundNote(string note)
        {
            if (note == lastBackgroundNote) return;
            lastBackgroundNote = note;
            Log(note);
        }

        /// <summary>
        /// Run the full health collection at the configured interval while the device is idle enough.
        /// </summary>
        void BackgroundLoop()
        {
            BackgroundSettings settings = ReadBackgroundSettings();
            // STATUS reports the configured interval and state already before the first run.
            backgroundInterval = settings.Enabled ? settings.IntervalMinutes : 0;
            backgroundState = !settings.Enabled ? "Disabled" : (settings.PauseOnBattery && IsOnBattery() ? "Battery" : "Active");
            if (stopEvent.WaitOne(TimeSpan.FromSeconds(settings.StartDelaySeconds))) return;
            while (!stopping)
            {
                TimeSpan wait = TimeSpan.FromSeconds(60);
                // Log housekeeping once a day, also when the background checks are disabled or paused.
                if (DateTime.UtcNow - lastHousekeeping >= TimeSpan.FromHours(24))
                {
                    lastHousekeeping = DateTime.UtcNow;
                    CleanupLogs();
                }
                try
                {
                    settings = ReadBackgroundSettings();
                    backgroundInterval = settings.Enabled ? settings.IntervalMinutes : 0;
                    if (!settings.Enabled)
                    {
                        backgroundState = "Disabled";
                        LogBackgroundNote("Background health checks are disabled in Health_Config.xml.");
                    }
                    else if (settings.PauseOnBattery && IsOnBattery())
                    {
                        backgroundState = "Battery";
                        LogBackgroundNote("Background health checks paused: the device runs on battery.");
                    }
                    else
                    {
                        backgroundState = "Active";
                        DateTime last = lastBackgroundAttempt;
                        if (File.Exists(cacheFile))
                        {
                            DateTime written = File.GetLastWriteTimeUtc(cacheFile);
                            if (written > last) last = written;
                        }
                        if (DateTime.UtcNow - last >= TimeSpan.FromMinutes(settings.IntervalMinutes))
                        {
                            string postpone = null;
                            int cpu = settings.MaxCpuPercent < 100 ? GetCpuPercent() : 0;
                            if (stopping) return;
                            if (cpu > settings.MaxCpuPercent) postpone = "processor load " + cpu + " %";
                            else if (runLock.CurrentCount == 0) postpone = "a repair is running";
                            else if (!healthLock.Wait(0)) postpone = "a health check is running";
                            if (postpone == null)
                            {
                                try
                                {
                                    lastBackgroundAttempt = DateTime.UtcNow;
                                    string healthScript = Path.Combine(installRoot, "HealthStatus.ps1");
                                    if (File.Exists(healthScript))
                                    {
                                        LogBackgroundNote("Background health checks active (every " + settings.IntervalMinutes + " minutes).");
                                        RunScript(healthScript, "HealthStatus.ps1", HealthTimeoutSeconds, "background", true, "", null, true);
                                    }
                                }
                                finally { healthLock.Release(); }
                            }
                            else
                            {
                                LogBackgroundNote("Background health check postponed: " + postpone + ".");
                                wait = TimeSpan.FromSeconds(120);
                            }
                        }
                    }
                }
                catch (Exception ex)
                {
                    Log("Background health check error: " + ex.Message);
                }
                if (stopEvent.WaitOne(wait)) return;
            }
        }

        /// <summary>
        /// Days to keep log files: Log_Retention_Days of Tool_Config.xml (1-3650), default 90.
        /// </summary>
        int ReadLogRetentionDays()
        {
            try
            {
                string toolConfig = Path.Combine(installRoot, "Tool_Config.xml");
                if (!File.Exists(toolConfig)) return DefaultLogRetentionDays;
                XmlReaderSettings settings = new XmlReaderSettings();
                settings.DtdProcessing = DtdProcessing.Prohibit;
                settings.XmlResolver = null;
                XmlDocument document = new XmlDocument();
                document.XmlResolver = null;
                using (XmlReader reader = XmlReader.Create(toolConfig, settings)) { document.Load(reader); }
                XmlNode node = document.SelectSingleNode("/GUI_Config/Log_Retention_Days");
                int value;
                if (node != null && int.TryParse(node.InnerText.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out value) && value >= 1 && value <= 3650) return value;
            }
            catch (Exception ex)
            {
                Log("Log retention not readable, " + DefaultLogRetentionDays + " days are used: " + ex.Message);
            }
            return DefaultLogRetentionDays;
        }

        /// <summary>
        /// Delete *.log and *.old files older than the retention in the log folder (not in subfolders).
        /// The user folders under Logs\Users are cleaned by the users themselves (SelfXLog.ps1): users can
        /// create folders there, so SYSTEM never deletes in them (no junction or link can redirect a deletion).
        /// </summary>
        public int CleanupLogs()
        {
            int days = ReadLogRetentionDays();
            DateTime limit = DateTime.UtcNow.AddDays(-days);
            int deleted = 0;
            try
            {
                DirectoryInfo root = new DirectoryInfo(logDirectory);
                if (!root.Exists || (root.Attributes & FileAttributes.ReparsePoint) != 0) return 0;
                foreach (FileInfo file in root.GetFiles())
                {
                    string extension = file.Extension.ToLowerInvariant();
                    if (extension != ".log" && extension != ".old") continue;
                    if ((file.Attributes & FileAttributes.ReparsePoint) != 0) continue;
                    if (file.LastWriteTimeUtc >= limit) continue;
                    try
                    {
                        file.Delete();
                        deleted++;
                    }
                    catch { }
                }
                if (deleted > 0) Log("Log housekeeping: " + deleted + " log file(s) older than " + days + " days deleted.");
            }
            catch (Exception ex)
            {
                Log("Log housekeeping error: " + ex.Message);
            }
            return deleted;
        }

        /// <summary>
        /// Attempt to terminate the timed-out action and its descendants by process ID.
        /// </summary>
        static void KillProcessTree(int processId)
        {
            try
            {
                ProcessStartInfo kill = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "taskkill.exe"), "/PID " + processId + " /T /F");
                kill.UseShellExecute = false;
                kill.CreateNoWindow = true;
                using (Process killer = Process.Start(kill))
                {
                    killer.WaitForExit(10000);
                }
            }
            catch { }
        }

        /// <summary>
        /// Make text from a request safe for one log line: control characters and Unicode line or
        /// paragraph separators become '?', and the text is shortened.
        /// </summary>
        static string CleanLogText(string text)
        {
            if (text == null)
            {
                return "";
            }
            StringBuilder clean = new StringBuilder(Math.Min(text.Length, MaxLogMessageLength + 3));
            foreach (char c in text)
            {
                if (clean.Length >= MaxLogMessageLength)
                {
                    clean.Append("...");
                    break;
                }
                bool unsafeChar = char.IsControl(c) || c == '\u2028' || c == '\u2029' || c == '\u0085';
                clean.Append(unsafeChar ? '?' : c);
            }
            return clean.ToString();
        }

        /// <summary>
        /// Log a rejected request, at most MaxRejectedLogsPerWindow per minute; the rest is only counted.
        /// </summary>
        void LogRejected(string message)
        {
            string summary = null;
            bool write = false;
            lock (logLock)
            {
                DateTime now = DateTime.UtcNow;
                if (now - rejectedWindowStart >= RejectedLogWindow)
                {
                    if (rejectedSuppressed > 0)
                    {
                        summary = "Rate limit: " + rejectedSuppressed + " further rejected request(s) in the last minute were not logged.";
                    }
                    rejectedWindowStart = now;
                    rejectedInWindow = 0;
                    rejectedSuppressed = 0;
                }
                if (rejectedInWindow < MaxRejectedLogsPerWindow)
                {
                    rejectedInWindow++;
                    write = true;
                }
                else
                {
                    rejectedSuppressed++;
                }
            }
            if (summary != null)
            {
                Log(summary);
            }
            if (write)
            {
                Log(message);
            }
        }

        /// <summary>
        /// Append a timestamped entry with serialized size-based log rotation.
        /// </summary>
        void Log(string message)
        {
            message = CleanLogText(message);
            try
            {
                lock (logLock)
                {
                    Directory.CreateDirectory(logDirectory);
                    string path = Path.Combine(logDirectory, "SelfXService.log");
                    FileInfo info = new FileInfo(path);
                    if (info.Exists && info.Length > MaxLogBytes)
                    {
                        string old = path + ".old";
                        if (File.Exists(old))
                        {
                            File.Delete(old);
                        }
                        File.Move(path, old);
                    }
                    // The service runs for days: refresh the cached time zone (for example after the automatic
                    // time zone change during the OOBE) so the log shows the current local time of the device.
                    TimeZoneInfo.ClearCachedData();
                    File.AppendAllText(path, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + message + Environment.NewLine, Encoding.UTF8);
                }
            }
            catch { }
        }
    }

    /// <summary>
    /// Provide service-host and interactive troubleshooting entry points.
    /// </summary>
    public static class Program
    {
        /// <summary>
        /// Run under the Service Control Manager or wait for Ctrl+C in console mode.
        /// </summary>
        public static int Main(string[] args)
        {
            string pipeName = SelfXService.DefaultPipeName;
            string logDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), @"SelfX\Logs");
            bool console = false;

            foreach (string arg in args)
            {
                if (arg.Equals("/console", StringComparison.OrdinalIgnoreCase))
                {
                    console = true;
                }
                else if (arg.StartsWith("/pipe:", StringComparison.OrdinalIgnoreCase))
                {
                    pipeName = arg.Substring(6);
                }
                else if (arg.StartsWith("/logdir:", StringComparison.OrdinalIgnoreCase))
                {
                    logDirectory = arg.Substring(8);
                }
            }

            SelfXService service = new SelfXService(pipeName, logDirectory);
            if (!console)
            {
                ServiceBase.Run(service);
                return 0;
            }

            // Console mode for troubleshooting: runs with the rights of the current user.
            ManualResetEvent done = new ManualResetEvent(false);
            Console.CancelKeyPress += delegate(object sender, ConsoleCancelEventArgs e)
            {
                e.Cancel = true;
                done.Set();
            };
            service.StartListening();
            Console.WriteLine("SelfX service " + SelfXService.Version + " listening on pipe '" + pipeName + "'. Press Ctrl+C to stop.");
            done.WaitOne();
            service.StopListening();
            return 0;
        }
    }
}
