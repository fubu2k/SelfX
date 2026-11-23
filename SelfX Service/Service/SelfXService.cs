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
    Starts non-interactive PowerShell 7 (pwsh.exe) with the service identity and captures
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
    Built with the .NET 10 SDK (Projects\SelfXService\SelfXService.csproj); no remote API is used.

Notes:
    Name    : SelfXService.cs
    Package : SelfX Service
    Context : System (LOCAL SYSTEM service; current user in /console mode)
    Version : 2.8.3

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
    2.8.0    2026-11-23  fubu2k               First pipe instance with FirstPipeInstance (a pipe name that another process already owns is
                                              not joined: logged, retried); Windows event log entries 4001-4004 and 4099 (fixed texts,
                                              rate limited); ProgramData\SelfX is checked at start and daily (link, owner), the service
                                              writes nothing there while it is not safe (N3, N6, F12)
    2.6.11   2026-11-22  fubu2k               Pipe deadlines use overlapped I/O (asynchronous pipe handle), so a cancelled read or write
                                              ends reliably; one deadline for the whole request. The per-user connection limit is
                                              applied when the connection is accepted (owner of the client process), before any data
                                              is read
    2.8.0    2026-11-23  fubu2k               Header comments: build with the .NET 10 SDK (no .NET Framework compiler); version line
    2.8.1    2026-11-23  fubu2k               The OtherSessions check reads the sessions by name (WTSQuerySessionInformation) instead of WTSQueryUserToken:
                                              the service no longer needs SeTcbPrivilege (finding N5)
    2.8.2    2026-11-23  fubu2k               Before every start the service checks the installed scripts and configuration against SelfX.Files.json
                                              (SHA256, no unlisted script or XML file, no links); mismatch: nothing is started (event 4005),
                                              Tool_Config.xml Service_FileCheck=Audit only logs (finding N4)
    2.8.3    2026-11-23  fubu2k               Daily housekeeping also deletes device log reports older than 7 days (Reports\<SID>, only report files,
                                              only trusted folders without links) and empty user folders
*/

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.ServiceProcess;
using System.Text;
using System.Text.Json;
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
        // Device log reports (Reports\<SID>) are kept for 7 days at most; the collect action applies the same limit.
        const int ReportRetentionDays = 7;
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

        // Grace period after CancelIoEx until the cancelled operation has completed; afterwards the handle is closed.
        const int CancelGraceMs = 2000;
        // Connections whose client process owner cannot be read share one bucket with the per-user limit.
        const string UnknownClientKey = "client:unknown";

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool CancelIoEx(SafePipeHandle handle, IntPtr overlapped);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool GetNamedPipeClientProcessId(SafePipeHandle pipe, out uint processId);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern IntPtr OpenProcess(uint access, bool inheritHandle, uint processId);
        [DllImport("advapi32.dll", SetLastError = true)]
        static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
        // CloseHandle is declared below (used by the client check of F4).
        const uint ProcessQueryLimitedInformation = 0x1000;
        const uint TokenQuery = 0x0008;

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

        // User and domain of a session by name. Unlike WTSQueryUserToken this needs no SeTcbPrivilege (security review
        // finding N5: the service must not depend on one of the strongest privileges of LocalSystem).
        [DllImport("wtsapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern bool WTSQuerySessionInformationW(IntPtr server, int sessionId, int infoClass, out IntPtr buffer, out int bytesReturned);

        const int WtsUserName = 5;
        const int WtsDomainName = 7;

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
        // Defense in depth (finding F12): ProgramData\SelfX is checked when the service starts and before the daily housekeeping.
        // While it is not safe (link, or an owner other than SYSTEM, administrators, TrustedInstaller or the service account)
        // nothing is written there and no status cache is read or produced.
        volatile bool dataFolderSafe = true;
        static readonly string[] TrustedOwnerSids = { "S-1-5-18", "S-1-5-32-544", "S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464" };
        // The first pipe instance is created with FirstPipeInstance (finding N3): when another process already owns the pipe
        // name, the service does not join it but logs the problem and retries.
        bool firstPipeInstanceCreated;
        int pipeInUseFailures;
        // Windows event log (finding N6): only when running under the Service Control Manager, fixed texts, rate limited per
        // event ID (the Application log can be read by every user, so no request text and no user names go there).
        bool securityEventsEnabled;
        readonly object eventLock = new object();
        readonly Dictionary<int, EventWindow> eventWindows = new Dictionary<int, EventWindow>();
        const int MaxSecurityEventsPerWindow = 10;
        static readonly TimeSpan SecurityEventWindow = TimeSpan.FromMinutes(10);
        const int EventPipeInUse = 4001;
        const int EventRejected = 4002;
        const int EventPowerShellUnprotected = 4003;
        const int EventDataFolderUnsafe = 4004;
        const int EventFilesChanged = 4005;
        const int EventSuppressed = 4099;
        sealed class EventWindow { public DateTime Start = DateTime.MinValue; public int Count; public int Suppressed; }
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

            installRoot = AppContext.BaseDirectory.TrimEnd('\\');
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
            firstPipeInstanceCreated = false;
            pipeInUseFailures = 0;
            VerifyDataFolder();
            if (dataFolderSafe)
            {
                try { Directory.CreateDirectory(Path.GetDirectoryName(cacheFile)); } catch { }
            }
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
                    PipeOptions pipeOptions = PipeOptions.Asynchronous;
                    if (!firstPipeInstanceCreated)
                    {
                        // Fails when any other process already owns this pipe name (for example a user process that
                        // was faster at start): the service must not serve under a name that it does not control.
                        pipeOptions |= PipeOptions.FirstPipeInstance;
                    }
#if NET
                    // .NET (since 5): the constructor with PipeSecurity no longer exists, the access rules are set by this factory.
                    server = NamedPipeServerStreamAcl.Create(pipeName, PipeDirection.InOut, NamedPipeServerStream.MaxAllowedServerInstances,
                        PipeTransmissionMode.Byte, pipeOptions, 4096, 4096, security);
#else
                    server = new NamedPipeServerStream(pipeName, PipeDirection.InOut, NamedPipeServerStream.MaxAllowedServerInstances,
                        PipeTransmissionMode.Byte, pipeOptions, 4096, 4096, security);
#endif
                    if (!firstPipeInstanceCreated)
                    {
                        firstPipeInstanceCreated = true;
                        if (pipeInUseFailures > 0)
                        {
                            Log("The pipe name '" + pipeName + "' is free now; the service accepts connections.");
                        }
                        pipeInUseFailures = 0;
                    }
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
                        // The per-user limit is applied before any data is read: the key is the owner of the client
                        // process (from the kernel, not from the client), so one user cannot fill the global slots.
                        string clientKey = GetClientProcessKey(connection);
                        if (!EnterUser(clientKey))
                        {
                            Interlocked.Decrement(ref activeConnections);
                            connection.Dispose();
                            LogRejected("Rate limit: more than " + MaxConnectionsPerUser + " open connections from " + clientKey + "; a connection was refused.");
                            continue;
                        }
                        // A thread of its own, so that waiting connections cannot starve the thread pool.
                        Thread worker = new Thread(delegate() { HandleConnection(connection, clientKey); });
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
                    if (!stopping && !firstPipeInstanceCreated)
                    {
                        // Logged on the first failure and then once a minute (the retry runs every second).
                        pipeInUseFailures++;
                        if (pipeInUseFailures == 1 || pipeInUseFailures % 60 == 0)
                        {
                            Log("The pipe name '" + pipeName + "' is already in use by another process or cannot be created (" + ex.GetType().Name + "); the service does not accept connections until it is free.");
                            SecurityEvent(EventPipeInUse, EventLogEntryType.Error, "The pipe name of the SelfX service is already in use by another process; the service does not accept connections until it is free.");
                        }
                        Thread.Sleep(1000);
                    }
                    else if (!stopping)
                    {
                        Log("Listener error: " + ex.Message);
                        Thread.Sleep(1000);
                    }
                }
            }
        }

        /// <summary>
        /// Wait for one overlapped pipe operation until the deadline. On a timeout the I/O of the pipe is cancelled
        /// (CancelIoEx works reliably for overlapped I/O, the pipe is opened with PipeOptions.Asynchronous); if it
        /// still does not complete, the handle is closed. Returns false on a timeout.
        /// </summary>
        static bool WaitForPipeIo(NamedPipeServerStream pipe, IAsyncResult pending, int milliseconds)
        {
            if (pending.CompletedSynchronously || pending.AsyncWaitHandle.WaitOne(Math.Max(0, milliseconds)))
            {
                return true;
            }
            try { CancelIoEx(pipe.SafePipeHandle, IntPtr.Zero); } catch { }
            if (!pending.AsyncWaitHandle.WaitOne(CancelGraceMs))
            {
                try { pipe.Dispose(); } catch { }
            }
            return false;
        }

        /// <summary>
        /// Read one request line (bytes up to '\n', at most maxBytes) within one deadline for the whole request.
        /// A client that sends slowly cannot extend the deadline. Returns null on a timeout or when the client
        /// closes the connection before sending anything.
        /// </summary>
        static string ReadRequest(NamedPipeServerStream pipe, int maxBytes, int deadlineMs)
        {
            Stopwatch elapsed = Stopwatch.StartNew();
            MemoryStream line = new MemoryStream();
            byte[] buffer = new byte[256];
            while (line.Length < maxBytes)
            {
                int remaining = deadlineMs - (int)elapsed.ElapsedMilliseconds;
                if (remaining <= 0) return null;
                IAsyncResult pending = pipe.BeginRead(buffer, 0, buffer.Length, null, null);
                if (!WaitForPipeIo(pipe, pending, remaining)) return null;
                int count;
                try { count = pipe.EndRead(pending); }
                catch (IOException) { return null; }
                catch (OperationCanceledException) { return null; }
                catch (ObjectDisposedException) { return null; }
                if (count <= 0) break;
                int newline = Array.IndexOf(buffer, (byte)'\n', 0, count);
                int take = newline >= 0 ? newline : count;
                take = (int)Math.Min(take, maxBytes - line.Length);
                line.Write(buffer, 0, take);
                if (newline >= 0) break;
            }
            if (line.Length == 0 && elapsed.ElapsedMilliseconds >= deadlineMs) return null;
            // Invalid UTF-8 becomes U+FFFD and is then rejected by the request patterns.
            return Encoding.UTF8.GetString(line.ToArray()).Trim();
        }

        /// <summary>
        /// Write the answer within the deadline. Returns false when the client does not read it in time.
        /// </summary>
        static bool WriteResponse(NamedPipeServerStream pipe, string response, int deadlineMs)
        {
            byte[] data = new UTF8Encoding(false).GetBytes(response + "\r\n");
            IAsyncResult pending = pipe.BeginWrite(data, 0, data.Length, null, null);
            if (!WaitForPipeIo(pipe, pending, deadlineMs)) return false;
            try { pipe.EndWrite(pending); }
            catch (IOException) { return false; }
            catch (OperationCanceledException) { return false; }
            catch (ObjectDisposedException) { return false; }
            return true;
        }

        /// <summary>
        /// Keep the connection until the client has read the answer and closed its end, at most until the deadline
        /// (replaces WaitForPipeDrain, which cannot be cancelled). Extra data from the client is discarded.
        /// </summary>
        static void WaitForClientClose(NamedPipeServerStream pipe, int deadlineMs)
        {
            Stopwatch elapsed = Stopwatch.StartNew();
            byte[] buffer = new byte[256];
            while (true)
            {
                int remaining = deadlineMs - (int)elapsed.ElapsedMilliseconds;
                if (remaining <= 0) return;
                IAsyncResult pending = pipe.BeginRead(buffer, 0, buffer.Length, null, null);
                if (!WaitForPipeIo(pipe, pending, remaining)) return;
                try
                {
                    if (pipe.EndRead(pending) <= 0) return;
                }
                catch { return; }
            }
        }

        /// <summary>
        /// Key for the connection limit before anything is read: "sid:" + the owner SID of the client process.
        /// The process ID comes from the kernel (GetNamedPipeClientProcessId); a client cannot choose it. When the
        /// owner cannot be read (process already ended, access denied) the shared unknown bucket is used.
        /// </summary>
        static string GetClientProcessKey(NamedPipeServerStream pipe)
        {
            uint processId;
            try
            {
                if (!GetNamedPipeClientProcessId(pipe.SafePipeHandle, out processId) || processId == 0) return UnknownClientKey;
            }
            catch { return UnknownClientKey; }
            IntPtr process = OpenProcess(ProcessQueryLimitedInformation, false, processId);
            if (process == IntPtr.Zero) return UnknownClientKey;
            try
            {
                IntPtr token;
                if (!OpenProcessToken(process, TokenQuery, out token)) return UnknownClientKey;
                try
                {
                    using (WindowsIdentity owner = new WindowsIdentity(token))
                    {
                        return owner.User != null ? "sid:" + owner.User.Value : UnknownClientKey;
                    }
                }
                catch { return UnknownClientKey; }
                finally { CloseHandle(token); }
            }
            finally { CloseHandle(process); }
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
        void HandleConnection(NamedPipeServerStream pipe, string clientKey)
        {
            string user = "unknown";
            try
            {
                using (pipe)
                {
                    // One deadline for the whole request: a client that sends nothing or sends slowly is closed.
                    string request = ReadRequest(pipe, MaxRequestLength, RequestReadTimeoutMs);
                    if (request == null)
                    {
                        LogRejected("No complete request within " + (RequestReadTimeoutMs / 1000) + " s from " + clientKey + "; the connection was closed.");
                        return;
                    }
                    try { user = pipe.GetImpersonationUserName(); } catch { }
                    string callerSid = GetCallerSid(pipe);
                    bool callerIsAdmin = GetCallerIsAdmin(pipe);
                    long callerSession = -1;
                    try { uint sessionId; if (GetNamedPipeClientSessionId(pipe.SafePipeHandle, out sessionId)) callerSession = sessionId; } catch { }

                    string response = ProcessRequest(request, user, callerSid, callerIsAdmin, callerSession);
                    // A client that does not read the answer must not block this thread.
                    if (WriteResponse(pipe, response, ResponseWriteTimeoutMs))
                    {
                        WaitForClientClose(pipe, ClientCloseTimeoutMs);
                    }
                }
            }
            catch (Exception ex)
            {
                Log("Connection error (" + user + "): " + ex.Message);
            }
            finally
            {
                LeaveUser(clientKey);
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
        /// DOMAIN\user of a session, or null when it cannot be read or the session has no user.
        /// </summary>
        static string GetSessionAccount(int sessionId)
        {
            string user = QuerySessionString(sessionId, WtsUserName);
            string domain = QuerySessionString(sessionId, WtsDomainName);
            if (string.IsNullOrEmpty(user)) return null;
            return (domain ?? "") + "\\" + user;
        }

        static string QuerySessionString(int sessionId, int infoClass)
        {
            IntPtr buffer = IntPtr.Zero;
            int bytes;
            if (!WTSQuerySessionInformationW(IntPtr.Zero, sessionId, infoClass, out buffer, out bytes)) return null;
            try { return Marshal.PtrToStringUni(buffer); }
            finally { WTSFreeMemory(buffer); }
        }

        /// <summary>
        /// Number of ACTIVE sessions of other users (not the caller's session, not session 0, not another session of the
        /// caller's own account). The accounts are compared by DOMAIN\user as Windows reports it for the sessions, so no
        /// account lookup and no privilege beyond the service's normal rights is needed (works for local, domain and
        /// Entra ID accounts alike). Returns -1 when the sessions cannot be determined, so that the caller fails closed.
        /// </summary>
        static int CountOtherUserSessions(string callerSid, long callerSession)
        {
            if (callerSid == null || callerSession < 0 || callerSession > int.MaxValue) return -1;
            string callerAccount = GetSessionAccount((int)callerSession);
            if (callerAccount == null) return -1;
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
                    string account = GetSessionAccount(session.SessionId);
                    if (account == null) return -1;
                    if (!string.Equals(account, callerAccount, StringComparison.OrdinalIgnoreCase)) others++;
                }
                return others;
            }
            catch { return -1; }
            finally { WTSFreeMemory(info); }
        }

        const string FileListName = "SelfX.Files.json";
        const long MaxFileListBytes = 1048576;
        const int MaxFileProblems = 20;
        // Same rule as the generator (tools\New-SelfXIntuneWin.ps1): plain relative names with forward slashes.
        static readonly Regex ListedNamePattern = new Regex(@"^[A-Za-z0-9_][A-Za-z0-9_ .()\-]*(/[A-Za-z0-9_][A-Za-z0-9_ .()\-]*)*\z", RegexOptions.CultureInvariant);
        static readonly Regex Sha256Pattern = new Regex(@"^[0-9A-Fa-f]{64}\z", RegexOptions.CultureInvariant);
        // Files that PowerShell or the service load as code or configuration; none of them may exist without an entry in the list.
        static readonly string[] CheckedExtensions = { ".ps1", ".psm1", ".psd1", ".ps1xml", ".xml" };

        /// <summary>
        /// Finding N4: compare the installed scripts and configuration with SelfX.Files.json (written at package build, copied
        /// by Install.ps1). Every listed file must exist with the listed SHA256; no script or XML file below the root may be
        /// missing from the list; no link (junction, symbolic link) may be in the way. Returns false and the problems (at most
        /// 20, "kind: name") when anything differs, when the list is missing, too large or invalid (fail closed).
        /// </summary>
        static bool VerifyInstalledFiles(string root, out List<string> problems)
        {
            problems = new List<string>();
            try
            {
                root = root.TrimEnd('\\');
                string listPath = Path.Combine(root, FileListName);
                FileInfo listInfo = new FileInfo(listPath);
                if (!listInfo.Exists) { problems.Add("file list: missing"); return false; }
                if ((listInfo.Attributes & FileAttributes.ReparsePoint) != 0) { problems.Add("file list: is a link"); return false; }
                if (listInfo.Length > MaxFileListBytes) { problems.Add("file list: too large"); return false; }
                Dictionary<string, string> expected = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                using (JsonDocument document = JsonDocument.Parse(File.ReadAllBytes(listPath), new JsonDocumentOptions { MaxDepth = 4 }))
                {
                    JsonElement top = document.RootElement;
                    JsonElement version, files;
                    if (top.ValueKind != JsonValueKind.Object || !top.TryGetProperty("ManifestVersion", out version) ||
                        version.ValueKind != JsonValueKind.Number || version.GetInt32() != 1 ||
                        !top.TryGetProperty("Files", out files) || files.ValueKind != JsonValueKind.Object)
                    {
                        problems.Add("file list: unsupported format");
                        return false;
                    }
                    foreach (JsonProperty entry in files.EnumerateObject())
                    {
                        string hash = entry.Value.ValueKind == JsonValueKind.String ? entry.Value.GetString() : null;
                        if (!ListedNamePattern.IsMatch(entry.Name) || hash == null || !Sha256Pattern.IsMatch(hash) || expected.ContainsKey(entry.Name))
                        {
                            problems.Add("file list: invalid entry");
                            return false;
                        }
                        expected[entry.Name] = hash;
                    }
                }
                if (expected.Count == 0) { problems.Add("file list: empty"); return false; }

                foreach (KeyValuePair<string, string> entry in expected)
                {
                    if (problems.Count >= MaxFileProblems) break;
                    string full = Path.GetFullPath(Path.Combine(root, entry.Key.Replace('/', '\\')));
                    if (!full.StartsWith(root + "\\", StringComparison.OrdinalIgnoreCase)) { problems.Add("path: " + entry.Key); continue; }
                    if (!File.Exists(full)) { problems.Add("missing: " + entry.Key); continue; }
                    if (IsLinkBelow(root, full)) { problems.Add("link: " + entry.Key); continue; }
                    string actual;
                    try
                    {
                        using (FileStream stream = new FileStream(full, FileMode.Open, FileAccess.Read, FileShare.Read))
                        using (SHA256 sha = SHA256.Create())
                        {
                            actual = BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", "");
                        }
                    }
                    catch (IOException) { problems.Add("not readable: " + entry.Key); continue; }
                    if (!string.Equals(actual, entry.Value, StringComparison.OrdinalIgnoreCase)) problems.Add("changed: " + entry.Key);
                }
                FindUnlistedFiles(new DirectoryInfo(root), root, expected, problems);
                return problems.Count == 0;
            }
            catch (JsonException)
            {
                problems.Add("file list: invalid JSON");
                return false;
            }
            catch (Exception ex)
            {
                // Fail closed: when the list or the files cannot be read, nothing is started.
                problems.Add("check failed: " + ex.GetType().Name);
                return false;
            }
        }

        /// <summary>True when the file or one of its folders below the root is a link (junction, symbolic link).</summary>
        static bool IsLinkBelow(string root, string full)
        {
            FileSystemInfo item = new FileInfo(full);
            while (item != null && item.FullName.Length > root.Length)
            {
                if ((item.Attributes & FileAttributes.ReparsePoint) != 0) return true;
                item = item is FileInfo ? ((FileInfo)item).Directory : ((DirectoryInfo)item).Parent;
            }
            return false;
        }

        static void FindUnlistedFiles(DirectoryInfo folder, string root, Dictionary<string, string> listed, List<string> problems)
        {
            foreach (FileSystemInfo entry in folder.EnumerateFileSystemInfos())
            {
                if (problems.Count >= MaxFileProblems) return;
                string relative = entry.FullName.Substring(root.Length + 1).Replace('\\', '/');
                if ((entry.Attributes & FileAttributes.ReparsePoint) != 0) { problems.Add("link: " + relative); continue; }
                DirectoryInfo sub = entry as DirectoryInfo;
                if (sub != null) { FindUnlistedFiles(sub, root, listed, problems); continue; }
                if (Array.IndexOf(CheckedExtensions, entry.Extension.ToLowerInvariant()) < 0) continue;
                if (!listed.ContainsKey(relative)) problems.Add("not listed: " + relative);
            }
        }

        /// <summary>
        /// Called before every start of a script. Returns true when the installed files match SelfX.Files.json. Otherwise
        /// nothing is started (Enforce, default); with Service_FileCheck=Audit in Tool_Config.xml the problem is only logged.
        /// The setting counts only when the file list is intact and Tool_Config.xml itself is not among the problems.
        /// </summary>
        bool CheckInstalledFiles(string scriptName)
        {
            List<string> problems;
            if (VerifyInstalledFiles(installRoot, out problems)) return true;
            bool audit = false;
            bool settingTrusted = !problems.Exists(delegate(string p) { return p.StartsWith("file list:", StringComparison.Ordinal) || p.StartsWith("check failed:", StringComparison.Ordinal) || p.IndexOf("Tool_Config.xml", StringComparison.OrdinalIgnoreCase) >= 0; });
            if (settingTrusted) audit = string.Equals(ReadToolConfigValue("Service_FileCheck"), "Audit", StringComparison.OrdinalIgnoreCase);
            Log("Installed files do not match " + FileListName + " (" + string.Join("; ", problems.GetRange(0, Math.Min(5, problems.Count))) + "); '" + scriptName + (audit ? "' is started anyway (Service_FileCheck=Audit)." : "' was not started."));
            SecurityEvent(EventFilesChanged, audit ? EventLogEntryType.Warning : EventLogEntryType.Error,
                audit ? "Installed SelfX files do not match SelfX.Files.json (Audit: actions as SYSTEM are still started). See the SelfX log."
                      : "Installed SelfX files do not match SelfX.Files.json; SelfX actions as SYSTEM are not started. See the SelfX log.");
            return audit;
        }

        string ReadToolConfigValue(string name)
        {
            try
            {
                string toolConfig = Path.Combine(installRoot, "Tool_Config.xml");
                XmlReaderSettings settings = new XmlReaderSettings();
                settings.DtdProcessing = DtdProcessing.Prohibit;
                settings.XmlResolver = null;
                XmlDocument document = new XmlDocument();
                document.XmlResolver = null;
                using (XmlReader reader = XmlReader.Create(toolConfig, settings)) { document.Load(reader); }
                XmlNode node = document.SelectSingleNode("/GUI_Config/" + name);
                return node == null ? "" : node.InnerText.Trim();
            }
            catch { return ""; }
        }

        /// <summary>Fixed path of PowerShell 7 (machine-wide installation, writable only by administrators).</summary>
        static string PowerShellPath
        {
            get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), @"PowerShell\7\pwsh.exe"); }
        }

        /// <summary>
        /// The installer checks the rights of PowerShell 7 only when SelfX is installed. PowerShell 7 can arrive later
        /// (Autopilot installs apps in any order), so the service checks it again before every start: neither the folder
        /// nor pwsh.exe may allow Everyone, Authenticated Users, Interactive or Users to change files or permissions.
        /// A SYSTEM process must never run a program that normal users can replace.
        /// </summary>
        static bool IsPowerShellProtected(string executable, out string reason)
        {
            reason = "";
            string[] userSids = { "S-1-1-0", "S-1-5-11", "S-1-5-4", "S-1-5-32-545" };
            FileSystemRights dangerous = FileSystemRights.WriteData | FileSystemRights.AppendData | FileSystemRights.Delete |
                FileSystemRights.DeleteSubdirectoriesAndFiles | FileSystemRights.ChangePermissions | FileSystemRights.TakeOwnership;
            try
            {
                foreach (string path in new string[] { Path.GetDirectoryName(executable), executable })
                {
                    FileSystemSecurity security = path == executable
                        ? (FileSystemSecurity)new FileInfo(path).GetAccessControl()
                        : (FileSystemSecurity)new DirectoryInfo(path).GetAccessControl();
                    foreach (FileSystemAccessRule rule in security.GetAccessRules(true, true, typeof(SecurityIdentifier)))
                    {
                        if (rule.AccessControlType != AccessControlType.Allow) continue;
                        if (Array.IndexOf(userSids, rule.IdentityReference.Value) >= 0 && (rule.FileSystemRights & dangerous) != 0)
                        {
                            reason = "'" + path + "' can be changed by normal users (" + rule.IdentityReference.Value + ")";
                            return false;
                        }
                    }
                }
                return true;
            }
            catch (Exception ex)
            {
                // Fail closed: when the rights cannot be read, nothing is started.
                reason = "the rights could not be read (" + ex.GetType().Name + ")";
                return false;
            }
        }

        /// <summary>
        /// Run PowerShell under the service identity and log bounded output and completion.
        /// </summary>
        string RunScript(string scriptPath, string scriptName, int timeoutSeconds, string user, bool health = false, string healthFilter = "", string callerSid = null, bool background = false, bool callerIsAdmin = false)
        {
            // PowerShell 7 at its fixed machine-wide location (no PATH search, no user-writable folder). A missing
            // installation fails the action with a clear text instead of running anything else.
            if (health && !dataFolderSafe)
            {
                return "ERROR Data folder is not protected";
            }
            string powershell = PowerShellPath;
            if (!File.Exists(powershell))
            {
                Log("PowerShell 7 not found at '" + powershell + "'; '" + scriptName + "' was not started.");
                return "ERROR PowerShell 7 is not installed";
            }
            string unprotectedReason;
            if (!IsPowerShellProtected(powershell, out unprotectedReason))
            {
                Log("PowerShell 7 is not protected: " + unprotectedReason + "; '" + scriptName + "' was not started.");
                SecurityEvent(EventPowerShellUnprotected, EventLogEntryType.Warning, "PowerShell 7 is not protected against changes by normal users: " + unprotectedReason + ". SelfX actions as SYSTEM are not started.");
                return "ERROR PowerShell 7 is not protected";
            }
            FileVersionInfo version = FileVersionInfo.GetVersionInfo(powershell);
            if (version.FileMajorPart < 7 || (version.FileMajorPart == 7 && version.FileMinorPart < 6))
            {
                Log("PowerShell " + version.FileMajorPart + "." + version.FileMinorPart + " found; 7.6 or newer is required; '" + scriptName + "' was not started.");
                return "ERROR PowerShell 7.6 or newer is required";
            }
            // Finding N4: scripts and configuration must be exactly what the package contained.
            if (!CheckInstalledFiles(scriptName))
            {
                return "ERROR Installed files are not intact";
            }
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
            // Only machine-wide module folders: the module path of the service environment is not trusted for SYSTEM.
            startInfo.EnvironmentVariables["PSModulePath"] = Path.Combine(Path.GetDirectoryName(powershell), "Modules") + ";" +
                Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\Modules");
            startInfo.EnvironmentVariables["POWERSHELL_TELEMETRY_OPTOUT"] = "1";
            startInfo.EnvironmentVariables["POWERSHELL_UPDATECHECK"] = "Off";
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
            if (!dataFolderSafe) return prefix + "NONE" + suffix + "-";
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
                    VerifyDataFolder();
                    CleanupLogs();
                    CleanupReports();
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
            if (!dataFolderSafe) return 0;
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
        /// Delete old device log reports: ProgramData\SelfX\Reports\(user SID)\DeviceLogs-*.txt and .zip older than
        /// ReportRetentionDays, then empty user folders. Only folders named like a SID, only files named like a report, no links,
        /// and only folders owned by SYSTEM or administrators (the collect action creates them with a protected ACL), so
        /// a manipulated folder can never make SYSTEM delete other files.
        /// </summary>
        public int CleanupReports()
        {
            if (!dataFolderSafe) return 0;
            int deleted = 0;
            try
            {
                string dataRoot = Path.GetDirectoryName(logDirectory.TrimEnd('\\'));
                if (string.IsNullOrEmpty(dataRoot)) return 0;
                DirectoryInfo root = new DirectoryInfo(Path.Combine(dataRoot, "Reports"));
                if (!root.Exists || !IsTrustedFolder(root)) return 0;
                DateTime limit = DateTime.UtcNow.AddDays(-ReportRetentionDays);
                foreach (DirectoryInfo folder in root.GetDirectories())
                {
                    if (!Regex.IsMatch(folder.Name, @"\AS-1-[0-9]+(-[0-9]+)+\z") || !IsTrustedFolder(folder)) continue;
                    foreach (FileInfo file in folder.GetFiles())
                    {
                        string extension = file.Extension.ToLowerInvariant();
                        if (!file.Name.StartsWith("DeviceLogs-", StringComparison.Ordinal) || (extension != ".txt" && extension != ".zip")) continue;
                        if ((file.Attributes & FileAttributes.ReparsePoint) != 0) continue;
                        if (file.LastWriteTimeUtc >= limit) continue;
                        try
                        {
                            file.Delete();
                            deleted++;
                        }
                        catch { }
                    }
                    try
                    {
                        // Directory.Delete without recursion fails while the folder still has content.
                        if (folder.GetFileSystemInfos().Length == 0) folder.Delete();
                    }
                    catch { }
                }
                if (deleted > 0) Log("Report housekeeping: " + deleted + " report file(s) older than " + ReportRetentionDays + " days deleted.");
            }
            catch (Exception ex)
            {
                Log("Report housekeeping error: " + ex.Message);
            }
            return deleted;
        }

        /// <summary>
        /// True when the folder is no link and owned by SYSTEM, an administrator group or the service account.
        /// </summary>
        bool IsTrustedFolder(DirectoryInfo directory)
        {
            try
            {
                if ((directory.Attributes & FileAttributes.ReparsePoint) != 0) return false;
                SecurityIdentifier owner = (SecurityIdentifier)directory.GetAccessControl().GetOwner(typeof(SecurityIdentifier));
                string ownerSid = owner == null ? "" : owner.Value;
                return ownerSid == WindowsIdentity.GetCurrent().User.Value || Array.IndexOf(TrustedOwnerSids, ownerSid) >= 0;
            }
            catch
            {
                return false;
            }
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
                SecurityEvent(EventRejected, EventLogEntryType.Warning, "A request or connection to the SelfX service was rejected. Details are in SelfXService.log in the protected log folder.");
            }
        }

        /// <summary>
        /// Check ProgramData\SelfX (finding F12): no link, and an owner that only administrators can set. The installer prepares
        /// the folder; this check is the second line of defense when a user changed it later or created it before an update.
        /// </summary>
        bool CheckDataFolder(out string reason)
        {
            reason = "";
            string dataRoot = Path.GetDirectoryName(logDirectory.TrimEnd('\\'));
            string current = WindowsIdentity.GetCurrent().User.Value;
            foreach (string path in new string[] { dataRoot, logDirectory, Path.GetDirectoryName(cacheFile) })
            {
                if (string.IsNullOrEmpty(path)) continue;
                try
                {
                    DirectoryInfo directory = new DirectoryInfo(path);
                    if (!directory.Exists) continue;
                    if ((directory.Attributes & FileAttributes.ReparsePoint) != 0)
                    {
                        reason = "'" + path + "' is a link";
                        return false;
                    }
                    SecurityIdentifier owner = (SecurityIdentifier)directory.GetAccessControl().GetOwner(typeof(SecurityIdentifier));
                    string ownerSid = owner == null ? "" : owner.Value;
                    if (ownerSid != current && Array.IndexOf(TrustedOwnerSids, ownerSid) < 0)
                    {
                        reason = "'" + path + "' is owned by an account that is not trusted";
                        return false;
                    }
                }
                catch (Exception ex)
                {
                    // Fail closed: a folder that cannot be checked is not used.
                    reason = "'" + path + "' could not be checked (" + ex.GetType().Name + ")";
                    return false;
                }
            }
            return true;
        }

        void VerifyDataFolder()
        {
            string reason;
            bool safe = CheckDataFolder(out reason);
            bool was = dataFolderSafe;
            dataFolderSafe = safe;
            if (!safe && was)
            {
                // Nothing is written to the folder while it is not safe, so this goes to the Windows event log only.
                SecurityEvent(EventDataFolderUnsafe, EventLogEntryType.Error, "The SelfX data folder is not protected: " + reason + ". The service writes no log, cache or report there until an administrator repairs it (reinstall SelfX).");
            }
            else if (safe && !was)
            {
                Log("The data folder is protected again.");
            }
        }

        /// <summary>
        /// Enable the Windows event log entries (called only when running under the Service Control Manager).
        /// </summary>
        public void EnableSecurityEvents()
        {
            securityEventsEnabled = true;
        }

        /// <summary>
        /// Write a security-relevant event to the Application log: fixed texts only, at most MaxSecurityEventsPerWindow per
        /// event ID and 10 minutes; the number of events that were left out is reported once the window is over.
        /// </summary>
        void SecurityEvent(int id, EventLogEntryType type, string message)
        {
            if (!securityEventsEnabled) return;
            int suppressedBefore = 0;
            bool write = false;
            lock (eventLock)
            {
                EventWindow window;
                if (!eventWindows.TryGetValue(id, out window))
                {
                    window = new EventWindow();
                    eventWindows[id] = window;
                }
                DateTime now = DateTime.UtcNow;
                if (now - window.Start >= SecurityEventWindow)
                {
                    suppressedBefore = window.Suppressed;
                    window.Start = now;
                    window.Count = 0;
                    window.Suppressed = 0;
                }
                if (window.Count < MaxSecurityEventsPerWindow)
                {
                    window.Count++;
                    write = true;
                }
                else
                {
                    window.Suppressed++;
                }
            }
            try
            {
                if (suppressedBefore > 0)
                {
                    this.EventLog.WriteEntry("Event " + id + ": " + suppressedBefore + " further event(s) of this kind were not written.", EventLogEntryType.Warning, EventSuppressed);
                }
                if (write)
                {
                    this.EventLog.WriteEntry(message.Length > 800 ? message.Substring(0, 800) : message, type, id);
                }
            }
            catch { }
        }

        /// <summary>
        /// Append a timestamped entry with serialized size-based log rotation.
        /// </summary>
        void Log(string message)
        {
            message = CleanLogText(message);
            if (!dataFolderSafe) return;
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
                service.EnableSecurityEvents();
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
