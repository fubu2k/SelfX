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
    Layout: the service runs from the code folder App; the configuration (Tool_Config.xml,
    Issues_List.xml, Health_Config.xml, Branding, own scripts, language files and text
    overrides of the company) is in the folder Config next to it (GetConfigRoot). A script of the project is
    started from App\Scripts_to_run; an own script of the company from Config\Scripts_to_run
    only when it is listed in Config\SelfX.Config.json with its current SHA256 (also with
    Service_FileCheck=Audit). The file check compares App with SelfX.Code.json and Config with
    SelfX.Config.json; the install folder above them may hold nothing but App and Config.
    Trust mode (docs\Architecture.md): before every start the service reads the anchor HKLM\SOFTWARE\SelfX\Trust that
    Install.ps1 wrote (64-bit view; Mode = Hash or Signature, Signers = SHA1 thumbprints). The anchor counts only when the key
    is owned by SYSTEM or Administrators and no other identity may change it; a missing, invalid or unprotected anchor starts
    nothing (event 4006). Mode Hash: the file check as described above. Mode Signature: every file of the two lists is opened
    once (readable for others, not writable, not replaceable) and stays open until the script has ended; SelfX.Code.json must be
    a member of the signed catalog App\SelfX.Code.cat and SelfX.Config.json a member of Config\SelfX.Config.cat; the file check
    runs on the open handles; every .ps1, .psm1, .psd1 and .dll of the lists (the script to start, the scripts it loads, the
    libraries, own scripts of the company) must carry an Authenticode signature; Issues_List.xml, Health_Config.xml and the
    other settings files must be members of SelfX.Config.cat. A signature counts when Windows accepts it (WinVerifyTrust) and
    the signer is in the list of the anchor. Revocation is checked from the local cache only (no network request, so the
    service does not wait without a network). A failed signature check starts nothing (event 4007), also with
    Service_FileCheck=Audit. A positive result is kept for 60 minutes per file (path, write time, size and SHA256 of the open
    handle), so the health runs do not repeat the signature check of unchanged files.
    RUN children receive the SID of the requesting pipe client in SELFX_CALLER_SID, read
    from the client token (identification level), so scripts can deliver results only to
    that user. The variable is absent when the caller cannot be identified.
    APPRETRY <app id> retries one Intune app: the client sends only an ID in the form of a GUID. The service reads the
    IME cache (HKLM\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps, 64-bit view, read only) itself and accepts the
    ID only when that reading lists the app as not installed; it then starts the fixed repair SelfX_Apps_RetryInstall.ps1
    (listed in Health_Config.xml, same checks as RUN: TerminalServer, OtherSessions, pause, run slot) and hands the ID that
    it read itself to the script in SELFX_APP_ID. The ID is never used as a path or an argument.
    HEALTH accepts no arguments and invokes only the installed HealthStatus.ps1 collector,
    returning bounded JSON as UTF-8/base64. It shares the repair lock and has a 240-second
    limit. Optional checks are configured in the administrator-protected Health_Config.xml.
    Every health run also updates the status cache ProgramData\SelfX\Cache\Health.json
    (readable by SYSTEM and administrators only). With <Inventory Enabled="true"> in Health_Config.xml (default off) every full
    health run also appends one JSON line with a fixed schema (SchemaVersion, time, mode, status per check type, failed apps with
    their error code; no names, no detail texts) to ProgramData\SelfX\Inventory\SelfX.Inventory.json (same rights as the cache;
    rotated to SelfX.Inventory.json.old at MaxSizeKB), for a log collector such as the Azure Monitor Agent. Not written while
    the device status is off (mode TerminalServer with TerminalServer_Health Off). A background thread runs the full health
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
    Windows event log: own classic log SelfX (Applications and Services Logs), source SelfXService, created by Install.ps1.
    Every entry carries its fields as separate insertion strings in a fixed order (field 1 = fixed English text): security
    events 4001-4008 (at most 10 per ID in 10 minutes), System action started/succeeded/failed 4010-4012 and a health row that
    changed to Error 4013 and an Intune app that changed to failed 4014 (at most 20 per ID and minute), 4099 = entries left out. No user names, no paths, no detail texts; the
    SID of the caller only with EventLog_CallerSid = True in Tool_Config.xml. Fields are cleaned (control characters) and shortened.
    Built with the .NET 10 SDK (Projects\SelfXService\SelfXService.csproj); no remote API is used.

Notes:
    Name    : SelfXService.cs
    Package : SelfX Service
    Context : System (LOCAL SYSTEM service; current user in /console mode)
    Version : 2.9.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.0.0    2026-10-28  Wolfgang Baeck       Initial version for SelfX Service
    2.8.4    2026-11-23  fubu2k               The file check also covers .dll files: a DLL below the install folder (WinRT) must be listed in
    2.8.5    2026-11-23  fubu2k               The file check also covers .exe files: SelfXService.exe and SelfX.exe are compared by SHA256,
                                              an unlisted .exe below the install folder is refused
    2.8.19   2026-11-23  fubu2k               Installer helper SafeTree (/removetree:, /cleandata:): deletes folder trees through handles opened
                                              with FILE_FLAG_OPEN_REPARSE_POINT, without a time window between check and delete (M1)
    2.8.20   2026-11-23  fubu2k               N1: Tool_Config.xml and Issues_List.xml are checked first, a check cut off at 20 problems is noted
                                              (log, event 4005; Service_FileCheck=Audit is then ignored). N2: a file of any type without an entry
                                              in the list is refused. N3: the rights check of PowerShell 7 accepts only SYSTEM, Administrators and
                                              TrustedInstaller as writers, also for the folders above pwsh.exe up to the drive root
    2.8.21   2026-11-23  fubu2k               N5: an unexpected exception while a request is processed is logged (type and cleaned message) and answered
                                              with the fixed text "ERROR Internal error" (no details; the client shows Error, not a timeout).
                                              N6: every PowerShell child (RUN, HEALTH, background) is put into a job object with
                                              KILL_ON_JOB_CLOSE; when the service stops, the whole process tree is ended, so an update or
                                              uninstall finds no SYSTEM process that still holds files. No new action starts while stopping.
    2.9.0    2026-11-27  fubu2k               The file check reads two lists, SelfX.Code.json and SelfX.Config.json, instead of SelfX.Files.json; a file
                                              in both lists or in the wrong list (placement rule) is an invalid entry (event 4005)
    3.1.0    2026-11-27  fubu2k               Code and configuration in two folders: catalog, Health_Config.xml and Tool_Config.xml are read only from
                                              Config (GetConfigFilePath), scripts of the project only from App; an own script below Config is started
                                              only when SelfX.Config.json lists it with its current SHA256 and the catalog or Health_Config.xml names
                                              it; the file check covers App (SelfX.Code.json), Config (SelfX.Config.json) and the folder above them
    3.1.0    2026-11-27  fubu2k               Text overrides: Texts/<culture>.xml is accepted in SelfX.Config.json (placement rule); nothing below
                                              Texts may be in SelfX.Code.json
    3.1.0    2026-11-27  fubu2k               Trust mode: the anchor HKLM\SOFTWARE\SelfX\Trust is read before every start (event 4006 when it is
                                              missing, invalid or can be changed by normal users). Mode Signature: files are checked through
                                              handles that stay open during the run; lists against the signed catalogs SelfX.Code.cat and
                                              SelfX.Config.cat, scripts and libraries by their embedded signature, settings files against
                                              SelfX.Config.cat (WinVerifyTrust, signer from the anchor, revocation from the cache only; event
                                              4007); positive results are cached for 60 minutes. Mode Hash: unchanged
    3.1.0    2026-11-27  fubu2k               SafeTree /cleanold:<root> /minage:<days>: deletes old entries below one of four fixed folders
                                              (Windows\Temp and three Intune Management Extension content folders, resolved in this file, never
                                              from an argument) through handles, without following links (free disk space, SelfX_Device_FreeSpace.ps1)
    3.1.0    2026-11-27  fubu2k               Environment_Mode (Tool_Config.xml: Client or TerminalServer). TerminalServer: RUN refuses a
                                              script unless all its catalog entries or its remediation are classified TerminalServer Show, for
                                              every caller (event 4008); an unreadable Tool_Config.xml counts as TerminalServer. At the start a
                                              warning when Windows is a session host but the mode is Client (event 4009); the mode is never
                                              switched by the service. The check of other active sessions (OtherSessions) is the same in both modes
    3.1.0    2026-11-28  fubu2k               TerminalServer_Health (Off or AdminOnly, only with Environment_Mode TerminalServer): Off = no
                                              background checks (Background Enabled is ignored), no status cache, HEALTH and STATUS answer
                                              UNAVAILABLE TerminalServer to every caller; AdminOnly = only elevated administrators get HEALTH and
                                              STATUS. Any other value and an unreadable Tool_Config.xml count as Off. The log housekeeping keeps running
    3.1.0    2026-11-28  fubu2k               The mode comes from Windows, not from a setting: product type workstation (Windows 11) = Client,
                                              every other product type (Windows Server, Windows Enterprise multi-session) and version data that
                                              cannot be read = TerminalServer (fail closed). Environment_Mode of Tool_Config.xml is ignored (a note
                                              in the log when it is still there); the warning of event 4009 is gone (the mode can no longer differ)
    3.1.0    2026-11-28  fubu2k               Own event log SelfX (source SelfXService, AutoLog off): entries with separate fields (EventInstance);
                                              new events 4010-4012 (System action started, succeeded, failed: script, result, exit code,
                                              duration, SID only with EventLog_CallerSid = True) and 4013 (health row changed to Error: type,
                                              name, previous status); own rate limit of 20 per ID and minute for them; 4099 with fields
    3.1.0    2026-11-28  fubu2k               APPRETRY <app id> (protocol 1.2.0): retry of one Intune app. The ID must be a GUID and must be
                                              listed as not installed in the own reading of the IME cache (Win32Apps, read only); the fixed
                                              repair SelfX_Apps_RetryInstall.ps1 gets it in SELFX_APP_ID (removed for every other start).
                                              Event 4014 (Intune app changed to failed: app ID, error code, previous state) after a health run,
                                              from the same reading; operational rate limit
    3.1.0    2026-11-28  fubu2k               Inventory file (Health_Config.xml Inventory Enabled="true", default off): after every full health run
                                              one JSON line with schema version 1 in ProgramData\SelfX\Inventory\SelfX.Inventory.json (status per
                                              check type, failed apps with code, no names or detail texts), rotation at MaxSizeKB (64-10240, default
                                              1024) to SelfX.Inventory.json.old, no link followed; nothing while TerminalServer_Health is Off
    3.1.0    2026-11-28  fubu2k               SafeTree (/removetree:, /cleandata:, /cleanold:): every entry below the root is used only when the
                                              final path of its handle is exactly the expected path. A user could turn an empty folder into a
                                              junction in place while it was open, so that the entries listed and opened through it lay outside
                                              the root (delete as SYSTEM outside Windows\Temp). Such entries are kept and counted.
    3.1.0    2026-11-28  fubu2k               When="NotOK" in the service: a normal user can start a repair that Health_Config.xml offers only while its
                                              check is not OK (and that is no System action of the catalog) only while the status cache of the last 60
                                              minutes lists that row as not OK (answer ERROR NotNeeded otherwise; administrators are not restricted).
                                              HEALTH without a filter is answered from a status cache of the last 60 seconds instead of a new run
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
using System.Security.Cryptography.X509Certificates;
using System.Security.Principal;
using System.ServiceProcess;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading;
using Microsoft.Win32;
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
        public const string Version = "1.2.0";

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
        // A HEALTH request without a filter is answered from the status cache when a full collection wrote it at most this long ago:
        // repeated requests (several windows, a loop) do not occupy the single run slot.
        const int HealthCacheReuseSeconds = 60;
        // A repair with When="NotOK" starts for a normal user only while a status cache of at most this age lists its row as not OK.
        const int RemediationCacheMaxAgeMinutes = 60;
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

        // User and domain of a session by name. Unlike WTSQueryUserToken this needs no SeTcbPrivilege (the service must not depend on one of the strongest
        // privileges of LocalSystem).
        [DllImport("wtsapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern bool WTSQuerySessionInformationW(IntPtr server, int sessionId, int infoClass, out IntPtr buffer, out int bytesReturned);

        const int WtsUserName = 5;
        const int WtsDomainName = 7;

        const int WtsActive = 0;

        // Version data of the running Windows: the product type decides the mode (Client or TerminalServer, IsTerminalServer).
        // RtlGetVersion is not subject to the compatibility manifest like GetVersionEx and VerifyVersionInfo (deprecated since
        // Windows 10). Layout: RTL_OSVERSIONINFOEXW (wdm.h) = OSVERSIONINFOEXW (winnt.h).
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct OsVersionInfoEx
        {
            public int OSVersionInfoSize;
            public int MajorVersion;
            public int MinorVersion;
            public int BuildNumber;
            public int PlatformId;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
            public string CSDVersion;
            public ushort ServicePackMajor;
            public ushort ServicePackMinor;
            public ushort SuiteMask;
            public byte ProductType;
            public byte Reserved;
        }

        [DllImport("ntdll.dll")]
        static extern int RtlGetVersion(ref OsVersionInfoEx versionInformation);

        // wProductType and wSuiteMask values of OSVERSIONINFOEXW (winnt.h).
        const byte VerNtWorkstation = 1;
        const ushort VerSuiteTerminal = 0x0010;
        const ushort VerSuiteSingleUserTs = 0x0100;

        static readonly Regex ScriptNamePattern = new Regex(@"^[A-Za-z0-9_\-\.]{1,100}\.ps1\z", RegexOptions.IgnoreCase);
        static readonly Regex HealthRequestPattern = new Regex(
            @"^HEALTH(?: (IME|Defender|Compliance|Applications|Disk|BitLocker|PendingReboot|Updates|Service|Custom)(?: ([A-Za-z0-9+/]{2,400}={0,2}))?)?\z",
            RegexOptions.CultureInvariant);

        // APPRETRY <app id>: retry of one Intune app (Win32 app of the Intune Management Extension). The client sends nothing but an
        // ID in the form of a GUID. The service accepts it only when its own reading of the IME cache lists the app as not installed,
        // and hands the ID it read itself to the fixed repair script (environment variable, never a path or an argument).
        const string AppRetryScript = "SelfX_Apps_RetryInstall.ps1";
        const string AppIdVariable = "SELFX_APP_ID";
        static readonly Regex AppRetryRequestPattern = new Regex(
            @"^APPRETRY ([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})\z", RegexOptions.CultureInvariant);
        static readonly Regex AppIdPattern = new Regex(@"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z", RegexOptions.CultureInvariant);
        // A key of the IME cache that stands for an app: <app id> or <app id>_<revision> (HealthStatus.ps1 reads the same form).
        static readonly Regex AppKeyPattern = new Regex(
            @"^([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})(?:_[0-9]{1,9})?\z", RegexOptions.CultureInvariant);
        const string Win32AppsKeyPath = @"SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps";
        // Bounds of one reading of the IME cache: keys visited, depth below Win32Apps (user key, app key, older layouts below it),
        // length of one EnforcementStateMessage, apps remembered for event 4014.
        const int MaxAppKeysRead = 2000;
        const int MaxAppKeyDepth = 4;
        const int MaxAppStateLength = 8192;
        const int MaxAppsTracked = 200;
        // Tests only (Test-ServicePipe.ps1 sets it through reflection on a test instance): a key below HKCU read instead of the IME
        // cache. No request, file or environment variable reaches this field; in the service it is always null.
        string win32AppsKeyForTest;
        // Last state per app ID seen by this service process, for event 4014 (change to failed).
        readonly Dictionary<string, int> appStates = new Dictionary<string, int>(StringComparer.Ordinal);
        readonly object appStateLock = new object();

        /// <summary>One entry of the IME cache: app ID (lower case), EnforcementState and ErrorCode of its EnforcementStateMessage.</summary>
        sealed class AppState { public string Id; public int State; public long ErrorCode; }

        // installRoot is the code folder (App on a device), configRoot the configuration folder (Config next to App).
        readonly string installRoot;
        readonly string configRoot;
        readonly string scriptsRoot;
        readonly string catalogPath;
        readonly string logDirectory;
        readonly string cacheFile;
        // Inventory file for a log collector (Health_Config.xml, element Inventory; default off): one JSON line per full health run.
        readonly string inventoryFile;
        readonly object inventoryLock = new object();
        const int InventorySchemaVersion = 1;
        const int DefaultInventoryMaxKB = 1024;
        const int MinInventoryMaxKB = 64;
        const int MaxInventoryMaxKB = 10240;
        const int MaxInventoryApps = 20;
        // The check types of HealthStatus.ps1 in the fixed order of the schema (Service and Custom can have several rows).
        static readonly string[] InventoryTypes = { "IME", "Defender", "Compliance", "Applications", "Disk", "BitLocker", "PendingReboot", "Updates", "Service", "Custom" };
        static readonly Regex InventoryAppCodePattern = new Regex(@"^0x[0-9A-F]{8}\z", RegexOptions.CultureInvariant);
        readonly string pipeName;
        readonly object logLock = new object();
        readonly SemaphoreSlim runLock = new SemaphoreSlim(1, 1);
        // Positive results of the signature check (trust mode Signature), see SignatureCache.
        readonly SignatureCache signatureCache = new SignatureCache();
        // Job object of the PowerShell children (N6); created in StartListening, ended in StopListening.
        volatile ChildJob childJob;
        // Serializes all health runs, because each of them writes the status cache.
        readonly SemaphoreSlim healthLock = new SemaphoreSlim(1, 1);
        readonly ManualResetEvent stopEvent = new ManualResetEvent(false);
        volatile bool stopping;
        // Defense in depth: ProgramData\SelfX is checked when the service starts and before the daily housekeeping.
        // While it is not safe (link, or an owner other than SYSTEM, administrators, TrustedInstaller or the service account)
        // nothing is written there and no status cache is read or produced.
        volatile bool dataFolderSafe = true;
        static readonly string[] TrustedOwnerSids = { "S-1-5-18", "S-1-5-32-544", "S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464" };
        // The first pipe instance is created with FirstPipeInstance: when another process already owns the pipe
        // name, the service does not join it but logs the problem and retries.
        bool firstPipeInstanceCreated;
        int pipeInUseFailures;
        // Windows event log: only when running under the Service Control Manager, fixed texts, rate limited per
        // event ID (the event log can be read by every user, so no request text and no user names go there).
        // Own classic log "SelfX" (Applications and Services Logs), source SelfXService; Install.ps1 creates both and moves
        // the source of older versions out of the Application log. Every entry has its fields as separate insertion strings
        // (EventInstance): field 1 is a fixed English text, the other fields follow in a fixed order (docs\Installation.md).
        const string EventLogName = "SelfX";
        const string EventSourceName = "SelfXService";
        bool securityEventsEnabled;
        EventLog eventLog;
        bool eventLogWriteFailed;
        readonly object eventLock = new object();
        readonly Dictionary<int, EventWindow> eventWindows = new Dictionary<int, EventWindow>();
        // Security events (4001-4008): at most 10 per event ID in 10 minutes. Operational events (4010-4014): at most 20 per
        // event ID and minute, so a busy device (several users, terminal server) does not lose them after a few actions.
        const int MaxSecurityEventsPerWindow = 10;
        static readonly TimeSpan SecurityEventWindow = TimeSpan.FromMinutes(10);
        const int MaxOperationalEventsPerWindow = 20;
        static readonly TimeSpan OperationalEventWindow = TimeSpan.FromMinutes(1);
        // Length limits of one insertion string: the message (field 1) and every other field.
        const int MaxEventMessageLength = 800;
        const int MaxEventFieldLength = 256;
        // Tests: when set, entries are collected here instead of the event log (also outside the Service Control Manager),
        // and eventClockForTest replaces the clock of the rate limit.
        List<object[]> eventsForTest;
        DateTime? eventClockForTest;
        const int EventPipeInUse = 4001;
        const int EventRejected = 4002;
        const int EventPowerShellUnprotected = 4003;
        const int EventDataFolderUnsafe = 4004;
        const int EventFilesChanged = 4005;
        const int EventTrustAnchor = 4006;
        const int EventSignature = 4007;
        // Mode TerminalServer: a request for an action that is not classified TerminalServer Show was refused.
        // (Event 4009, "session host but Environment_Mode Client", is no longer written: the mode comes from Windows.)
        const int EventTerminalServerRefused = 4008;
        // Operational events (4009 stays unused). A System action (RUN, also a remediation) started, ended with exit code 0, or
        // failed (other exit code, timeout, start error); a health check row changed to Error.
        const int EventActionStarted = 4010;
        const int EventActionSucceeded = 4011;
        const int EventActionFailed = 4012;
        const int EventHealthError = 4013;
        // An Intune app changed to failed (EnforcementState 5000-5999) in the own reading of the IME cache after a health run.
        const int EventAppInstallFailed = 4014;
        // Tool_Config.xml: EventLog_CallerSid = True adds the SID of the requesting user to 4010-4012; anything else = no SID.
        const string EventCallerSidSetting = "EventLog_CallerSid";
        const string EventNoValue = "-";
        // Answer to HEALTH and STATUS when the device status is not available to the caller (mode TerminalServer).
        const string HealthUnavailableResponse = "UNAVAILABLE TerminalServer";
        const int EventSuppressed = 4099;
        sealed class EventWindow { public DateTime Start = DateTime.MinValue; public int Count; public int Suppressed; }
        // Last status per health row (Id + name) seen by this service process, for event 4013 (change to Error).
        readonly Dictionary<string, string> healthRowStatus = new Dictionary<string, string>(StringComparer.Ordinal);
        readonly object healthRowLock = new object();
        const int MaxHealthRowsTracked = 200;
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
            // The entries go to the own log SelfX (WriteEventRecord); AutoLog would write to the Application log with the same source.
            AutoLog = false;

            installRoot = AppContext.BaseDirectory.TrimEnd('\\');
            configRoot = GetConfigRoot(installRoot);
            scriptsRoot = Path.Combine(installRoot, "Scripts_to_run");
            catalogPath = GetConfigFilePath("Issues_List.xml");
            this.pipeName = pipeName;
            this.logDirectory = logDirectory;
            // The cache folder is a sibling of the log folder (default ProgramData\SelfX\Cache).
            string dataRoot = Path.GetDirectoryName(logDirectory.TrimEnd('\\'));
            cacheFile = Path.Combine(Path.Combine(string.IsNullOrEmpty(dataRoot) ? logDirectory : dataRoot, "Cache"), "Health.json");
            inventoryFile = Path.Combine(Path.Combine(string.IsNullOrEmpty(dataRoot) ? logDirectory : dataRoot, "Inventory"), "SelfX.Inventory.json");
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
            childJob = ChildJob.Create();
            if (childJob == null)
            {
                Log("Warning: the job object for the action processes could not be created (error " + Marshal.GetLastWin32Error() + "); running actions will not end with the service.");
            }
            listener = new Thread(ListenLoop);
            listener.IsBackground = true;
            listener.Name = "SelfXPipeListener";
            listener.Start();
            background = new Thread(BackgroundLoop);
            background.IsBackground = true;
            background.Name = "SelfXBackgroundHealth";
            background.Start();
            Log("Service started. Version " + Version + ", pipe '" + pipeName + "', code '" + installRoot + "', configuration '" + configRoot + "'.");
            LogEnvironmentMode();
        }

        /// <summary>
        /// Wake the blocked listener and wait briefly for it to stop accepting connections.
        /// </summary>
        public void StopListening()
        {
            stopping = true;
            stopEvent.Set();
            // N6: end every running PowerShell child with its descendants (RUN, HEALTH and background), so that an update or
            // an uninstall does not find a SYSTEM process that still holds files. New starts are refused (stopping).
            ChildJob job = childJob;
            childJob = null;
            if (job != null)
            {
                job.Terminate();
            }
            // A running background collection is only reading; stop it with the service (fallback without a job).
            int pid = backgroundProcessId;
            if (pid != 0)
            {
                KillProcessTree(pid);
            }
            // The thread of an ended action releases the run slot right after the process ended.
            if (runLock.Wait(3000))
            {
                runLock.Release();
            }
            else
            {
                Log("An action was still running 3 s after the service stop was requested.");
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

                    string response;
                    try
                    {
                        response = ProcessRequest(request, user, callerSid, callerIsAdmin, callerSession);
                    }
                    catch (Exception ex)
                    {
                        // N5: the client gets a fixed answer without details (instead of waiting for a timeout);
                        // the log has the type and the cleaned message, never the request content.
                        Log("Request error (" + CleanLogText(user) + "): " + ex.GetType().Name + ": " + CleanLogText(ex.Message));
                        response = "ERROR Internal error";
                    }
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
                // Mode TerminalServer: the status describes the server, not the place of work of the user (TerminalServer_Health).
                // No log line here: the status icon of every signed-in user asks regularly.
                if (!IsHealthAllowed(callerIsAdmin)) return HealthUnavailableResponse;
                return GetStatusResponse();
            }
            Match healthMatch = HealthRequestPattern.Match(request);
            if (healthMatch.Success)
            {
                // Mode TerminalServer: checks run only as TerminalServer_Health allows (before anything is started).
                if (!IsHealthAllowed(callerIsAdmin))
                {
                    LogRejected("HEALTH request from " + user + " refused: the device status is not available on a terminal server (TerminalServer_Health).");
                    return HealthUnavailableResponse;
                }
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
                // A full check that the cache already holds from the last minute is not run again.
                if (filter.Length == 0)
                {
                    string cached = ReadFreshHealthCache(TimeSpan.FromSeconds(HealthCacheReuseSeconds));
                    if (cached != null) return "HEALTH " + Convert.ToBase64String(Encoding.UTF8.GetBytes(cached));
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
            Match appMatch = AppRetryRequestPattern.Match(request);
            if (appMatch.Success)
            {
                return ProcessAppRetry(appMatch.Groups[1].Value.ToLowerInvariant(), user, callerSid, callerIsAdmin, callerSession);
            }
            if (request.StartsWith("APPRETRY", StringComparison.Ordinal))
            {
                // The request text is not logged: it is not a GUID and may carry anything.
                LogRejected("Rejected invalid app retry request from " + user + ".");
                return "ERROR Invalid app";
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
            bool hideOnTerminalServer;
            // Elevation is granted only to System entries, never arbitrary client-supplied scripts.
            if (!TryGetSystemAction(scriptName, out timeoutSeconds, out blockOtherSessions, out hideOnTerminalServer))
            {
                LogRejected("Rejected request from " + user + ": '" + scriptName + "' is not a System action in the catalog.");
                return "ERROR Action is not allowed";
            }

            // Mode TerminalServer (from Windows, IsTerminalServer): an action that is not classified TerminalServer Show is refused for
            // every caller, also for elevated administrators. The window hides these actions, but the window is no security boundary.
            // No file, setting or request can switch the mode; version data that cannot be read count as TerminalServer (fail closed).
            if (hideOnTerminalServer && IsTerminalServer())
            {
                LogRejected("Request from " + user + " for '" + scriptName + "' refused: the action is not available on a terminal server (mode TerminalServer).",
                    EventTerminalServerRefused, "A SelfX action that is not available on a terminal server or session host (mode TerminalServer) was requested and refused. Details are in SelfXService.log in the protected log folder.");
                return "ERROR TerminalServer";
            }

            // The script of the project (App\Scripts_to_run) or an own script of the company that SelfX.Config.json lists with its
            // current SHA256 (Config\Scripts_to_run); nothing else, also not with Service_FileCheck=Audit.
            string scriptPath = ResolveScriptPath(installRoot, configRoot, "Scripts_to_run", scriptName);
            if (scriptPath == null)
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

            // A repair that Health_Config.xml offers only while its check is not OK (When="NotOK"): a normal user may start it only
            // while the status cache says so. The window hides the button otherwise, but the window is no security boundary.
            if (!callerIsAdmin && !IsRemediationNeeded(scriptName))
            {
                LogRejected("Request from " + user + " for '" + scriptName + "' refused: the status cache does not list its check as not OK (When=NotOK).");
                return "ERROR NotNeeded";
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
        /// APPRETRY: retry of one Intune app through the fixed repair AppRetryScript. The same checks as RUN (whitelist through
        /// Health_Config.xml or the catalog, TerminalServer before anything else, other sessions, pause per user, one action at a time);
        /// in addition the ID must be listed as not installed in the own reading of the IME cache, read right before the start.
        /// The script gets the ID of that reading in SELFX_APP_ID; it reads the cache again and changes only the entries of this app.
        /// </summary>
        string ProcessAppRetry(string requestedId, string user, string callerSid, bool callerIsAdmin, long callerSession)
        {
            int timeoutSeconds;
            bool blockOtherSessions;
            bool hideOnTerminalServer;
            if (!TryGetSystemAction(AppRetryScript, out timeoutSeconds, out blockOtherSessions, out hideOnTerminalServer))
            {
                LogRejected("Rejected app retry from " + user + ": '" + AppRetryScript + "' is not a System action or remediation.");
                return "ERROR Action is not allowed";
            }
            // Intune installs no apps on Windows Server; the repair is classified Hide there and refused for every caller.
            if (hideOnTerminalServer && IsTerminalServer())
            {
                LogRejected("App retry from " + user + " refused: the action is not available on a terminal server (mode TerminalServer).",
                    EventTerminalServerRefused, "A SelfX action that is not available on a terminal server or session host (mode TerminalServer) was requested and refused. Details are in SelfXService.log in the protected log folder.");
                return "ERROR TerminalServer";
            }
            string scriptPath = ResolveScriptPath(installRoot, configRoot, "Scripts_to_run", AppRetryScript);
            if (scriptPath == null)
            {
                LogRejected("Rejected app retry from " + user + ": script '" + AppRetryScript + "' not found.");
                return "ERROR Script not found";
            }
            // The repair restarts the Intune Management Extension (OtherSessions = Block in Health_Config.xml).
            if (blockOtherSessions && !callerIsAdmin)
            {
                int others = CountOtherUserSessions(callerSid, callerSession);
                if (others != 0)
                {
                    LogRejected("App retry from " + user + " refused: " + (others < 0 ? "sessions could not be checked" : "another user is signed in") + ".");
                    return "ERROR OtherSessions";
                }
            }
            // Same pause key as RUN of this script: a user cannot restart the IME every few seconds through the other request.
            string runKey = "RUN|" + LimitKey(user, callerSid) + "|" + AppRetryScript.ToLowerInvariant();
            if (InCooldown(runKey))
            {
                LogRejected("Rate limit: app retry from " + user + " refused.");
                return "BUSY";
            }
            // Only an ID that the service itself reads from the IME cache reaches the script.
            string appId = FindRetryableApp(requestedId);
            if (appId == null)
            {
                LogRejected("App retry from " + user + " refused: app " + requestedId + " is not in the IME cache or does not need a retry.");
                return "ERROR Unknown app";
            }
            if (!runLock.Wait(0))
            {
                Log("Busy: app retry from " + user + " refused.");
                return "BUSY";
            }
            try
            {
                Log("App retry for " + appId + " requested by " + user + ".");
                return RunScript(scriptPath, AppRetryScript, timeoutSeconds, user, false, "", callerSid, false, callerIsAdmin, appId);
            }
            finally
            {
                runLock.Release();
                StartCooldown(runKey, RunCooldownSeconds);
            }
        }

        /// <summary>
        /// True for a state that a retry can help: readable (above 0), not installed (1000) and not "not applicable" (3000-3999).
        /// The script decides with its own reading whether the app failed or its download stalled; anything else changes nothing there.
        /// </summary>
        static bool IsRetryableAppState(int state)
        {
            return state > 0 && state != 1000 && !(state >= 3000 && state < 4000);
        }

        /// <summary>Failed installation in the IME cache (EnforcementState 5000-5999).</summary>
        static bool IsFailedAppState(int state)
        {
            return state >= 5000 && state < 6000;
        }

        /// <summary>
        /// The ID as read from the IME cache when the app is listed there with a state that a retry can help, otherwise null.
        /// A cache that cannot be read gives null (fail closed).
        /// </summary>
        string FindRetryableApp(string requestedId)
        {
            if (requestedId == null || !AppIdPattern.IsMatch(requestedId)) return null;
            List<AppState> apps;
            try { apps = ReadAppStates(); }
            catch (Exception ex)
            {
                Log("The IME app cache could not be read (" + ex.GetType().Name + ").");
                return null;
            }
            foreach (AppState app in apps)
            {
                if (string.Equals(app.Id, requestedId, StringComparison.Ordinal) && IsRetryableAppState(app.State)) return app.Id;
            }
            return null;
        }

        /// <summary>
        /// Reads the IME cache Win32Apps\&lt;user&gt;\&lt;app id&gt;[_&lt;revision&gt;] (64-bit view; in tests a key below HKCU), only reading.
        /// An app is the nearest key at or above the entry whose name has the form of an app key and that lies below the user key;
        /// the user key itself is never taken as an app. At most MaxAppKeysRead keys and MaxAppKeyDepth levels are visited.
        /// </summary>
        List<AppState> ReadAppStates()
        {
            List<AppState> apps = new List<AppState>();
            RegistryKey hive = null;
            RegistryKey root = null;
            try
            {
                if (win32AppsKeyForTest != null) root = Registry.CurrentUser.OpenSubKey(win32AppsKeyForTest, false);
                else
                {
                    hive = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64);
                    root = hive.OpenSubKey(Win32AppsKeyPath, false);
                }
                if (root == null) return apps;
                int budget = MaxAppKeysRead;
                ReadAppStates(root, 0, null, apps, ref budget);
            }
            finally
            {
                if (root != null) root.Dispose();
                if (hive != null) hive.Dispose();
            }
            return apps;
        }

        static void ReadAppStates(RegistryKey key, int depth, string appId, List<AppState> apps, ref int budget)
        {
            foreach (string name in key.GetSubKeyNames())
            {
                if (budget <= 0) return;
                budget--;
                using (RegistryKey child = key.OpenSubKey(name, false))
                {
                    if (child == null) continue;
                    string id = appId;
                    // depth 0 = the user key (object ID of the user or 00000000-...): never an app.
                    if (depth >= 1)
                    {
                        Match match = AppKeyPattern.Match(name);
                        if (match.Success) id = match.Groups[1].Value.ToLowerInvariant();
                    }
                    if (id != null)
                    {
                        AppState state = ReadAppState(child, id);
                        if (state != null) apps.Add(state);
                    }
                    if (depth + 1 < MaxAppKeyDepth) ReadAppStates(child, depth + 1, id, apps, ref budget);
                }
            }
        }

        /// <summary>EnforcementState and ErrorCode of the value EnforcementStateMessage (JSON of the IME), or null without a usable value.</summary>
        static AppState ReadAppState(RegistryKey key, string appId)
        {
            string text = key.GetValue("EnforcementStateMessage", null, RegistryValueOptions.DoNotExpandEnvironmentNames) as string;
            if (string.IsNullOrEmpty(text) || text.Length > MaxAppStateLength) return null;
            try
            {
                using (JsonDocument document = JsonDocument.Parse(text, new JsonDocumentOptions { MaxDepth = 4 }))
                {
                    JsonElement top = document.RootElement;
                    if (top.ValueKind != JsonValueKind.Object) return null;
                    JsonElement value;
                    int state = 0;
                    if (top.TryGetProperty("EnforcementState", out value) && value.ValueKind == JsonValueKind.Number) value.TryGetInt32(out state);
                    long code = 0;
                    if (top.TryGetProperty("ErrorCode", out value) && value.ValueKind == JsonValueKind.Number) value.TryGetInt64(out code);
                    return new AppState { Id = appId, State = state, ErrorCode = code };
                }
            }
            catch (JsonException) { return null; }
        }

        /// <summary>An error code of the IME as 0x and eight hex digits (signed 32-bit values as HRESULT), or null for 0 or a value out of range.</summary>
        static string FormatAppErrorCode(long code)
        {
            if (code == 0 || code < int.MinValue || code > uint.MaxValue) return null;
            uint value = unchecked((uint)code);
            return "0x" + value.ToString("X8", CultureInfo.InvariantCulture);
        }

        /// <summary>
        /// The apps that changed to failed since the last reading of this service process, as {app ID, error code, previous state}.
        /// Per app ID a failed entry wins over the others (an app can have entries of several users or revisions). An app seen for the
        /// first time as failed counts as a change (previous state "-"), so the state after a restart is reported once. An entry with an
        /// ID that is not a GUID or without a valid error code is not reported. At most MaxAppsTracked apps are remembered.
        /// </summary>
        static List<string[]> FindAppFailureChanges(List<AppState> apps, Dictionary<string, int> lastState)
        {
            List<string[]> changes = new List<string[]>();
            Dictionary<string, AppState> current = new Dictionary<string, AppState>(StringComparer.Ordinal);
            List<string> order = new List<string>();
            foreach (AppState app in apps)
            {
                if (app == null || app.Id == null || !AppIdPattern.IsMatch(app.Id)) continue;
                AppState known;
                if (!current.TryGetValue(app.Id, out known)) { current[app.Id] = app; order.Add(app.Id); }
                else if (IsFailedAppState(app.State) && !IsFailedAppState(known.State)) current[app.Id] = app;
            }
            foreach (string id in order)
            {
                AppState app = current[id];
                int previous;
                bool seen = lastState.TryGetValue(id, out previous);
                if (!seen && lastState.Count >= MaxAppsTracked) continue;
                lastState[id] = app.State;
                if (!IsFailedAppState(app.State) || (seen && IsFailedAppState(previous))) continue;
                string code = FormatAppErrorCode(app.ErrorCode);
                if (code == null) continue;
                changes.Add(new string[] { id, code, seen ? previous.ToString(CultureInfo.InvariantCulture) : EventNoValue });
            }
            return changes;
        }

        /// <summary>
        /// Writes event 4014 (fields: message, app ID, error code, previous state) for every app that changed to failed. The values come
        /// only from the own reading of the IME cache: no app name, no detail text, nothing from a client.
        /// </summary>
        void ReportAppFailures()
        {
            List<AppState> apps;
            try { apps = ReadAppStates(); }
            catch (Exception ex)
            {
                Log("The IME app cache could not be read for the event log (" + ex.GetType().Name + ").");
                return;
            }
            List<string[]> changes;
            lock (appStateLock) { changes = FindAppFailureChanges(apps, appStates); }
            foreach (string[] change in changes)
            {
                WriteEventRecord(EventAppInstallFailed, EventLogEntryType.Warning, new string[] {
                    "An Intune app installation failed (local cache of the Intune Management Extension).", change[0], change[1], change[2] });
            }
        }

        /// <summary>Who gets the device status (HEALTH, STATUS) and whether the background checks run.</summary>
        enum HealthAccess { Everyone, AdminOnly, Off }

        /// <summary>
        /// Access to the device status from the mode and TerminalServer_Health of Tool_Config.xml (null = the file cannot be read).
        /// Client: everyone. TerminalServer: AdminOnly only for exactly that value (case is ignored), otherwise Off (default, empty,
        /// any other value, unreadable file): on a terminal server the status describes the server, and every user would see its
        /// security state.
        /// </summary>
        static HealthAccess GetHealthAccess(bool terminalServer, string terminalServerHealth)
        {
            if (!terminalServer) return HealthAccess.Everyone;
            if (terminalServerHealth != null && string.Equals(terminalServerHealth.Trim(), "AdminOnly", StringComparison.OrdinalIgnoreCase)) return HealthAccess.AdminOnly;
            return HealthAccess.Off;
        }

        /// <summary>TerminalServer_Health: empty (element missing), Off or AdminOnly; case is ignored.</summary>
        static bool IsValidTerminalServerHealth(string value)
        {
            string text = (value ?? "").Trim();
            return text.Length == 0 || string.Equals(text, "Off", StringComparison.OrdinalIgnoreCase) || string.Equals(text, "AdminOnly", StringComparison.OrdinalIgnoreCase);
        }

        HealthAccess ReadHealthAccess()
        {
            return GetHealthAccess(IsTerminalServer(), ReadToolConfigValue("TerminalServer_Health"));
        }

        /// <summary>True when the caller gets HEALTH and STATUS; AdminOnly needs an elevated administrator (the same check as for RUN).</summary>
        bool IsHealthAllowed(bool callerIsAdmin)
        {
            HealthAccess access = ReadHealthAccess();
            return access == HealthAccess.Everyone || (access == HealthAccess.AdminOnly && callerIsAdmin);
        }

        /// <summary>
        /// True when the product type and suite mask describe a terminal server or session host for several users: every product type
        /// other than workstation (Windows Server reports 3, a domain controller 2, Windows Enterprise multi-session 3 as well), and a
        /// workstation in application server mode (VER_SUITE_TERMINAL without VER_SUITE_SINGLEUSERTS).
        /// </summary>
        static bool IsSessionHostProduct(byte productType, ushort suiteMask)
        {
            if (productType != VerNtWorkstation) return true;
            return (suiteMask & VerSuiteTerminal) != 0 && (suiteMask & VerSuiteSingleUserTs) == 0;
        }

        /// <summary>Session host check of the running Windows; null when the version data cannot be read.</summary>
        static bool? IsSessionHost()
        {
            try
            {
                OsVersionInfoEx info = new OsVersionInfoEx();
                info.OSVersionInfoSize = Marshal.SizeOf(typeof(OsVersionInfoEx));
                if (RtlGetVersion(ref info) != 0) return null;
                return IsSessionHostProduct(info.ProductType, info.SuiteMask);
            }
            catch { return null; }
        }

        // Tests only (Test-ServicePipe.ps1 sets it through reflection on a test instance): the mode without asking Windows. No request,
        // file, registry value or environment variable reaches this field; in the service it is always null.
        bool? terminalServerForTest;

        /// <summary>
        /// The mode of SelfX, from Windows and never from a setting: Client on Windows 11 (product type workstation), TerminalServer on
        /// Windows Server and every other session host. Version data that cannot be read count as TerminalServer (fail closed).
        /// </summary>
        bool IsTerminalServer()
        {
            if (terminalServerForTest.HasValue) return terminalServerForTest.Value;
            bool? host = IsSessionHost();
            return !host.HasValue || host.Value;
        }

        /// <summary>
        /// Logs the mode at the start (it comes from Windows) and TerminalServer_Health. An Environment_Mode that is still in
        /// Tool_Config.xml (configuration of an earlier build) is ignored and named in the log.
        /// </summary>
        void LogEnvironmentMode()
        {
            try
            {
                bool? host = IsSessionHost();
                if (host == null) Log("Mode: the product type of Windows cannot be read; requests are handled as on a terminal server (TerminalServer).");
                else Log("Mode: " + (host.Value ? "TerminalServer (Windows Server or another session host)" : "Client (Windows 11)") + ", from the product type of Windows.");
                if (IsTerminalServer())
                {
                    string health = ReadToolConfigValue("TerminalServer_Health");
                    if (health != null && !IsValidTerminalServerHealth(health)) Log("TerminalServer_Health in Tool_Config.xml is not Off or AdminOnly; Off is used.");
                    Log("TerminalServer_Health: " + (ReadHealthAccess() == HealthAccess.AdminOnly ? "AdminOnly" : "Off") + ".");
                }
                string old = ReadToolConfigValue("Environment_Mode");
                if (!string.IsNullOrEmpty(old)) Log("Environment_Mode in Tool_Config.xml is not used any more and is ignored: the mode comes from Windows.");
            }
            catch (Exception e) { Log("Mode check failed: " + e.Message); }
        }

        /// <summary>
        /// Check the installed System-action whitelist and resolve a bounded execution timeout.
        /// </summary>
        bool TryGetSystemAction(string scriptName, out int timeoutSeconds, out bool blockOtherSessions, out bool hideOnTerminalServer)
        {
            timeoutSeconds = DefaultTimeoutSeconds;
            blockOtherSessions = false;
            // Not classified = Hide (fail closed): only an explicit TerminalServer Show keeps an action in the mode TerminalServer.
            hideOnTerminalServer = true;
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
                string healthConfig = GetConfigFilePath("Health_Config.xml");
                if (!File.Exists(healthConfig)) return false;
                XmlDocument health = new XmlDocument();
                health.XmlResolver = null;
                using (XmlReader reader = XmlReader.Create(healthConfig, settings)) { health.Load(reader); }
                XmlNode remediation = health.SelectSingleNode("/HealthConfig/Remediations/Remediation[@Script='" + scriptName + "']");
                if (remediation == null) return false;
                XmlAttribute remediationSessions = remediation.Attributes["OtherSessions"];
                blockOtherSessions = remediationSessions != null && remediationSessions.Value.Trim() == "Block";
                XmlAttribute remediationTerminalServer = remediation.Attributes["TerminalServer"];
                hideOnTerminalServer = remediationTerminalServer == null || remediationTerminalServer.Value.Trim() != "Show";
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
            // Hide when any System entry of the script is not classified Show by exactly one element (one script, one classification;
            // Test-Catalog.ps1 checks it). A second TerminalServer element must not turn a Hide into the Show of the first one.
            hideOnTerminalServer = catalog.SelectSingleNode(
                "//Action[normalize-space(Context)='System' and normalize-space(Script)='" + scriptName + "' and not(count(TerminalServer)=1 and normalize-space(TerminalServer)='Show')]") != null;

            XmlNode timeoutNode = action.SelectSingleNode("TimeoutSeconds");
            int configured;
            if (timeoutNode != null && int.TryParse(timeoutNode.InnerText.Trim(), out configured) && configured > 0)
            {
                timeoutSeconds = Math.Min(configured, MaxTimeoutSeconds);
            }
            return true;
        }

        /// <summary>
        /// False only for a script that no System action of the catalog lists and whose remediations in Health_Config.xml all say
        /// When="NotOK", while the status cache (written by the service, at most RemediationCacheMaxAgeMinutes old) does not list one
        /// of their rows (Id, and Name when the remediation names one) as not OK. A missing, old or unreadable cache counts as "not
        /// needed" (fail closed): the window runs a check before it offers the repair, and that check writes the cache.
        /// </summary>
        bool IsRemediationNeeded(string scriptName)
        {
            try
            {
                XmlReaderSettings settings = new XmlReaderSettings();
                settings.DtdProcessing = DtdProcessing.Prohibit;
                settings.XmlResolver = null;
                XmlDocument catalog = new XmlDocument();
                catalog.XmlResolver = null;
                using (XmlReader reader = XmlReader.Create(catalogPath, settings)) { catalog.Load(reader); }
                // scriptName is validated by ScriptNamePattern, so it contains no quotes.
                if (catalog.SelectSingleNode("//Action[normalize-space(Context)='System' and normalize-space(Script)='" + scriptName + "']") != null) return true;
                string healthConfig = GetConfigFilePath("Health_Config.xml");
                if (!File.Exists(healthConfig)) return false;
                XmlDocument health = new XmlDocument();
                health.XmlResolver = null;
                using (XmlReader reader = XmlReader.Create(healthConfig, settings)) { health.Load(reader); }
                XmlNodeList remediations = health.SelectNodes("/HealthConfig/Remediations/Remediation[@Script='" + scriptName + "']");
                if (remediations.Count == 0) return false;
                List<string> ids = new List<string>();
                List<string> names = new List<string>();
                foreach (XmlNode node in remediations)
                {
                    XmlElement remediation = node as XmlElement;
                    if (remediation == null) return false;
                    if (remediation.GetAttribute("When").Trim() != "NotOK") return true;
                    ids.Add(remediation.GetAttribute("Id").Trim());
                    names.Add(remediation.HasAttribute("Name") ? remediation.GetAttribute("Name") : null);
                }
                string cached = ReadFreshHealthCache(TimeSpan.FromMinutes(RemediationCacheMaxAgeMinutes));
                return cached != null && AnyHealthRowNotOk(cached, ids.ToArray(), names.ToArray());
            }
            catch (Exception e)
            {
                Log("Repair condition not readable (" + e.GetType().Name + "); the repair is refused for normal users.");
                return false;
            }
        }

        /// <summary>
        /// True when the health JSON (array of rows with Id, Name, Status) has a row whose Id is one of ids (and whose Name is the
        /// name at the same position, when that is not null) and whose Status is not OK. Invalid JSON = false (tested by
        /// Test-ServicePipe.ps1).
        /// </summary>
        static bool AnyHealthRowNotOk(string json, string[] ids, string[] names)
        {
            if (string.IsNullOrEmpty(json) || ids == null || names == null || ids.Length != names.Length) return false;
            try
            {
                using (JsonDocument document = JsonDocument.Parse(json, new JsonDocumentOptions { MaxDepth = 8 }))
                {
                    if (document.RootElement.ValueKind != JsonValueKind.Array) return false;
                    foreach (JsonElement row in document.RootElement.EnumerateArray())
                    {
                        if (row.ValueKind != JsonValueKind.Object) continue;
                        string status = JsonText(row, "Status");
                        if (status.Length == 0 || status == "OK") continue;
                        string id = JsonText(row, "Id");
                        string name = JsonText(row, "Name");
                        for (int i = 0; i < ids.Length; i++)
                        {
                            if (!string.Equals(ids[i], id, StringComparison.Ordinal)) continue;
                            if (names[i] != null && !string.Equals(names[i], name, StringComparison.Ordinal)) continue;
                            return true;
                        }
                    }
                }
            }
            catch (JsonException) { return false; }
            return false;
        }

        /// <summary>
        /// The text of the status cache when it was written at most maxAge ago (and not in the future), null otherwise: the data folder
        /// must have passed the safety check of the start, and the size limit of STATUS applies.
        /// </summary>
        string ReadFreshHealthCache(TimeSpan maxAge)
        {
            if (!dataFolderSafe) return null;
            for (int attempt = 0; attempt < 3; attempt++)
            {
                try
                {
                    if (!File.Exists(cacheFile)) return null;
                    TimeSpan age = DateTime.UtcNow - File.GetLastWriteTimeUtc(cacheFile);
                    if (age < TimeSpan.Zero || age > maxAge) return null;
                    byte[] bytes = File.ReadAllBytes(cacheFile);
                    if (bytes.Length == 0 || bytes.Length > MaxCacheLength) return null;
                    return new UTF8Encoding(false, true).GetString(bytes);
                }
                catch (IOException) { Thread.Sleep(100); }
                catch (ArgumentException) { return null; }
            }
            return null;
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

        // The two lists written at package build (tools\SelfXPackage.Common.ps1): code (same for every company) and configuration.
        const string CodeListName = "SelfX.Code.json";
        const string ConfigListName = "SelfX.Config.json";
        static readonly string[] FileListNames = { CodeListName, ConfigListName };
        static readonly string[] ConfigFileNames = { "Health_Config.xml", "Issues_List.xml", "Network_Test_Config.xml", "Ticket_Config.xml", "Tool_Config.xml" };
        static readonly Regex ConfigScriptPattern = new Regex(@"^(Scripts_to_run|HealthChecks)/[A-Za-z0-9._-]+\.ps1\z", RegexOptions.CultureInvariant);
        static readonly Regex ConfigLanguagePattern = new Regex(@"^Languages/[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8}){0,2}\.xml\z", RegexOptions.CultureInvariant);
        static readonly Regex ConfigTextPattern = new Regex(@"^Texts/[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8}){0,2}\.xml\z", RegexOptions.CultureInvariant);
        const long MaxFileListBytes = 1048576;
        const int MaxFileProblems = 20;
        // Same rule as the generator (tools\SelfXPackage.Common.ps1): plain relative names with forward slashes.
        static readonly Regex ListedNamePattern = new Regex(@"^[A-Za-z0-9_][A-Za-z0-9_ .()\-]*(/[A-Za-z0-9_][A-Za-z0-9_ .()\-]*)*\z", RegexOptions.CultureInvariant);
        static readonly Regex Sha256Pattern = new Regex(@"^[0-9A-Fa-f]{64}\z", RegexOptions.CultureInvariant);
        // The generator lists every file of the installation (scripts, configuration, images, WinRT and Audio libraries, both
        // programs), so no file of any type may exist in the install folder without an entry in the list (a stray .config,
        // .json, .cmd, .manifest or .dll.config next to a checked program would otherwise go unnoticed). Only the two lists
        // themselves are exempt. A replaced SelfXService.exe skips its own check: this detects accidents (broken update); the protection
        // against an attacker is the folder ACL and App Control.
        // Checked first, so that a long list of other problems cannot hide them: the configuration read by CheckInstalledFiles
        // (Service_FileCheck) and the action catalog.
        static readonly string[] PriorityFiles = { "Tool_Config.xml", "Issues_List.xml" };
        // Last entry of the problem list when the check stopped at MaxFileProblems (the list is then incomplete).
        const string TruncatedProblem = "check stopped: more problems may exist";

        /// <summary>
        /// Placement rule (same as Test-SelfXListPlacement in Install.ps1 and tools\SelfXPackage.Common.ps1): SelfX.Code.json may
        /// hold any file that is not a settings file or below Branding; SelfX.Config.json only settings files, files below Branding,
        /// own scripts in Scripts_to_run or HealthChecks, own language files and text overrides (Texts/&lt;culture&gt;.xml). Nothing
        /// below Texts may be in SelfX.Code.json. Both lists are written by the administrator of the package, but a file that does
        /// not belong in a list is refused, so no program or script of the project can be moved into the list that carries the
        /// company's own files.
        /// </summary>
        static bool IsAllowedInList(string name, string listName)
        {
            bool isConfigFile = name.StartsWith("Branding/", StringComparison.Ordinal) && name.Length > "Branding/".Length;
            bool isText = name.StartsWith("Texts/", StringComparison.Ordinal) && name.Length > "Texts/".Length;
            foreach (string known in ConfigFileNames)
            {
                if (string.Equals(known, name, StringComparison.Ordinal)) isConfigFile = true;
            }
            if (listName == CodeListName) return !(isConfigFile || isText);
            return isConfigFile || ConfigScriptPattern.IsMatch(name) || ConfigLanguagePattern.IsMatch(name) || ConfigTextPattern.IsMatch(name);
        }

        static bool HasDotSegment(string name)
        {
            foreach (string segment in name.Split('/'))
            {
                if (segment == "." || segment == "..") return true;
            }
            return false;
        }

        /// <summary>
        /// The configuration folder: the folder Config next to the code folder when the code folder is named App (installation),
        /// otherwise the code folder itself (flat layout of the repository and of tests). Same rule as Get-SelfXConfigRoot in
        /// SelfXPaths.ps1. Nothing that a user can set (environment, registry, request) takes part in it.
        /// </summary>
        static string GetConfigRoot(string codeRoot)
        {
            string code = Path.GetFullPath(codeRoot).TrimEnd('\\');
            if (string.Equals(Path.GetFileName(code), "App", StringComparison.OrdinalIgnoreCase))
            {
                string parent = Path.GetDirectoryName(code);
                if (!string.IsNullOrEmpty(parent)) return Path.Combine(parent, "Config");
            }
            return code;
        }

        /// <summary>
        /// The only way the service builds the path of a settings file: one of the fixed names in the configuration folder.
        /// Any other name throws (no path from a request or a file can reach this method).
        /// </summary>
        string GetConfigFilePath(string name)
        {
            return GetConfigFilePath(configRoot, name);
        }

        static string GetConfigFilePath(string root, string name)
        {
            foreach (string known in ConfigFileNames)
            {
                if (string.Equals(known, name, StringComparison.Ordinal)) return Path.Combine(root, known);
            }
            throw new ArgumentException("Not a configuration file of SelfX.", "name");
        }

        /// <summary>
        /// Full path of a script named in the catalog or in Health_Config.xml, or null when it may not be started. folder is
        /// Scripts_to_run or HealthChecks, fileName a name checked by ScriptNamePattern. The script of the project (code folder)
        /// wins. An own script of the company (configuration folder, only in the layout App/Config) is used only when neither the
        /// script nor a folder below the configuration folder is a link and SelfX.Config.json lists "folder/fileName" with the
        /// SHA256 the file has now. This does not depend on Service_FileCheck, so an unlisted or changed own script never starts.
        /// Same rule as Resolve-SelfXScriptPath in SelfXPaths.ps1.
        /// </summary>
        static string ResolveScriptPath(string codeRoot, string configRoot, string folder, string fileName)
        {
            if (folder != "Scripts_to_run" && folder != "HealthChecks") return null;
            if (fileName == null || !ScriptNamePattern.IsMatch(fileName) || fileName.Contains("..") || fileName.IndexOfAny(new[] { '\\', '/', ':' }) >= 0) return null;
            string code = Path.GetFullPath(codeRoot).TrimEnd('\\');
            string codeFolder = Path.Combine(code, folder);
            string codePath = Path.GetFullPath(Path.Combine(codeFolder, fileName));
            if (codePath.StartsWith(codeFolder + "\\", StringComparison.OrdinalIgnoreCase) && File.Exists(codePath)) return codePath;

            string config = Path.GetFullPath(configRoot).TrimEnd('\\');
            if (string.Equals(config, code, StringComparison.OrdinalIgnoreCase)) return null;
            string configFolder = Path.Combine(config, folder);
            string configPath = Path.GetFullPath(Path.Combine(configFolder, fileName));
            if (!configPath.StartsWith(configFolder + "\\", StringComparison.OrdinalIgnoreCase) || !File.Exists(configPath)) return null;
            try
            {
                if ((new DirectoryInfo(config).Attributes & FileAttributes.ReparsePoint) != 0 || IsLinkBelow(config, configPath)) return null;
                Dictionary<string, ListedFile> listed = new Dictionary<string, ListedFile>(StringComparer.OrdinalIgnoreCase);
                string problem;
                if (!ReadFileList(config, ConfigListName, listed, out problem)) return null;
                ListedFile entry;
                if (!listed.TryGetValue(folder + "/" + fileName, out entry)) return null;
                return string.Equals(HashFile(configPath), entry.Hash, StringComparison.OrdinalIgnoreCase) ? configPath : null;
            }
            catch (Exception)
            {
                // Fail closed: a list or a file that cannot be read starts nothing.
                return null;
            }
        }

        static string HashFile(string path)
        {
            using (FileStream stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
            using (SHA256 sha = SHA256.Create())
            {
                return BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", "");
            }
        }

        /// <summary>One entry of a file list: the expected SHA256 and the folder the name is relative to.</summary>
        sealed class ListedFile
        {
            public string Hash;
            public string Root;
        }

        /// <summary>
        /// Reads one list (in root) into expected (name -> SHA256 and root, case-insensitive names). A name that is already in
        /// expected (listed twice or in both lists) or that is not allowed in this list is an invalid entry. Returns false and a
        /// problem text when the list is missing, a link, too large or invalid (fail closed).
        /// </summary>
        static bool ReadFileList(string root, string listName, Dictionary<string, ListedFile> expected, out string problem)
        {
            return ReadFileList(root, listName, expected, null, out problem);
        }

        /// <summary>
        /// As above. With pins (trust mode Signature) the list is read through its pinned handle: the bytes are the ones whose
        /// membership in the signed catalog was checked.
        /// </summary>
        static bool ReadFileList(string root, string listName, Dictionary<string, ListedFile> expected, PinnedFiles pins, out string problem)
        {
            problem = null;
            string listPath = Path.Combine(root, listName);
            FileInfo listInfo = new FileInfo(listPath);
            if (!listInfo.Exists) { problem = "file list: " + listName + " missing"; return false; }
            if ((listInfo.Attributes & FileAttributes.ReparsePoint) != 0) { problem = "file list: " + listName + " is a link"; return false; }
            if (listInfo.Length > MaxFileListBytes) { problem = "file list: " + listName + " too large"; return false; }
            byte[] content = pins == null ? File.ReadAllBytes(listPath) : pins.Open(listPath).ReadAll(MaxFileListBytes);
            if (content == null) { problem = "file list: " + listName + " too large"; return false; }
            int count = 0;
            using (JsonDocument document = JsonDocument.Parse(content, new JsonDocumentOptions { MaxDepth = 4 }))
            {
                JsonElement top = document.RootElement;
                JsonElement version, files;
                if (top.ValueKind != JsonValueKind.Object || !top.TryGetProperty("ManifestVersion", out version) ||
                    version.ValueKind != JsonValueKind.Number || version.GetInt32() != 1 ||
                    !top.TryGetProperty("Files", out files) || files.ValueKind != JsonValueKind.Object)
                {
                    problem = "file list: " + listName + " unsupported format";
                    return false;
                }
                foreach (JsonProperty entry in files.EnumerateObject())
                {
                    string hash = entry.Value.ValueKind == JsonValueKind.String ? entry.Value.GetString() : null;
                    if (!ListedNamePattern.IsMatch(entry.Name) || HasDotSegment(entry.Name) ||
                        hash == null || !Sha256Pattern.IsMatch(hash) || expected.ContainsKey(entry.Name) || !IsAllowedInList(entry.Name, listName))
                    {
                        problem = "file list: " + listName + " invalid entry";
                        return false;
                    }
                    expected[entry.Name] = new ListedFile { Hash = hash, Root = root };
                    count++;
                }
            }
            if (count == 0) { problem = "file list: " + listName + " empty"; return false; }
            return true;
        }

        /// <summary>
        /// Flat layout (code and configuration in one folder: repository, tests): see VerifyInstalledLayout.
        /// </summary>
        static bool VerifyInstalledFiles(string root, out List<string> problems)
        {
            return VerifyInstalledLayout(root, root, out problems);
        }

        /// <summary>
        /// Compare the installed files with SelfX.Code.json (in the code folder, names relative to it) and SelfX.Config.json (in the
        /// configuration folder, names relative to it), written at package build and copied by Install.ps1. Every listed file must
        /// exist with the listed SHA256, in exactly one of the two lists; no file in either folder may be missing from its list; no
        /// link (junction, symbolic link) may be in the way. In the layout App/Config the install folder above them may hold only the
        /// two folders (an empty folder left over from an older layout that is still in use is allowed; a file anywhere else is not
        /// listed). Returns false and the problems (at most 20, "kind: name", plus the entry TruncatedProblem when the check stopped
        /// there; Tool_Config.xml and Issues_List.xml are checked first) when anything differs, when a list is missing, too large or
        /// invalid (fail closed).
        /// </summary>
        static bool VerifyInstalledLayout(string codeRoot, string configRoot, out List<string> problems)
        {
            return VerifyLayout(codeRoot, configRoot, null, out problems);
        }

        /// <summary>
        /// As above. With pins (trust mode Signature) every list and every listed file is opened once through pins, hashed from
        /// that handle and stays open (nobody can change or replace it) until pins is disposed; the signed catalogs
        /// SelfX.Code.cat (code folder) and SelfX.Config.cat (configuration folder) are then allowed next to the lists. Without
        /// pins (trust mode Hash) a catalog is a file that is not listed.
        /// </summary>
        static bool VerifyLayout(string codeRoot, string configRoot, PinnedFiles pins, out List<string> problems)
        {
            problems = new List<string>();
            bool truncated = false;
            try
            {
                string code = Path.GetFullPath(codeRoot).TrimEnd('\\');
                string config = Path.GetFullPath(configRoot).TrimEnd('\\');
                bool split = !string.Equals(code, config, StringComparison.OrdinalIgnoreCase);
                if (split)
                {
                    // Both folders must be real folders of the installation, not links to somewhere else.
                    if (!Directory.Exists(config)) { problems.Add("missing: Config"); return false; }
                    if ((new DirectoryInfo(code).Attributes & FileAttributes.ReparsePoint) != 0) { problems.Add("link: App"); return false; }
                    if ((new DirectoryInfo(config).Attributes & FileAttributes.ReparsePoint) != 0) { problems.Add("link: Config"); return false; }
                }
                Dictionary<string, ListedFile> expected = new Dictionary<string, ListedFile>(StringComparer.OrdinalIgnoreCase);
                string listProblem;
                if (!ReadFileList(code, CodeListName, expected, pins, out listProblem)) { problems.Add(listProblem); return false; }
                if (!ReadFileList(config, ConfigListName, expected, pins, out listProblem)) { problems.Add(listProblem); return false; }

                // Configuration and catalog first, then the rest.
                List<KeyValuePair<string, ListedFile>> ordered = new List<KeyValuePair<string, ListedFile>>();
                foreach (KeyValuePair<string, ListedFile> entry in expected)
                {
                    if (IsPriorityFile(entry.Key)) ordered.Add(entry);
                }
                foreach (KeyValuePair<string, ListedFile> entry in expected)
                {
                    if (!IsPriorityFile(entry.Key)) ordered.Add(entry);
                }
                foreach (KeyValuePair<string, ListedFile> entry in ordered)
                {
                    string root = entry.Value.Root;
                    string full = Path.GetFullPath(Path.Combine(root, entry.Key.Replace('/', '\\')));
                    if (!full.StartsWith(root + "\\", StringComparison.OrdinalIgnoreCase)) { AddProblem(problems, "path: " + entry.Key, ref truncated); continue; }
                    if (!File.Exists(full)) { AddProblem(problems, "missing: " + entry.Key, ref truncated); continue; }
                    if (IsLinkBelow(root, full)) { AddProblem(problems, "link: " + entry.Key, ref truncated); continue; }
                    string actual;
                    try { actual = pins == null ? HashFile(full) : pins.Open(full).Hash; }
                    catch (IOException) { AddProblem(problems, "not readable: " + entry.Key, ref truncated); continue; }
                    if (!string.Equals(actual, entry.Value.Hash, StringComparison.OrdinalIgnoreCase)) AddProblem(problems, "changed: " + entry.Key, ref truncated);
                }
                bool signed = pins != null;
                if (split)
                {
                    FindUnlistedFiles(new DirectoryInfo(code), code, "", expected, signed ? new[] { CodeListName, CodeCatalogName } : new[] { CodeListName }, problems, ref truncated);
                    FindUnlistedFiles(new DirectoryInfo(config), config, "Config/", expected, signed ? new[] { ConfigListName, ConfigCatalogName } : new[] { ConfigListName }, problems, ref truncated);
                    FindForeignEntries(code, config, problems, ref truncated);
                }
                else
                {
                    FindUnlistedFiles(new DirectoryInfo(code), code, "", expected, signed ? new[] { CodeListName, ConfigListName, CodeCatalogName, ConfigCatalogName } : FileListNames, problems, ref truncated);
                }
                if (truncated) problems.Add(TruncatedProblem);
                return problems.Count == 0;
            }
            catch (JsonException)
            {
                problems.Add("file list: invalid JSON");
                return false;
            }
            catch (Exception ex)
            {
                // Fail closed: when a list or the files cannot be read, nothing is started.
                problems.Add("check failed: " + ex.GetType().Name);
                return false;
            }
        }

        /// <summary>
        /// Layout App/Config: the install folder above the two folders may hold nothing else. A file there or in another folder is
        /// "not listed", a link is "link"; an empty folder (left over from an older layout while a process still uses it as working
        /// folder) is allowed.
        /// </summary>
        static void FindForeignEntries(string code, string config, List<string> problems, ref bool truncated)
        {
            string parent = Path.GetDirectoryName(code);
            if (string.IsNullOrEmpty(parent) || !string.Equals(Path.GetDirectoryName(config), parent, StringComparison.OrdinalIgnoreCase)) { AddProblem(problems, "path: Config", ref truncated); return; }
            foreach (FileSystemInfo entry in new DirectoryInfo(parent).EnumerateFileSystemInfos())
            {
                string full = entry.FullName.TrimEnd('\\');
                if (string.Equals(full, code, StringComparison.OrdinalIgnoreCase) || string.Equals(full, config, StringComparison.OrdinalIgnoreCase)) continue;
                if ((entry.Attributes & FileAttributes.ReparsePoint) != 0) { AddProblem(problems, "link: ../" + entry.Name, ref truncated); continue; }
                DirectoryInfo folder = entry as DirectoryInfo;
                if (folder == null) { AddProblem(problems, "not listed: ../" + entry.Name, ref truncated); continue; }
                FindAnyFile(folder, parent, problems, ref truncated);
            }
        }

        static void FindAnyFile(DirectoryInfo folder, string parent, List<string> problems, ref bool truncated)
        {
            foreach (FileSystemInfo entry in folder.EnumerateFileSystemInfos())
            {
                string relative = "../" + entry.FullName.Substring(parent.Length + 1).Replace('\\', '/');
                if ((entry.Attributes & FileAttributes.ReparsePoint) != 0) { AddProblem(problems, "link: " + relative, ref truncated); continue; }
                DirectoryInfo sub = entry as DirectoryInfo;
                if (sub != null) { FindAnyFile(sub, parent, problems, ref truncated); continue; }
                AddProblem(problems, "not listed: " + relative, ref truncated);
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

        /// <summary>True for the files that are checked first (name relative to the root, case-insensitive).</summary>
        static bool IsPriorityFile(string relative)
        {
            foreach (string name in PriorityFiles)
            {
                if (string.Equals(relative, name, StringComparison.OrdinalIgnoreCase)) return true;
            }
            return false;
        }

        /// <summary>Adds a problem up to MaxFileProblems; a further problem only sets truncated (the check continues, so the flag means that more problems really exist).</summary>
        static void AddProblem(List<string> problems, string problem, ref bool truncated)
        {
            if (problems.Count >= MaxFileProblems) truncated = true;
            else problems.Add(problem);
        }

        /// <summary>
        /// Every file below root must be listed with root as its folder (a file of the code folder is not covered by an entry of the
        /// configuration list and the other way round). shownPrefix is put in front of the name in a problem ("Config/" for the
        /// configuration folder). The names in exempt (the list files of this folder) are skipped at the top of root.
        /// </summary>
        static void FindUnlistedFiles(DirectoryInfo folder, string root, string shownPrefix, Dictionary<string, ListedFile> listed, string[] exempt, List<string> problems, ref bool truncated)
        {
            foreach (FileSystemInfo entry in folder.EnumerateFileSystemInfos())
            {
                string relative = entry.FullName.Substring(root.Length + 1).Replace('\\', '/');
                if ((entry.Attributes & FileAttributes.ReparsePoint) != 0) { AddProblem(problems, "link: " + shownPrefix + relative, ref truncated); continue; }
                DirectoryInfo sub = entry as DirectoryInfo;
                if (sub != null) { FindUnlistedFiles(sub, root, shownPrefix, listed, exempt, problems, ref truncated); continue; }
                // Any file type: the lists are the complete content of the install folder (see the comment at PriorityFiles).
                bool isList = false;
                foreach (string listName in exempt)
                {
                    if (string.Equals(relative, listName, StringComparison.OrdinalIgnoreCase)) isList = true;
                }
                if (isList) continue;
                ListedFile file;
                if (!listed.TryGetValue(relative, out file) || !string.Equals(file.Root, root, StringComparison.OrdinalIgnoreCase)) AddProblem(problems, "not listed: " + shownPrefix + relative, ref truncated);
            }
        }

        /// <summary>
        /// Called before every start of a script. Reads the trust anchor and checks the installation in its mode. Returns false
        /// when nothing may be started. Mode Hash: the file check (CheckInstalledFiles(scriptName)), pinned stays null. Mode
        /// Signature: the signature check (VerifySignedLayout); on success pinned holds the open handles of all checked files and
        /// the caller disposes it after the script has ended, so the files that were checked are the files that run. A failed
        /// signature check never starts anything, also with Service_FileCheck=Audit; the setting only applies to differences
        /// between the files and the two lists, as in the mode Hash. A missing, invalid or unprotected anchor starts nothing.
        /// </summary>
        bool CheckInstalledFiles(string scriptName, string scriptPath, out PinnedFiles pinned)
        {
            pinned = null;
            string anchorProblem;
            TrustAnchor anchor = ReadTrustAnchor(RegistryHive.LocalMachine, TrustKeyPath, TrustAnchorWriterSids, out anchorProblem);
            if (anchor == null)
            {
                Log("The trust anchor HKLM\\" + TrustKeyPath + " cannot be used (" + anchorProblem + "); '" + scriptName + "' was not started.");
                // Fixed text: the reason (it can name the SID of an account) is written to the SelfX log only.
                SecurityEvent(EventTrustAnchor, EventLogEntryType.Error, "The trust anchor HKLM\\" + TrustKeyPath + " is missing, invalid or can be changed by normal users; SelfX actions as SYSTEM are not started. Install SelfX again. See the SelfX log.");
                return false;
            }
            if (!anchor.Signature) return CheckInstalledFiles(scriptName);

            PinnedFiles pins = new PinnedFiles();
            bool keep = false;
            try
            {
                List<string> fileProblems, signatureProblems;
                VerifySignedLayout(installRoot, configRoot, anchor.Signers, signatureCache, pins, out fileProblems, out signatureProblems);
                // The script that is started must itself be one of the files whose signature was accepted.
                if (signatureProblems.Count == 0 && !pins.IsSignatureChecked(scriptPath)) signatureProblems.Add("signature: " + scriptName + " (not checked)");
                if (signatureProblems.Count > 0)
                {
                    string shown = string.Join("; ", signatureProblems.GetRange(0, Math.Min(5, signatureProblems.Count)));
                    Log("Trust mode Signature: the signature check failed (" + shown + (signatureProblems.Count > 5 ? "; and " + (signatureProblems.Count - 5) + " more" : "") + "). '" + scriptName + "' was not started.");
                    SecurityEvent(EventSignature, EventLogEntryType.Error, "Trust mode Signature: an installed SelfX file has no valid signature of an allowed signer, or a signed catalog is missing or does not match; SelfX actions as SYSTEM are not started. See the SelfX log.");
                    return false;
                }
                if (fileProblems.Count > 0 && !ReportFileProblems(scriptName, fileProblems)) return false;
                pinned = pins;
                keep = true;
                return true;
            }
            finally
            {
                if (!keep) pins.Dispose();
            }
        }

        /// <summary>
        /// Trust mode Hash. Returns true when the installed files match SelfX.Code.json and SelfX.Config.json. Otherwise
        /// nothing is started (Enforce, default); with Service_FileCheck=Audit in Tool_Config.xml the problem is only logged.
        /// The setting counts only when the file list is intact, Tool_Config.xml itself is not among the problems and the check
        /// was not cut off at the problem limit (Tool_Config.xml is checked first, but a cut-off list cannot prove it).
        /// Event 4005 notes a cut-off check.
        /// </summary>
        bool CheckInstalledFiles(string scriptName)
        {
            List<string> problems;
            if (VerifyInstalledLayout(installRoot, configRoot, out problems)) return true;
            return ReportFileProblems(scriptName, problems);
        }

        /// <summary>Logs the differences between the files and the lists (event 4005). Returns true when the script is started anyway (Audit).</summary>
        bool ReportFileProblems(string scriptName, List<string> problems)
        {
            bool audit = false;
            bool truncated = problems.Contains(TruncatedProblem);
            bool settingTrusted = !truncated && !problems.Exists(delegate(string p) { return p.StartsWith("file list:", StringComparison.Ordinal) || p.StartsWith("check failed:", StringComparison.Ordinal) || p.IndexOf("Tool_Config.xml", StringComparison.OrdinalIgnoreCase) >= 0; });
            if (settingTrusted) audit = string.Equals(ReadToolConfigValue("Service_FileCheck"), "Audit", StringComparison.OrdinalIgnoreCase);
            string shown = string.Join("; ", problems.GetRange(0, Math.Min(5, problems.Count)));
            string cutOff = truncated ? " The check stopped after " + MaxFileProblems + " problems; the list is incomplete." : "";
            Log("Installed files do not match " + CodeListName + " and " + ConfigListName + " (" + shown + ")." + cutOff + " '" + scriptName + (audit ? "' is started anyway (Service_FileCheck=Audit)." : "' was not started."));
            SecurityEvent(EventFilesChanged, audit ? EventLogEntryType.Warning : EventLogEntryType.Error,
                (audit ? "Installed SelfX files do not match SelfX.Code.json and SelfX.Config.json (Audit: actions as SYSTEM are still started). See the SelfX log."
                       : "Installed SelfX files do not match SelfX.Code.json and SelfX.Config.json; SelfX actions as SYSTEM are not started. See the SelfX log.") + cutOff);
            return audit;
        }

        // --- Trust mode (docs\Architecture.md). Install.ps1 writes the anchor; the service only reads it. ---
        const string TrustKeyPath = @"SOFTWARE\SelfX\Trust";
        const string CodeCatalogName = "SelfX.Code.cat";
        const string ConfigCatalogName = "SelfX.Config.cat";
        const int MaxTrustedSigners = 10;
        const long MaxCatalogBytes = 4 * 1048576;
        // The only identities that may own or change the anchor (same rule as Test-SelfXTrustAnchorState in Install.ps1).
        static readonly string[] TrustAnchorWriterSids = { "S-1-5-18", "S-1-5-32-544" };
        static readonly Regex ThumbprintPattern = new Regex(@"^[0-9A-Fa-f]{40}\z", RegexOptions.CultureInvariant);
        // Files of the lists that carry an embedded signature and are loaded by a script that the service starts. The two
        // programs (.exe) are not loaded by a script; they stay bound by their SHA256 in the signed list.
        static readonly string[] SignedExtensions = { ".ps1", ".psm1", ".psd1", ".dll" };
        static readonly TimeSpan SignatureCacheLifetime = TimeSpan.FromMinutes(60);
        const int MaxSignatureCacheEntries = 2000;

        /// <summary>The trust anchor as Install.ps1 wrote it.</summary>
        sealed class TrustAnchor
        {
            public bool Signature;
            public string[] Signers = new string[0];
        }

        /// <summary>
        /// Reads the trust anchor (64-bit view of the registry). Returns null and the problem when the key is missing, when it is
        /// owned by an identity outside writerSids, when any other identity may change it (set a value, create a sub key or a
        /// link, delete, change rights, take ownership; generic write and generic all count too), when Mode is not the text Hash
        /// or Signature, or when the mode Signature has no valid list of signers (REG_MULTI_SZ, 1 to 10 SHA1 thumbprints of 40
        /// hexadecimal characters). Anything that cannot be read is a problem (fail closed). hive, subKey and writerSids are
        /// parameters for the tests only; the service passes HKLM, TrustKeyPath and TrustAnchorWriterSids.
        /// </summary>
        static TrustAnchor ReadTrustAnchor(RegistryHive hive, string subKey, string[] writerSids, out string problem)
        {
            problem = null;
            try
            {
                using (RegistryKey baseKey = RegistryKey.OpenBaseKey(hive, RegistryView.Registry64))
                using (RegistryKey key = baseKey.OpenSubKey(subKey, false))
                {
                    if (key == null) { problem = "the key is missing"; return null; }
                    RegistrySecurity security = key.GetAccessControl(AccessControlSections.Owner | AccessControlSections.Access);
                    SecurityIdentifier owner = security.GetOwner(typeof(SecurityIdentifier)) as SecurityIdentifier;
                    if (owner == null || Array.IndexOf(writerSids, owner.Value) < 0) { problem = "the key is owned by " + (owner == null ? "an unknown identity" : owner.Value); return null; }
                    const int write = (int)(RegistryRights.SetValue | RegistryRights.CreateSubKey | RegistryRights.CreateLink | RegistryRights.Delete | RegistryRights.ChangePermissions | RegistryRights.TakeOwnership) | 0x10000000 | 0x40000000;
                    foreach (RegistryAccessRule rule in security.GetAccessRules(true, true, typeof(SecurityIdentifier)))
                    {
                        if (rule.AccessControlType != AccessControlType.Allow) continue;
                        if (((int)rule.RegistryRights & write) == 0) continue;
                        if (Array.IndexOf(writerSids, rule.IdentityReference.Value) >= 0) continue;
                        problem = "the key can be changed by " + rule.IdentityReference.Value;
                        return null;
                    }
                    string mode = key.GetValue("Mode", null, RegistryValueOptions.DoNotExpandEnvironmentNames) as string;
                    if (mode == null || key.GetValueKind("Mode") != RegistryValueKind.String) { problem = "Mode is missing or not a text"; return null; }
                    TrustAnchor anchor = new TrustAnchor();
                    if (mode == "Hash") return anchor;
                    if (mode != "Signature") { problem = "Mode is neither Hash nor Signature"; return null; }
                    string[] signers = key.GetValue("Signers", null, RegistryValueOptions.DoNotExpandEnvironmentNames) as string[];
                    if (signers == null || key.GetValueKind("Signers") != RegistryValueKind.MultiString || signers.Length == 0 || signers.Length > MaxTrustedSigners) { problem = "Signers is missing or not a list of 1 to " + MaxTrustedSigners + " thumbprints"; return null; }
                    List<string> list = new List<string>();
                    foreach (string signer in signers)
                    {
                        if (signer == null || !ThumbprintPattern.IsMatch(signer)) { problem = "Signers holds an entry that is not a SHA1 thumbprint"; return null; }
                        list.Add(signer.ToUpperInvariant());
                    }
                    anchor.Signature = true;
                    anchor.Signers = list.ToArray();
                    return anchor;
                }
            }
            catch (Exception ex)
            {
                problem = "the key cannot be read (" + ex.GetType().Name + ")";
                return null;
            }
        }

        /// <summary>
        /// The files of one check, each opened once: others may read the file, nobody may write, replace, rename or delete it
        /// while the handle is open (FileShare.Read). The SHA256, the size and the write time are read from that handle. The
        /// handles stay open until Dispose, which the service calls after the started script has ended: what was checked is what
        /// runs, without a second look at the file by path that could find other content.
        /// </summary>
        internal sealed class PinnedFiles : IDisposable
        {
            internal sealed class Entry
            {
                public FileStream Stream;
                public string Hash;
                public long Length;
                public DateTime WriteTimeUtc;
                public bool SignatureChecked;

                /// <summary>The whole file from the handle, or null when it is larger than max.</summary>
                public byte[] ReadAll(long max)
                {
                    if (Length > max) return null;
                    byte[] content = new byte[(int)Length];
                    Stream.Position = 0;
                    int done = 0;
                    while (done < content.Length)
                    {
                        int read = Stream.Read(content, done, content.Length - done);
                        if (read <= 0) throw new IOException("The file ended early.");
                        done += read;
                    }
                    return content;
                }
            }

            readonly Dictionary<string, Entry> entries = new Dictionary<string, Entry>(StringComparer.OrdinalIgnoreCase);

            public int Count { get { return entries.Count; } }
            public IEnumerable<KeyValuePair<string, Entry>> Entries { get { return entries; } }

            /// <summary>Opens the file (full path) once and hashes it; a second call returns the same entry. Throws when it cannot be opened.</summary>
            public Entry Open(string fullPath)
            {
                Entry entry;
                if (entries.TryGetValue(fullPath, out entry)) return entry;
                FileStream stream = new FileStream(fullPath, FileMode.Open, FileAccess.Read, FileShare.Read);
                try
                {
                    entry = new Entry();
                    entry.Stream = stream;
                    entry.Length = stream.Length;
                    entry.WriteTimeUtc = File.GetLastWriteTimeUtc(stream.SafeFileHandle);
                    using (SHA256 sha = SHA256.Create()) { entry.Hash = BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", ""); }
                }
                catch
                {
                    stream.Dispose();
                    throw;
                }
                entries[fullPath] = entry;
                return entry;
            }

            public Entry Find(string fullPath)
            {
                Entry entry;
                return fullPath != null && entries.TryGetValue(fullPath, out entry) ? entry : null;
            }

            public bool IsSignatureChecked(string fullPath)
            {
                Entry entry = Find(fullPath);
                return entry != null && entry.SignatureChecked;
            }

            public void Dispose()
            {
                foreach (Entry entry in entries.Values)
                {
                    try { entry.Stream.Dispose(); } catch { }
                }
                entries.Clear();
            }
        }

        /// <summary>
        /// Positive results of the signature check, kept for SignatureCacheLifetime. An entry is used only when the path, the
        /// write time, the size and the SHA256 read from the open handle are the same (and, for a member of a catalog, the SHA256
        /// of the catalog, which is part of the key). The stored value is the thumbprint of the signer; whether that signer is
        /// allowed is decided at every start from the anchor. Negative results are never kept. The lifetime bounds what can change
        /// without the file changing: a certificate that expires, is revoked or is no longer trusted.
        /// </summary>
        internal sealed class SignatureCache
        {
            sealed class Item
            {
                public string Hash;
                public long Length;
                public DateTime WriteTimeUtc;
                public string Thumbprint;
                public DateTime Expires;
            }

            readonly Dictionary<string, Item> items = new Dictionary<string, Item>(StringComparer.OrdinalIgnoreCase);
            readonly object gate = new object();
            public int Hits;
            public int Misses;

            public string Find(string key, PinnedFiles.Entry file, DateTime now)
            {
                lock (gate)
                {
                    Item item;
                    if (items.TryGetValue(key, out item) && now < item.Expires && item.Length == file.Length && item.WriteTimeUtc == file.WriteTimeUtc &&
                        string.Equals(item.Hash, file.Hash, StringComparison.Ordinal))
                    {
                        Hits++;
                        return item.Thumbprint;
                    }
                    Misses++;
                    return null;
                }
            }

            public void Store(string key, PinnedFiles.Entry file, string thumbprint, DateTime now)
            {
                lock (gate)
                {
                    if (items.Count >= MaxSignatureCacheEntries) items.Clear();
                    items[key] = new Item { Hash = file.Hash, Length = file.Length, WriteTimeUtc = file.WriteTimeUtc, Thumbprint = thumbprint, Expires = now + SignatureCacheLifetime };
                }
            }
        }

        static bool IsAllowedSigner(string thumbprint, string[] signers)
        {
            if (thumbprint == null || signers == null) return false;
            foreach (string signer in signers)
            {
                if (string.Equals(signer, thumbprint, StringComparison.OrdinalIgnoreCase)) return true;
            }
            return false;
        }

        /// <summary>
        /// Embedded Authenticode signature of a pinned file. Returns null when Windows accepts the signature and the signer is
        /// allowed, otherwise the reason (NoSignature, BadDigest, UntrustedRoot, Expired, Revoked, SignerNotAllowed, ...).
        /// </summary>
        static string CheckEmbeddedSignature(string fullPath, PinnedFiles.Entry file, string[] signers, SignatureCache cache)
        {
            DateTime now = DateTime.UtcNow;
            string key = "E|" + fullPath;
            string thumbprint = cache == null ? null : cache.Find(key, file, now);
            if (thumbprint == null)
            {
                SelfXTrust.Verdict verdict = SelfXTrust.VerifyEmbedded(fullPath, file.Stream);
                if (verdict.Reason != "Ok") return verdict.Reason;
                if (!ThumbprintPattern.IsMatch(verdict.Thumbprint)) return "SignerUnknown";
                thumbprint = verdict.Thumbprint;
                if (cache != null) cache.Store(key, file, thumbprint, now);
            }
            if (!IsAllowedSigner(thumbprint, signers)) return "SignerNotAllowed";
            file.SignatureChecked = true;
            return null;
        }

        /// <summary>
        /// A pinned file as a member of a pinned, signed catalog: the catalog hash of the file (SHA256, from its handle) is in the
        /// catalog, Windows accepts the signature of the catalog and its signer is allowed. Returns null or the reason.
        /// </summary>
        static string CheckCatalogMember(string catalogPath, PinnedFiles.Entry catalog, string fullPath, PinnedFiles.Entry file, string[] signers, SignatureCache cache)
        {
            DateTime now = DateTime.UtcNow;
            string key = "C|" + catalog.Hash + "|" + fullPath;
            string thumbprint = cache == null ? null : cache.Find(key, file, now);
            if (thumbprint == null)
            {
                SelfXTrust.Verdict verdict = SelfXTrust.VerifyCatalogMember(catalogPath, fullPath, file.Stream);
                if (verdict.Reason != "Ok") return verdict.Reason == "NoSignature" ? "NotInCatalogOrCatalogUnsigned" : verdict.Reason;
                if (!ThumbprintPattern.IsMatch(verdict.Thumbprint)) return "SignerUnknown";
                thumbprint = verdict.Thumbprint;
                if (cache != null) cache.Store(key, file, thumbprint, now);
            }
            if (!IsAllowedSigner(thumbprint, signers)) return "SignerNotAllowed";
            file.SignatureChecked = true;
            return null;
        }

        /// <summary>Pins a list and its catalog and checks that the list is a member of the signed catalog. Returns the catalog entry or null (problem added).</summary>
        static PinnedFiles.Entry CheckSignedList(string root, string listName, string catalogName, string[] signers, SignatureCache cache, PinnedFiles pins, List<string> problems)
        {
            string catalogPath = Path.Combine(root, catalogName);
            string listPath = Path.Combine(root, listName);
            PinnedFiles.Entry catalog = null, list = null;
            foreach (string name in new[] { catalogName, listName })
            {
                string path = Path.Combine(root, name);
                try
                {
                    FileInfo info = new FileInfo(path);
                    if (!info.Exists) { problems.Add("signature: " + name + " (missing)"); return null; }
                    if ((info.Attributes & FileAttributes.ReparsePoint) != 0) { problems.Add("signature: " + name + " (link)"); return null; }
                    if (info.Length > MaxCatalogBytes) { problems.Add("signature: " + name + " (too large)"); return null; }
                    PinnedFiles.Entry entry = pins.Open(path);
                    if (name == catalogName) catalog = entry; else list = entry;
                }
                catch (Exception ex)
                {
                    if (!(ex is IOException) && !(ex is UnauthorizedAccessException)) throw;
                    problems.Add("signature: " + name + " (not readable)");
                    return null;
                }
            }
            string reason = CheckCatalogMember(catalogPath, catalog, listPath, list, signers, cache);
            if (reason != null) { problems.Add("signature: " + listName + " against " + catalogName + " (" + reason + ")"); return null; }
            return catalog;
        }

        /// <summary>
        /// Trust mode Signature, the whole check of one start. Every file is opened through pins and stays open:
        ///  1. SelfX.Code.json is a member of the signed catalog SelfX.Code.cat next to it (code folder), SelfX.Config.json a member
        ///     of SelfX.Config.cat (configuration folder); both catalogs are signed by an allowed signer. The names in SelfX.Code.cat
        ///     are paths of the package, so the list is found by its hash, and the list binds the installed names.
        ///  2. The file check (VerifyLayout) on the pinned handles: every listed file exists with the listed SHA256, no file
        ///     without an entry, no link. Differences go to fileProblems (Service_FileCheck decides, as in the mode Hash).
        ///  3. Every listed .ps1, .psm1, .psd1 and .dll that could be opened has an embedded signature of an allowed signer.
        ///  4. Every settings file of the configuration folder (Issues_List.xml, Health_Config.xml, Tool_Config.xml, ...) is a member
        ///     of SelfX.Config.cat.
        /// Everything of 1, 3 and 4 that fails goes to signatureProblems (at most 20). Returns true when both lists are empty.
        /// Anything unexpected is a signature problem (fail closed).
        /// </summary>
        static bool VerifySignedLayout(string codeRoot, string configRoot, string[] signers, SignatureCache cache, PinnedFiles pins, out List<string> fileProblems, out List<string> signatureProblems)
        {
            fileProblems = new List<string>();
            signatureProblems = new List<string>();
            try
            {
                if (signers == null || signers.Length == 0) { signatureProblems.Add("signature: no allowed signer"); return false; }
                string code = Path.GetFullPath(codeRoot).TrimEnd('\\');
                string config = Path.GetFullPath(configRoot).TrimEnd('\\');
                PinnedFiles.Entry codeCatalog = CheckSignedList(code, CodeListName, CodeCatalogName, signers, cache, pins, signatureProblems);
                PinnedFiles.Entry configCatalog = CheckSignedList(config, ConfigListName, ConfigCatalogName, signers, cache, pins, signatureProblems);
                if (codeCatalog == null || configCatalog == null) return false;

                VerifyLayout(code, config, pins, out fileProblems);

                bool truncated = false;
                List<KeyValuePair<string, PinnedFiles.Entry>> files = new List<KeyValuePair<string, PinnedFiles.Entry>>(pins.Entries);
                foreach (KeyValuePair<string, PinnedFiles.Entry> file in files)
                {
                    string extension = Path.GetExtension(file.Key);
                    bool signedType = false;
                    foreach (string known in SignedExtensions)
                    {
                        if (string.Equals(known, extension, StringComparison.OrdinalIgnoreCase)) signedType = true;
                    }
                    if (!signedType) continue;
                    string reason = CheckEmbeddedSignature(file.Key, file.Value, signers, cache);
                    if (reason != null) AddProblem(signatureProblems, "signature: " + ShownName(code, config, file.Key) + " (" + reason + ")", ref truncated);
                }
                string configCatalogPath = Path.Combine(config, ConfigCatalogName);
                foreach (string name in ConfigFileNames)
                {
                    string full = Path.Combine(config, name);
                    PinnedFiles.Entry entry = pins.Find(full);
                    // A settings file that is not listed or could not be opened is a problem of the file check (step 2).
                    if (entry == null) continue;
                    string reason = CheckCatalogMember(configCatalogPath, configCatalog, full, entry, signers, cache);
                    if (reason != null) AddProblem(signatureProblems, "signature: " + name + " against " + ConfigCatalogName + " (" + reason + ")", ref truncated);
                }
                if (truncated) signatureProblems.Add(TruncatedProblem);
                return fileProblems.Count == 0 && signatureProblems.Count == 0;
            }
            catch (Exception ex)
            {
                signatureProblems.Add("signature: check failed (" + ex.GetType().Name + ")");
                return false;
            }
        }

        /// <summary>Name of an installed file for the log: relative to the code folder, or Config/... for the configuration folder.</summary>
        static string ShownName(string code, string config, string full)
        {
            if (full.StartsWith(code + "\\", StringComparison.OrdinalIgnoreCase)) return full.Substring(code.Length + 1).Replace('\\', '/');
            if (full.StartsWith(config + "\\", StringComparison.OrdinalIgnoreCase)) return "Config/" + full.Substring(config.Length + 1).Replace('\\', '/');
            return Path.GetFileName(full);
        }

        string ReadToolConfigValue(string name)
        {
            try
            {
                string toolConfig = GetConfigFilePath("Tool_Config.xml");
                XmlReaderSettings settings = new XmlReaderSettings();
                settings.DtdProcessing = DtdProcessing.Prohibit;
                settings.XmlResolver = null;
                XmlDocument document = new XmlDocument();
                document.XmlResolver = null;
                using (XmlReader reader = XmlReader.Create(toolConfig, settings)) { document.Load(reader); }
                XmlNode node = document.SelectSingleNode("/GUI_Config/" + name);
                return node == null ? "" : node.InnerText.Trim();
            }
            // null = the file cannot be read; each caller decides how to fail closed.
            catch { return null; }
        }

        /// <summary>Fixed path of PowerShell 7 (machine-wide installation, writable only by administrators).</summary>
        static string PowerShellPath
        {
            get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), @"PowerShell\7\pwsh.exe"); }
        }

        // The only identities that may change PowerShell 7 or the folders above it: SYSTEM, Administrators and TrustedInstaller
        // (NT SERVICE\TrustedInstaller). Everything else (Everyone, Users, Authenticated Users, Interactive, CREATOR OWNER,
        // a domain or local group, a single account) counts as "normal users".
        static readonly string[] TrustedWriterSids =
        {
            "S-1-5-18", "S-1-5-32-544", "S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464"
        };

        /// <summary>
        /// The installer checks the rights of PowerShell 7 only when SelfX is installed. PowerShell 7 can arrive later
        /// (Autopilot installs apps in any order), so the service checks it again before every start: pwsh.exe and its folder
        /// may only be changed by SYSTEM, Administrators and TrustedInstaller (any other identity with write, delete,
        /// permission or ownership rights is refused), and so may the folders above it up to the drive root (nobody else may
        /// delete or take over the folder that contains pwsh.exe). The owner is not compared (a device where another
        /// account owns the folder must keep working); what counts is who may change it. A SYSTEM process must never run a program that normal users can replace.
        /// </summary>
        static bool IsPowerShellProtected(string executable, out string reason)
        {
            return IsPathChainProtected(executable, null, null, out reason);
        }

        /// <summary>
        /// The check behind IsPowerShellProtected. Tests only: stopBefore (null = whole chain) is the first folder above the
        /// file that is no longer checked, so a test folder below %TEMP% is not judged by the rights of the user profile;
        /// trustedSids (null = TrustedWriterSids) lets a test that runs as a normal user trust its own account.
        /// </summary>
        static bool IsPathChainProtected(string executable, string stopBefore, string[] trustedSids, out string reason)
        {
            reason = "";
            if (trustedSids == null) trustedSids = TrustedWriterSids;
            // pwsh.exe and its own folder: any right that changes, replaces or adds code.
            FileSystemRights direct = FileSystemRights.WriteData | FileSystemRights.AppendData | FileSystemRights.Delete |
                FileSystemRights.DeleteSubdirectoriesAndFiles | FileSystemRights.ChangePermissions | FileSystemRights.TakeOwnership;
            // Folders above it: rights that remove or take over the folder below them. Creating new entries (drive root: normal
            // users may create folders) does not replace an existing folder; rules that only apply to children are skipped.
            FileSystemRights above = FileSystemRights.DeleteSubdirectoriesAndFiles | FileSystemRights.ChangePermissions | FileSystemRights.TakeOwnership;
            try
            {
                FileInfo file = new FileInfo(executable);
                if (!IsProtectedAgainstChange(file.GetAccessControl(), executable, direct, trustedSids, out reason)) return false;
                DirectoryInfo folder = file.Directory;
                if (folder == null) { reason = "'" + executable + "' has no folder"; return false; }
                if (!IsProtectedAgainstChange(folder.GetAccessControl(), folder.FullName, direct, trustedSids, out reason)) return false;
                string limit = stopBefore == null ? null : Path.GetFullPath(stopBefore).TrimEnd('\\');
                for (DirectoryInfo parent = folder.Parent; parent != null; parent = parent.Parent)
                {
                    if (limit != null && string.Equals(parent.FullName.TrimEnd('\\'), limit, StringComparison.OrdinalIgnoreCase)) break;
                    if (!IsProtectedAgainstChange(parent.GetAccessControl(), parent.FullName, above, trustedSids, out reason)) return false;
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

        static bool IsProtectedAgainstChange(FileSystemSecurity security, string path, FileSystemRights dangerous, string[] trustedSids, out string reason)
        {
            reason = "";
            foreach (FileSystemAccessRule rule in security.GetAccessRules(true, true, typeof(SecurityIdentifier)))
            {
                if (rule.AccessControlType != AccessControlType.Allow) continue;
                // A rule that only applies to child items (for example CREATOR OWNER in Program Files) says nothing about this item;
                // the children are checked with their own rights.
                if ((rule.PropagationFlags & PropagationFlags.InheritOnly) != 0) continue;
                if ((rule.FileSystemRights & dangerous) == 0) continue;
                if (Array.IndexOf(trustedSids, rule.IdentityReference.Value) >= 0) continue;
                reason = "'" + path + "' can be changed by normal users (" + rule.IdentityReference.Value + ")";
                return false;
            }
            return true;
        }

        /// <summary>
        /// Run PowerShell under the service identity and log bounded output and completion.
        /// </summary>
        string RunScript(string scriptPath, string scriptName, int timeoutSeconds, string user, bool health = false, string healthFilter = "", string callerSid = null, bool background = false, bool callerIsAdmin = false, string appId = null)
        {
            // N6: no new process while the service stops (it would outlive the job object that was just ended).
            if (stopping)
            {
                return "ERROR Service is stopping";
            }
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
            // Scripts and configuration must be exactly what the package contained (trust mode Hash) or what the allowed signer
            // signed (trust mode Signature; the checked files then stay open until the script has ended).
            PinnedFiles pinned;
            if (!CheckInstalledFiles(scriptName, scriptPath, out pinned))
            {
                return "ERROR Installed files are not intact";
            }
            try
            {
                return StartScript(powershell, scriptPath, scriptName, timeoutSeconds, user, health, healthFilter, callerSid, background, callerIsAdmin, appId);
            }
            finally
            {
                if (pinned != null) pinned.Dispose();
            }
        }

        /// <summary>
        /// The second half of RunScript: starts PowerShell with the checked script, waits for the end or the timeout and
        /// returns the protocol answer.
        /// </summary>
        string StartScript(string powershell, string scriptPath, string scriptName, int timeoutSeconds, string user, bool health, string healthFilter, string callerSid, bool background, bool callerIsAdmin, string appId)
        {
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
            // The app of APPRETRY: only the ID that the service read itself from the IME cache, and only for an action; every other start
            // (RUN, health, background) has no value, also not an inherited one.
            startInfo.EnvironmentVariables.Remove(AppIdVariable);
            if (!health && appId != null && AppIdPattern.IsMatch(appId))
            {
                startInfo.EnvironmentVariables[AppIdVariable] = appId;
            }
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
            // Events 4010-4012 for System actions (RUN, also a remediation); health runs only report rows that changed to Error (4013).
            // The script name is the checked file name of the catalog; the SID only with EventLog_CallerSid = True.
            string eventSid = health ? EventNoValue : EventCallerSid(callerSid);
            if (!health)
            {
                WriteEventRecord(EventActionStarted, EventLogEntryType.Information,
                    ActionEventFields(EventActionStarted, scriptName, null, null, 0, eventSid, callerIsAdmin));
            }
            Stopwatch watch = Stopwatch.StartNew();
            string result;
            using (Process process = new Process())
            {
                process.StartInfo = startInfo;
                process.OutputDataReceived += collect;
                process.ErrorDataReceived += collect;
                try
                {
                    process.Start();
                }
                catch (Exception)
                {
                    if (!health)
                    {
                        WriteEventRecord(EventActionFailed, EventLogEntryType.Error,
                            ActionEventFields(EventActionFailed, scriptName, "StartError", EventNoValue, (long)watch.Elapsed.TotalSeconds, eventSid, callerIsAdmin));
                    }
                    throw;
                }
                AttachToJob(process, scriptName);
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
            long seconds = (long)watch.Elapsed.TotalSeconds;
            if (health)
            {
                if (result == "DONE 0" && !outputOverflow)
                {
                    ReportHealthChanges(text);
                    // Event 4014 from the own reading of the IME cache (not from the JSON of the script).
                    ReportAppFailures();
                    // Only a full collection describes the whole device (a single check has only its own rows).
                    if (string.IsNullOrEmpty(healthFilter)) WriteInventory(text);
                }
            }
            else if (result == "DONE 0")
            {
                WriteEventRecord(EventActionSucceeded, EventLogEntryType.Information,
                    ActionEventFields(EventActionSucceeded, scriptName, "ExitCode", "0", seconds, eventSid, callerIsAdmin));
            }
            else
            {
                bool timeout = result == "TIMEOUT";
                WriteEventRecord(EventActionFailed, timeout ? EventLogEntryType.Error : EventLogEntryType.Warning,
                    ActionEventFields(EventActionFailed, scriptName, timeout ? "Timeout" : "ExitCode",
                        timeout ? EventNoValue : result.Substring("DONE ".Length), seconds, eventSid, callerIsAdmin));
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
                string healthConfig = GetConfigFilePath("Health_Config.xml");
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
                    bool healthOff = ReadHealthAccess() == HealthAccess.Off;
                    backgroundInterval = settings.Enabled && !healthOff ? settings.IntervalMinutes : 0;
                    if (healthOff)
                    {
                        // Mode TerminalServer with TerminalServer_Health Off: no checks and no status cache; Background Enabled
                        // is ignored. The housekeeping above still runs.
                        backgroundState = "Disabled";
                        LogBackgroundNote("Background health checks are off: terminal server (mode TerminalServer) with TerminalServer_Health Off.");
                    }
                    else if (!settings.Enabled)
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
                string toolConfig = GetConfigFilePath("Tool_Config.xml");
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
        /// Job object for the PowerShell children of the service (N6). The job ends all its processes when it is
        /// terminated or when its last handle is closed (KILL_ON_JOB_CLOSE, also if the service process itself dies).
        /// Processes started by a child join the job automatically. The job has no name (nothing to open or squat).
        /// A child that spawns a process before it is added to the job is a small gap: pwsh needs far longer for its
        /// start than this call; the timeout path and the taskkill fallback still cover that case.
        /// </summary>
        internal sealed class ChildJob
        {
            const int JobObjectExtendedLimitInformationClass = 9;
            const uint JobObjectLimitKillOnJobClose = 0x00002000;

            [StructLayout(LayoutKind.Sequential)]
            struct IoCounters
            {
                public ulong ReadOperationCount;
                public ulong WriteOperationCount;
                public ulong OtherOperationCount;
                public ulong ReadTransferCount;
                public ulong WriteTransferCount;
                public ulong OtherTransferCount;
            }

            [StructLayout(LayoutKind.Sequential)]
            struct BasicLimitInformation
            {
                public long PerProcessUserTimeLimit;
                public long PerJobUserTimeLimit;
                public uint LimitFlags;
                public UIntPtr MinimumWorkingSetSize;
                public UIntPtr MaximumWorkingSetSize;
                public uint ActiveProcessLimit;
                public UIntPtr Affinity;
                public uint PriorityClass;
                public uint SchedulingClass;
            }

            [StructLayout(LayoutKind.Sequential)]
            struct ExtendedLimitInformation
            {
                public BasicLimitInformation BasicLimitInformation;
                public IoCounters IoInfo;
                public UIntPtr ProcessMemoryLimit;
                public UIntPtr JobMemoryLimit;
                public UIntPtr PeakProcessMemoryUsed;
                public UIntPtr PeakJobMemoryUsed;
            }

            [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
            static extern IntPtr CreateJobObjectW(IntPtr attributes, string name);
            [DllImport("kernel32.dll", SetLastError = true)]
            static extern bool SetInformationJobObject(IntPtr job, int infoClass, IntPtr info, uint infoLength);
            [DllImport("kernel32.dll", SetLastError = true)]
            static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
            [DllImport("kernel32.dll", SetLastError = true)]
            static extern bool TerminateJobObject(IntPtr job, uint exitCode);
            [DllImport("kernel32.dll", SetLastError = true)]
            static extern bool CloseHandle(IntPtr handle);

            readonly object sync = new object();
            IntPtr handle;

            ChildJob(IntPtr jobHandle) { handle = jobHandle; }

            /// <summary>
            /// Create the job with KILL_ON_JOB_CLOSE. Returns null when Windows refuses (the caller logs it and goes on
            /// without the job, as before).
            /// </summary>
            public static ChildJob Create()
            {
                IntPtr job = CreateJobObjectW(IntPtr.Zero, null);
                if (job == IntPtr.Zero) return null;
                ExtendedLimitInformation limits = new ExtendedLimitInformation();
                limits.BasicLimitInformation.LimitFlags = JobObjectLimitKillOnJobClose;
                int length = Marshal.SizeOf(typeof(ExtendedLimitInformation));
                IntPtr buffer = Marshal.AllocHGlobal(length);
                try
                {
                    Marshal.StructureToPtr(limits, buffer, false);
                    if (!SetInformationJobObject(job, JobObjectExtendedLimitInformationClass, buffer, (uint)length))
                    {
                        CloseHandle(job);
                        return null;
                    }
                }
                finally { Marshal.FreeHGlobal(buffer); }
                return new ChildJob(job);
            }

            /// <summary>
            /// Put a started process into the job. False when the job is already ended or Windows refuses.
            /// </summary>
            public bool Add(Process process)
            {
                lock (sync)
                {
                    if (handle == IntPtr.Zero) return false;
                    try { return AssignProcessToJobObject(handle, process.Handle); }
                    catch (InvalidOperationException) { return false; }
                }
            }

            /// <summary>
            /// End all processes of the job at once and close the handle. Safe to call more than once.
            /// </summary>
            public void Terminate()
            {
                lock (sync)
                {
                    if (handle == IntPtr.Zero) return;
                    TerminateJobObject(handle, 1);
                    CloseHandle(handle);
                    handle = IntPtr.Zero;
                }
            }
        }

        /// <summary>
        /// Put a started child into the job object. While the service is stopping, a child that cannot be added is ended
        /// at once; otherwise the failure is logged and the child runs as before (timeout handling still applies).
        /// </summary>
        void AttachToJob(Process process, string scriptName)
        {
            ChildJob job = childJob;
            if (job != null && job.Add(process)) return;
            if (stopping)
            {
                KillProcessTree(process.Id);
                Log("'" + scriptName + "' was ended because the service is stopping.");
                return;
            }
            Log("Warning: '" + scriptName + "' is not in the job object; it would keep running if the service stopped.");
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
        void LogRejected(string message, int eventId = EventRejected, string eventText = null)
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
                SecurityEvent(eventId, EventLogEntryType.Warning, eventText ?? "A request or connection to the SelfX service was rejected. Details are in SelfXService.log in the protected log folder.");
            }
        }

        /// <summary>
        /// Check ProgramData\SelfX: no link, and an owner that only administrators can set. The installer prepares
        /// the folder; this check is the second line of defense when a user changed it later or created it before an update.
        /// </summary>
        bool CheckDataFolder(out string reason)
        {
            reason = "";
            string dataRoot = Path.GetDirectoryName(logDirectory.TrimEnd('\\'));
            string current = WindowsIdentity.GetCurrent().User.Value;
            foreach (string path in new string[] { dataRoot, logDirectory, Path.GetDirectoryName(cacheFile), Path.GetDirectoryName(inventoryFile) })
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
        /// Write a security-relevant event (4001-4008) to the log SelfX: one field, a fixed text. See WriteEventRecord.
        /// </summary>
        void SecurityEvent(int id, EventLogEntryType type, string message)
        {
            WriteEventRecord(id, type, new string[] { message });
        }

        /// <summary>True for the operational events 4010-4014 (own rate limit), false for the security events.</summary>
        static bool IsOperationalEvent(int id)
        {
            return id >= EventActionStarted && id <= EventAppInstallFailed;
        }

        /// <summary>
        /// Make one insertion string safe for the event log: control characters and Unicode line or paragraph separators are
        /// removed, '%' becomes '_' (Event Viewer would read "%%n" as a reference to a parameter message), the text is trimmed
        /// and shortened to maxLength characters. An empty result becomes "-", so every field has a value and the field count
        /// never changes.
        /// </summary>
        static string CleanEventField(string value, int maxLength)
        {
            if (value == null) return EventNoValue;
            StringBuilder clean = new StringBuilder(Math.Min(value.Length, maxLength));
            foreach (char c in value)
            {
                if (clean.Length >= maxLength) break;
                if (char.IsControl(c) || c == '\u2028' || c == '\u2029' || c == '\u0085') continue;
                clean.Append(c == '%' ? '_' : c);
            }
            string text = clean.ToString().Trim();
            return text.Length == 0 ? EventNoValue : text;
        }

        /// <summary>Cleans all fields: the first (the message) up to MaxEventMessageLength, the others up to MaxEventFieldLength.</summary>
        static string[] CleanEventFields(string[] fields)
        {
            string[] clean = new string[fields == null ? 0 : fields.Length];
            for (int i = 0; i < clean.Length; i++)
            {
                clean[i] = CleanEventField(fields[i], i == 0 ? MaxEventMessageLength : MaxEventFieldLength);
            }
            return clean;
        }

        /// <summary>
        /// Write one entry to the log SelfX with its fields as separate insertion strings (EventInstance). Rate limit per event ID:
        /// security events at most MaxSecurityEventsPerWindow in SecurityEventWindow, operational events at most
        /// MaxOperationalEventsPerWindow in OperationalEventWindow; the number of entries that were left out is reported as
        /// event 4099 (fields: message, event ID, count) once the window is over.
        /// </summary>
        void WriteEventRecord(int id, EventLogEntryType type, string[] fields)
        {
            if (!securityEventsEnabled && eventsForTest == null) return;
            bool operational = IsOperationalEvent(id);
            int limit = operational ? MaxOperationalEventsPerWindow : MaxSecurityEventsPerWindow;
            TimeSpan length = operational ? OperationalEventWindow : SecurityEventWindow;
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
                DateTime now = eventClockForTest ?? DateTime.UtcNow;
                if (now - window.Start >= length)
                {
                    suppressedBefore = window.Suppressed;
                    window.Start = now;
                    window.Count = 0;
                    window.Suppressed = 0;
                }
                if (window.Count < limit)
                {
                    window.Count++;
                    write = true;
                }
                else
                {
                    window.Suppressed++;
                }
            }
            if (suppressedBefore > 0)
            {
                EmitEvent(EventSuppressed, EventLogEntryType.Warning, CleanEventFields(new string[] {
                    "Further events of one ID were not written (rate limit).",
                    id.ToString(CultureInfo.InvariantCulture),
                    suppressedBefore.ToString(CultureInfo.InvariantCulture) }));
            }
            if (write)
            {
                EmitEvent(id, type, CleanEventFields(fields));
            }
        }

        /// <summary>The sink of WriteEventRecord: the test list, otherwise the log SelfX. A failure is noted once in the service log.</summary>
        void EmitEvent(int id, EventLogEntryType type, string[] fields)
        {
            if (eventsForTest != null)
            {
                lock (eventLock) { eventsForTest.Add(new object[] { id, type, fields }); }
                return;
            }
            try
            {
                lock (eventLock)
                {
                    if (eventLog == null) eventLog = new EventLog(EventLogName, ".", EventSourceName);
                }
                eventLog.WriteEvent(new EventInstance(id, 0, type), fields);
            }
            catch (Exception ex)
            {
                // For example the source is still registered in the Application log (installation not finished): the service keeps
                // running; the problem is noted once (no loop: Log does not write events).
                if (!eventLogWriteFailed)
                {
                    eventLogWriteFailed = true;
                    Log("Warning: an entry could not be written to the event log " + EventLogName + " (" + ex.GetType().Name + "). Install SelfX again.");
                }
            }
        }

        /// <summary>The SID for the events 4010-4012: only with EventLog_CallerSid = True in Tool_Config.xml, otherwise "-".</summary>
        string EventCallerSid(string callerSid)
        {
            if (string.IsNullOrEmpty(callerSid)) return EventNoValue;
            string setting = ReadToolConfigValue(EventCallerSidSetting);
            if (setting == null || !string.Equals(setting.Trim(), "True", StringComparison.OrdinalIgnoreCase)) return EventNoValue;
            // Only a value in the form of a SID is written.
            return Regex.IsMatch(callerSid, @"^S-1-[0-9]+(-[0-9]+){1,14}$") ? callerSid : EventNoValue;
        }

        /// <summary>
        /// Fields of 4010 (started): message, script, caller SID, caller elevated (True/False).
        /// Fields of 4011 (succeeded) and 4012 (failed): message, script, result (ExitCode, Timeout, StartError), exit code
        /// ("-" without one), duration in whole seconds, caller SID.
        /// </summary>
        static string[] ActionEventFields(int id, string scriptName, string result, string exitCode, long durationSeconds, string sid, bool callerIsAdmin)
        {
            if (id == EventActionStarted)
            {
                return new string[] { "A SelfX action was started as SYSTEM.", scriptName, sid, callerIsAdmin ? "True" : "False" };
            }
            string message = id == EventActionSucceeded ? "A SelfX action as SYSTEM ended successfully." : "A SelfX action as SYSTEM failed.";
            return new string[] { message, scriptName, result, exitCode, durationSeconds.ToString(CultureInfo.InvariantCulture), sid };
        }

        /// <summary>
        /// Reads the JSON answer of HealthStatus.ps1 (array of rows with Id, Name, Status) and returns the rows that changed to
        /// Error since the last answer seen by this service process, as {Id, Name, previous status}. A row seen for the first time
        /// with Error counts as a change (previous status "-"), so the state after a restart is reported once. Only the fields Id,
        /// Name and Status are read, never Detail (it can name apps, files or accounts). The rows of a single check update only
        /// their own entries. Invalid JSON changes nothing.
        /// </summary>
        static List<string[]> FindHealthErrorChanges(string json, Dictionary<string, string> lastStatus)
        {
            List<string[]> changes = new List<string[]>();
            if (string.IsNullOrEmpty(json)) return changes;
            try
            {
                using (JsonDocument document = JsonDocument.Parse(json, new JsonDocumentOptions { MaxDepth = 8 }))
                {
                    JsonElement top = document.RootElement;
                    List<JsonElement> rows = new List<JsonElement>();
                    // ConvertTo-Json writes a single row as an object, several rows as an array.
                    if (top.ValueKind == JsonValueKind.Object) rows.Add(top);
                    else if (top.ValueKind == JsonValueKind.Array) { foreach (JsonElement item in top.EnumerateArray()) rows.Add(item); }
                    foreach (JsonElement row in rows)
                    {
                        if (row.ValueKind != JsonValueKind.Object) continue;
                        string id = JsonText(row, "Id");
                        string name = JsonText(row, "Name");
                        string status = JsonText(row, "Status");
                        if (id.Length == 0 || id == "Collection" || status.Length == 0) continue;
                        string key = id + "\n" + name;
                        string previous;
                        bool known = lastStatus.TryGetValue(key, out previous);
                        if (!known && lastStatus.Count >= MaxHealthRowsTracked) continue;
                        lastStatus[key] = status;
                        if (status == "Error" && (!known || previous != "Error"))
                        {
                            changes.Add(new string[] { id, name, known ? previous : EventNoValue });
                        }
                    }
                }
            }
            catch (JsonException) { }
            return changes;
        }

        /// <summary>A string property of a JSON object, or "" when it is missing or not a string.</summary>
        static string JsonText(JsonElement element, string name)
        {
            JsonElement value;
            if (element.TryGetProperty(name, out value) && value.ValueKind == JsonValueKind.String) return value.GetString() ?? "";
            return "";
        }

        /// <summary>Writes event 4013 (fields: message, check type, row name, previous status) for every row that changed to Error.</summary>
        void ReportHealthChanges(string json)
        {
            List<string[]> changes;
            lock (healthRowLock) { changes = FindHealthErrorChanges(json, healthRowStatus); }
            foreach (string[] change in changes)
            {
                WriteEventRecord(EventHealthError, EventLogEntryType.Warning, new string[] {
                    "A SelfX health check changed to the status Error.", change[0], change[1], change[2] });
            }
        }

        /// <summary>
        /// MaxSizeKB of the inventory file in bytes, or 0 when the inventory is off. Health_Config.xml, element Inventory: only
        /// Enabled="true" (case is ignored) switches it on; a missing element, any other value and an unreadable file mean off.
        /// MaxSizeKB outside 64-10240 uses the default 1024.
        /// </summary>
        long ReadInventoryMaxBytes()
        {
            try
            {
                string healthConfig = GetConfigFilePath("Health_Config.xml");
                if (!File.Exists(healthConfig)) return 0;
                XmlReaderSettings settings = new XmlReaderSettings();
                settings.DtdProcessing = DtdProcessing.Prohibit;
                settings.XmlResolver = null;
                XmlDocument document = new XmlDocument();
                document.XmlResolver = null;
                using (XmlReader reader = XmlReader.Create(healthConfig, settings)) { document.Load(reader); }
                XmlElement node = document.SelectSingleNode("/HealthConfig/Inventory") as XmlElement;
                if (node == null || !string.Equals(node.GetAttribute("Enabled").Trim(), "true", StringComparison.OrdinalIgnoreCase)) return 0;
                int kb;
                if (!int.TryParse(node.GetAttribute("MaxSizeKB"), NumberStyles.Integer, CultureInfo.InvariantCulture, out kb) || kb < MinInventoryMaxKB || kb > MaxInventoryMaxKB) kb = DefaultInventoryMaxKB;
                return kb * 1024L;
            }
            catch (Exception ex)
            {
                // Fail closed: settings that cannot be read write nothing.
                Log("Inventory settings not readable, the inventory file is not written (" + ex.GetType().Name + ").");
                return 0;
            }
        }

        /// <summary>Order of the status values for "worst of": OK, Unknown, Pending, Error; -1 for any other text.</summary>
        static int InventoryStatusRank(string status)
        {
            switch (status)
            {
                case "OK": return 0;
                case "Unknown": return 1;
                case "Pending": return 2;
                case "Error": return 3;
                default: return -1;
            }
        }

        static readonly string[] InventoryStatusNames = { "OK", "Unknown", "Pending", "Error" };

        /// <summary>
        /// One line of the inventory file from the JSON answer of HealthStatus.ps1, or null when the answer has no rows or is not JSON.
        /// Fixed schema (version 1), always all fields in this order: SchemaVersion, TimeGenerated (UTC, ISO 8601), Mode (Client or
        /// TerminalServer), Overall (worst status of all rows; a Collection row counts as Error), one field per check type of
        /// InventoryTypes with the worst status of its rows ("" = not checked), FailedApps (app ID:error code, app ID:Stalled or
        /// app ID:- without a valid code; separated by ";", at most MaxInventoryApps). Only Id, Status and the list Apps (Id, Problem,
        /// Code) are read, never Name or Detail: no user name, no path and no app name reaches the file. A status other than OK, Pending,
        /// Error or Unknown counts as Unknown; an app ID that is not a GUID and an unknown problem are left out.
        /// </summary>
        static string BuildInventoryLine(string json, bool terminalServer, DateTime utcNow)
        {
            if (string.IsNullOrEmpty(json)) return null;
            Dictionary<string, int> worst = new Dictionary<string, int>(StringComparer.Ordinal);
            List<string> apps = new List<string>();
            int overall = -1;
            try
            {
                using (JsonDocument document = JsonDocument.Parse(json, new JsonDocumentOptions { MaxDepth = 8 }))
                {
                    JsonElement top = document.RootElement;
                    List<JsonElement> rows = new List<JsonElement>();
                    // ConvertTo-Json writes a single row as an object, several rows as an array.
                    if (top.ValueKind == JsonValueKind.Object) rows.Add(top);
                    else if (top.ValueKind == JsonValueKind.Array) { foreach (JsonElement item in top.EnumerateArray()) rows.Add(item); }
                    else return null;
                    foreach (JsonElement row in rows)
                    {
                        if (row.ValueKind != JsonValueKind.Object) continue;
                        string id = JsonText(row, "Id");
                        int rank = InventoryStatusRank(JsonText(row, "Status"));
                        if (rank < 0) rank = 1;
                        if (id == "Collection") rank = 3;
                        if (rank > overall) overall = rank;
                        if (Array.IndexOf(InventoryTypes, id) < 0) continue;
                        int known;
                        if (!worst.TryGetValue(id, out known) || rank > known) worst[id] = rank;
                        JsonElement list;
                        if (id != "Applications" || !row.TryGetProperty("Apps", out list)) continue;
                        List<JsonElement> entries = new List<JsonElement>();
                        if (list.ValueKind == JsonValueKind.Object) entries.Add(list);
                        else if (list.ValueKind == JsonValueKind.Array) { foreach (JsonElement item in list.EnumerateArray()) entries.Add(item); }
                        foreach (JsonElement entry in entries)
                        {
                            if (apps.Count >= MaxInventoryApps) break;
                            if (entry.ValueKind != JsonValueKind.Object) continue;
                            string appId = JsonText(entry, "Id");
                            if (!AppIdPattern.IsMatch(appId)) continue;
                            string problem = JsonText(entry, "Problem");
                            string value;
                            if (problem == "Stalled") value = "Stalled";
                            else if (problem == "Failed")
                            {
                                string code = JsonText(entry, "Code");
                                value = InventoryAppCodePattern.IsMatch(code) ? code : EventNoValue;
                            }
                            else continue;
                            string text = appId + ":" + value;
                            if (!apps.Contains(text)) apps.Add(text);
                        }
                    }
                }
            }
            catch (JsonException) { return null; }
            if (overall < 0) return null;
            using (MemoryStream stream = new MemoryStream())
            {
                using (Utf8JsonWriter writer = new Utf8JsonWriter(stream))
                {
                    writer.WriteStartObject();
                    writer.WriteNumber("SchemaVersion", InventorySchemaVersion);
                    writer.WriteString("TimeGenerated", utcNow.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture));
                    writer.WriteString("Mode", terminalServer ? "TerminalServer" : "Client");
                    writer.WriteString("Overall", InventoryStatusNames[overall]);
                    foreach (string type in InventoryTypes)
                    {
                        int rank;
                        writer.WriteString(type, worst.TryGetValue(type, out rank) ? InventoryStatusNames[rank] : "");
                    }
                    writer.WriteString("FailedApps", string.Join(";", apps));
                    writer.WriteEndObject();
                }
                return Encoding.UTF8.GetString(stream.ToArray());
            }
        }

        /// <summary>
        /// Appends one line (BuildInventoryLine) to ProgramData\SelfX\Inventory\SelfX.Inventory.json after a full health run, when
        /// Health_Config.xml switches the inventory on. Nothing is written while the data folder is not safe or the device status is
        /// off (mode TerminalServer with TerminalServer_Health Off). The folder inherits the rights of ProgramData\SelfX (SYSTEM and
        /// administrators), like the cache. A folder or file that is a link is not used. When the file would grow above MaxSizeKB,
        /// it is renamed to SelfX.Inventory.json.old (an older .old is deleted first): the name does not match the file pattern
        /// SelfX.Inventory.json of a collector, so no line is read twice. UTF-8 without byte order mark, one line per run.
        /// </summary>
        void WriteInventory(string json)
        {
            long maxBytes = ReadInventoryMaxBytes();
            if (maxBytes <= 0 || !dataFolderSafe) return;
            if (ReadHealthAccess() == HealthAccess.Off) return;
            string line = BuildInventoryLine(json, IsTerminalServer(), DateTime.UtcNow);
            if (line == null)
            {
                Log("Inventory file: the health answer has no rows; no line written.");
                return;
            }
            byte[] bytes = new UTF8Encoding(false).GetBytes(line + "\n");
            try
            {
                lock (inventoryLock)
                {
                    string folder = Path.GetDirectoryName(inventoryFile);
                    Directory.CreateDirectory(folder);
                    if ((File.GetAttributes(folder) & FileAttributes.ReparsePoint) != 0)
                    {
                        Log("Inventory folder is a link; the inventory file is not written.");
                        return;
                    }
                    FileInfo info = new FileInfo(inventoryFile);
                    if (info.Exists)
                    {
                        if ((info.Attributes & FileAttributes.ReparsePoint) != 0)
                        {
                            Log("Inventory file is a link; it is not written.");
                            return;
                        }
                        if (info.Length + bytes.Length > maxBytes)
                        {
                            string old = inventoryFile + ".old";
                            if (File.Exists(old)) File.Delete(old);
                            File.Move(inventoryFile, old);
                        }
                    }
                    using (FileStream stream = new FileStream(inventoryFile, FileMode.Append, FileAccess.Write, FileShare.Read))
                    {
                        stream.Write(bytes, 0, bytes.Length);
                    }
                }
            }
            catch (Exception ex)
            {
                Log("Inventory file not written (" + ex.GetType().Name + ").");
            }
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
    /// Delete folder trees as SYSTEM without following junctions or symbolic links and without a time window
    /// between check and delete (installer helper: /removetree: and /cleandata: of SelfXService.exe).
    /// Every entry is opened once with FILE_FLAG_OPEN_REPARSE_POINT (a link is opened itself, never its target), is
    /// judged on that handle (link, folder, owner) and is deleted through the same handle. A folder is held open
    /// (no share-delete) while its content is processed, so it cannot be renamed or replaced meanwhile.
    /// </summary>
    public static class SafeTree
    {
        const uint DELETE = 0x00010000;
        const uint READ_CONTROL = 0x00020000;
        const uint FILE_READ_ATTRIBUTES = 0x00000080;
        const uint SHARE_READ_WRITE = 0x00000003;
        const uint OPEN_EXISTING = 3;
        const uint FILE_FLAG_BACKUP_SEMANTICS = 0x02000000;
        const uint FILE_FLAG_OPEN_REPARSE_POINT = 0x00200000;
        const uint FILE_ATTRIBUTE_DIRECTORY = 0x10;
        const uint FILE_ATTRIBUTE_REPARSE_POINT = 0x400;
        const int FileBasicInfo = 0;
        const int FileStandardInfo = 1;
        const int FileAttributeTagInfo = 9;
        const int FileDispositionInfoEx = 21;
        // /cleanold: limits. The age is checked on the handle (newest of creation, write and change time); the depth limit
        // only protects the stack against a deeply nested folder that a user created in Windows\Temp.
        const int CleanOldMinDays = 1;
        const int CleanOldMaxDays = 365;
        const int CleanOldMaxDepth = 64;
        const uint DISPOSITION_DELETE_POSIX_IGNORE_READONLY = 0x13;
        const int ERROR_FILE_NOT_FOUND = 2;
        const int ERROR_PATH_NOT_FOUND = 3;
        const int ERROR_DIR_NOT_EMPTY = 145;
        // Reported for an entry whose handle names another path than expected (a parent folder became a link after it was opened).
        const int ERROR_CANT_RESOLVE_FILENAME = 1921;

        [StructLayout(LayoutKind.Sequential)]
        struct FILE_ATTRIBUTE_TAG_INFO { public uint FileAttributes; public uint ReparseTag; }

        [StructLayout(LayoutKind.Sequential)]
        struct FILE_DISPOSITION_INFO_EX { public uint Flags; }

        // FILE_BASIC_INFO (winbase.h): times as FILETIME (UTC, 100-ns intervals since 1601).
        [StructLayout(LayoutKind.Sequential)]
        struct FILE_BASIC_INFO { public long CreationTime; public long LastAccessTime; public long LastWriteTime; public long ChangeTime; public uint FileAttributes; }

        // FILE_STANDARD_INFO (winbase.h).
        [StructLayout(LayoutKind.Sequential)]
        struct FILE_STANDARD_INFO { public long AllocationSize; public long EndOfFile; public uint NumberOfLinks; public byte DeletePending; public byte Directory; }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool GetFileInformationByHandleEx(SafeFileHandle handle, int infoClass, out FILE_ATTRIBUTE_TAG_INFO info, uint size);

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool GetFileInformationByHandleEx(SafeFileHandle handle, int infoClass, out FILE_BASIC_INFO info, uint size);

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool GetFileInformationByHandleEx(SafeFileHandle handle, int infoClass, out FILE_STANDARD_INFO info, uint size);

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool SetFileInformationByHandle(SafeFileHandle handle, int infoClass, ref FILE_DISPOSITION_INFO_EX info, uint size);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern uint GetFinalPathNameByHandleW(SafeFileHandle handle, StringBuilder path, uint size, uint flags);

        [DllImport("advapi32.dll")]
        static extern uint GetSecurityInfo(SafeFileHandle handle, int objectType, uint info, out IntPtr owner, out IntPtr group, out IntPtr dacl, out IntPtr sacl, out IntPtr descriptor);

        [DllImport("kernel32.dll")]
        static extern IntPtr LocalFree(IntPtr memory);

        sealed class Result
        {
            public int Failed;
            public readonly List<string> Messages = new List<string>();
            public void Fail(string path, int error)
            {
                Failed++;
                if (Messages.Count < 20) Messages.Add("SELFX-SAFEDELETE-ERROR: " + path + " (Windows error " + error + ")");
            }
        }

        static string Extended(string fullPath)
        {
            return fullPath.StartsWith(@"\\?\", StringComparison.Ordinal) ? fullPath : @"\\?\" + fullPath;
        }

        static SafeFileHandle Open(string path, uint access)
        {
            return CreateFileW(Extended(path), access, SHARE_READ_WRITE, IntPtr.Zero, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, IntPtr.Zero);
        }

        static bool GetAttributes(SafeFileHandle handle, out uint attributes)
        {
            FILE_ATTRIBUTE_TAG_INFO info;
            attributes = 0;
            if (!GetFileInformationByHandleEx(handle, FileAttributeTagInfo, out info, (uint)Marshal.SizeOf(typeof(FILE_ATTRIBUTE_TAG_INFO)))) return false;
            attributes = info.FileAttributes;
            return true;
        }

        static string GetOwnerSid(SafeFileHandle handle)
        {
            IntPtr owner, group, dacl, sacl, descriptor;
            if (GetSecurityInfo(handle, 1, 1, out owner, out group, out dacl, out sacl, out descriptor) != 0) return null;
            try { return new SecurityIdentifier(owner).Value; }
            finally { if (descriptor != IntPtr.Zero) LocalFree(descriptor); }
        }

        // The handle must name exactly the expected path: a link in a parent folder would show a different final path.
        static bool PathMatches(SafeFileHandle handle, string fullPath)
        {
            StringBuilder builder = new StringBuilder(1024);
            uint length = GetFinalPathNameByHandleW(handle, builder, (uint)builder.Capacity, 0);
            if (length == 0 || length >= builder.Capacity) return false;
            return string.Equals(builder.ToString().TrimEnd('\\'), Extended(fullPath).TrimEnd('\\'), StringComparison.OrdinalIgnoreCase);
        }

        // Opens an entry below an open folder by its path and keeps the handle only when it names exactly that path. The owner of
        // an empty folder can turn it into a junction in place while the folder is open here (the open handle blocks renaming and
        // deleting, not FSCTL_SET_REPARSE_POINT), and FILE_FLAG_OPEN_REPARSE_POINT only covers the last part of a path: the
        // entries listed or opened through that folder then lie elsewhere. Such an entry is never deleted and never entered.
        static SafeFileHandle OpenExact(string path, uint access, out bool redirected)
        {
            redirected = false;
            SafeFileHandle handle = Open(path, access);
            if (handle.IsInvalid || PathMatches(handle, path)) return handle;
            redirected = true;
            handle.Dispose();
            return new SafeFileHandle(IntPtr.Zero, false);
        }

        static bool DeleteByHandle(SafeFileHandle handle, out int error)
        {
            FILE_DISPOSITION_INFO_EX info = new FILE_DISPOSITION_INFO_EX();
            info.Flags = DISPOSITION_DELETE_POSIX_IGNORE_READONLY;
            error = 0;
            if (SetFileInformationByHandle(handle, FileDispositionInfoEx, ref info, (uint)Marshal.SizeOf(typeof(FILE_DISPOSITION_INFO_EX)))) return true;
            error = Marshal.GetLastWin32Error();
            return false;
        }

        static List<string> Children(string folder)
        {
            // Without the \\?\ prefix, which Extended() adds again for every call.
            List<string> list = new List<string>();
            foreach (string entry in Directory.EnumerateFileSystemEntries(Extended(folder)))
            {
                list.Add(entry.StartsWith(@"\\?\", StringComparison.Ordinal) ? entry.Substring(4) : entry);
            }
            return list;
        }

        // Deletes the object behind the open handle: a link or file directly, a folder after its content.
        static void RemoveOpen(SafeFileHandle handle, string path, Result result)
        {
            uint attributes;
            int error;
            if (!GetAttributes(handle, out attributes)) { result.Fail(path, Marshal.GetLastWin32Error()); return; }
            bool isFolder = (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0 && (attributes & FILE_ATTRIBUTE_REPARSE_POINT) == 0;
            for (int attempt = 0; attempt < 5; attempt++)
            {
                if (isFolder)
                {
                    List<string> children;
                    try { children = Children(path); }
                    catch (Exception) { result.Fail(path, 0); return; }
                    foreach (string child in children) RemoveEntry(child, result);
                }
                if (DeleteByHandle(handle, out error)) return;
                // Someone added entries meanwhile: go through the folder again (bounded).
                if (!(isFolder && error == ERROR_DIR_NOT_EMPTY && result.Failed == 0)) { result.Fail(path, error); return; }
            }
            result.Fail(path, ERROR_DIR_NOT_EMPTY);
        }

        static void RemoveEntry(string path, Result result)
        {
            bool redirected;
            using (SafeFileHandle handle = OpenExact(path, DELETE | FILE_READ_ATTRIBUTES, out redirected))
            {
                if (redirected) { result.Fail(path, ERROR_CANT_RESOLVE_FILENAME); return; }
                if (handle.IsInvalid)
                {
                    int error = Marshal.GetLastWin32Error();
                    if (error != ERROR_FILE_NOT_FOUND && error != ERROR_PATH_NOT_FOUND) result.Fail(path, error);
                    return;
                }
                RemoveOpen(handle, path, result);
            }
        }

        // Folders and files that belong to a trusted owner are kept; links and entries of other owners are deleted.
        static void CleanFolder(string folder, HashSet<string> trusted, string skipFolder, Result result)
        {
            List<string> children;
            try { children = Children(folder); }
            catch (Exception) { result.Fail(folder, 0); return; }
            foreach (string child in children)
            {
                bool redirected;
                using (SafeFileHandle handle = OpenExact(child, DELETE | READ_CONTROL | FILE_READ_ATTRIBUTES, out redirected))
                {
                    if (redirected) { result.Fail(child, ERROR_CANT_RESOLVE_FILENAME); continue; }
                    if (handle.IsInvalid)
                    {
                        int error = Marshal.GetLastWin32Error();
                        if (error != ERROR_FILE_NOT_FOUND && error != ERROR_PATH_NOT_FOUND) result.Fail(child, error);
                        continue;
                    }
                    uint attributes;
                    if (!GetAttributes(handle, out attributes)) { result.Fail(child, Marshal.GetLastWin32Error()); continue; }
                    string owner = GetOwnerSid(handle);
                    bool isLink = (attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0;
                    if (isLink || owner == null || !trusted.Contains(owner)) { RemoveOpen(handle, child, result); continue; }
                    if ((attributes & FILE_ATTRIBUTE_DIRECTORY) != 0 && !string.Equals(child.TrimEnd('\\'), skipFolder, StringComparison.OrdinalIgnoreCase))
                    {
                        CleanFolder(child, trusted, skipFolder, result);
                    }
                }
            }
        }

        sealed class OldResult
        {
            public int Removed;
            public int Kept;
            public long Bytes;
        }

        // Newest of creation, write and change time (UTC): a file copied or renamed into the folder counts as new.
        static bool GetNewestTime(SafeFileHandle handle, out DateTime newest, out uint attributes)
        {
            FILE_BASIC_INFO info;
            newest = DateTime.MaxValue;
            attributes = 0;
            if (!GetFileInformationByHandleEx(handle, FileBasicInfo, out info, (uint)Marshal.SizeOf(typeof(FILE_BASIC_INFO)))) return false;
            long ticks = Math.Max(info.CreationTime, Math.Max(info.LastWriteTime, info.ChangeTime));
            if (ticks < 0) return false;
            newest = DateTime.FromFileTimeUtc(ticks);
            attributes = info.FileAttributes;
            return true;
        }

        // Size of a file with one name only; a hard link frees nothing when it is deleted.
        static long FreedBytes(SafeFileHandle handle)
        {
            FILE_STANDARD_INFO info;
            if (!GetFileInformationByHandleEx(handle, FileStandardInfo, out info, (uint)Marshal.SizeOf(typeof(FILE_STANDARD_INFO)))) return 0;
            return info.NumberOfLinks == 1 && info.EndOfFile > 0 ? info.EndOfFile : 0;
        }

        // Deletes every entry below the (open) folder whose newest time is before the cutoff. A link is deleted itself and never
        // followed; a real folder is held open while its content is processed and is deleted afterwards when it is old and empty.
        // An entry that is in use or denied is kept and counted: that is normal in Windows\Temp and not an error.
        static void CleanOld(string folder, DateTime cutoff, int depth, OldResult result)
        {
            if (depth > CleanOldMaxDepth) { result.Kept++; return; }
            List<string> children;
            try { children = Children(folder); }
            catch (Exception) { result.Kept++; return; }
            foreach (string child in children)
            {
                bool redirected;
                using (SafeFileHandle handle = OpenExact(child, DELETE | FILE_READ_ATTRIBUTES, out redirected))
                {
                    if (redirected) { result.Kept++; continue; }
                    if (handle.IsInvalid)
                    {
                        int error = Marshal.GetLastWin32Error();
                        if (error != ERROR_FILE_NOT_FOUND && error != ERROR_PATH_NOT_FOUND) result.Kept++;
                        continue;
                    }
                    DateTime newest;
                    uint attributes;
                    if (!GetNewestTime(handle, out newest, out attributes)) { result.Kept++; continue; }
                    bool isLink = (attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0;
                    bool isFolder = !isLink && (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
                    bool old = newest < cutoff;
                    if (isFolder)
                    {
                        CleanOld(child, cutoff, depth + 1, result);
                        if (!old) continue;
                        // Fails with ERROR_DIR_NOT_EMPTY when a newer entry is left: the folder then stays.
                        int folderError;
                        if (DeleteByHandle(handle, out folderError)) result.Removed++;
                        else result.Kept++;
                        continue;
                    }
                    if (!old) continue;
                    long size = isLink ? 0 : FreedBytes(handle);
                    int fileError;
                    if (DeleteByHandle(handle, out fileError)) { result.Removed++; result.Bytes += size; }
                    else result.Kept++;
                }
            }
        }

        /// <summary>The fixed folders of /cleanold:, resolved through known folders of Windows (never from an argument, an
        /// environment variable or the registry). Content\Incoming, Content\Staging and IMECache: Microsoft Learn, "Understanding
        /// the flow behind deployment, delivery, and processing of a Win32 application through Intune". null for an unknown key.</summary>
        internal static string CleanOldRoot(string key)
        {
            string windows = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
            string ime = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Microsoft Intune Management Extension", "Content");
            switch (key)
            {
                case "WindowsTemp": return string.IsNullOrEmpty(windows) ? null : Path.Combine(windows, "Temp");
                case "ImeIncoming": return Path.Combine(ime, "Incoming");
                case "ImeStaging": return Path.Combine(ime, "Staging");
                case "ImeCache": return string.IsNullOrEmpty(windows) ? null : Path.Combine(windows, "IMECache");
                default: return null;
            }
        }

        /// <summary>/cleanold:&lt;key&gt; /minage:&lt;days&gt;: deletes entries older than the given number of days below one fixed
        /// folder (CleanOldRoot). /cleanoldpath:&lt;absolute path&gt; does the same below any local folder for the tests and is
        /// refused when the process runs as SYSTEM, so the service account only ever cleans the fixed folders. A missing folder
        /// is not an error. Prints SELFX-CLEANOLD-OK removed=&lt;n&gt; kept=&lt;n&gt; bytes=&lt;n&gt;. Exit 0 = done (entries in use are
        /// kept), 1 = the folder is a link, lies behind a link or is not a folder, 2 = invalid arguments.</summary>
        public static int RunCleanOld(string key, string testPath, string minAge)
        {
            int days;
            if (string.IsNullOrEmpty(minAge) || !Regex.IsMatch(minAge, @"^[0-9]{1,3}\z") || !int.TryParse(minAge, NumberStyles.None, CultureInfo.InvariantCulture, out days) ||
                days < CleanOldMinDays || days > CleanOldMaxDays)
            {
                Console.WriteLine("SELFX-CLEANOLD-ERROR: /minage: must be a number of days from " + CleanOldMinDays + " to " + CleanOldMaxDays + ".");
                return 2;
            }
            string root;
            if (testPath != null)
            {
                if (key != null) { Console.WriteLine("SELFX-CLEANOLD-ERROR: use either /cleanold: or /cleanoldpath:."); return 2; }
                using (WindowsIdentity identity = WindowsIdentity.GetCurrent())
                {
                    if (identity.IsSystem) { Console.WriteLine("SELFX-CLEANOLD-ERROR: /cleanoldpath: is refused for SYSTEM."); return 2; }
                }
                root = FullPathOrNull(testPath);
            }
            else root = key == null ? null : CleanOldRoot(key);
            if (root == null) { Console.WriteLine("SELFX-CLEANOLD-ERROR: unknown folder."); return 2; }
            root = Path.GetFullPath(root).TrimEnd('\\');

            OldResult result = new OldResult();
            try
            {
                using (SafeFileHandle handle = Open(root, FILE_READ_ATTRIBUTES))
                {
                    uint attributes;
                    if (handle.IsInvalid)
                    {
                        int error = Marshal.GetLastWin32Error();
                        if (error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND) { Console.WriteLine("SELFX-CLEANOLD-OK removed=0 kept=0 bytes=0"); return 0; }
                        Console.WriteLine("SELFX-CLEANOLD-ERROR: the folder cannot be opened (Windows error " + error + ").");
                        return 1;
                    }
                    if (!PathMatches(handle, root)) { Console.WriteLine("SELFX-CLEANOLD-ERROR: a link lies in the path of the folder."); return 1; }
                    if (!GetAttributes(handle, out attributes) || (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0 || (attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0)
                    {
                        Console.WriteLine("SELFX-CLEANOLD-ERROR: the folder is not a real folder.");
                        return 1;
                    }
                    // The root stays open (no share-delete) until the end, so it cannot be renamed or replaced by a link meanwhile.
                    CleanOld(root, DateTime.UtcNow.AddDays(-days), 0, result);
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine("SELFX-CLEANOLD-ERROR: " + ex.GetType().Name);
                return 1;
            }
            Console.WriteLine(string.Format(CultureInfo.InvariantCulture, "SELFX-CLEANOLD-OK removed={0} kept={1} bytes={2}", result.Removed, result.Kept, result.Bytes));
            return 0;
        }

        static string FullPathOrNull(string path)
        {
            if (string.IsNullOrWhiteSpace(path) || path.StartsWith(@"\\", StringComparison.Ordinal) || !Path.IsPathRooted(path)) return null;
            string full = Path.GetFullPath(path).TrimEnd('\\');
            return full.Length > 3 ? full : null;
        }

        /// <summary>mode "removetree": delete the path itself and everything below it; mode "cleandata": delete links and
        /// foreign-owned entries below the path (the path itself is kept). Returns 0 only when everything worked.</summary>
        public static int Run(string mode, string path, string trustedSids, string skipRelative)
        {
            string full = FullPathOrNull(path);
            if (full == null) { Console.WriteLine("SELFX-SAFEDELETE-ERROR: the path must be an absolute local path."); return 2; }
            Result result = new Result();
            try
            {
                if (mode == "removetree")
                {
                    using (SafeFileHandle handle = Open(full, DELETE | FILE_READ_ATTRIBUTES))
                    {
                        if (handle.IsInvalid)
                        {
                            int error = Marshal.GetLastWin32Error();
                            if (error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND) { Console.WriteLine("SELFX-SAFEDELETE-OK"); return 0; }
                            result.Fail(full, error);
                        }
                        else if (!PathMatches(handle, full)) { Console.WriteLine("SELFX-SAFEDELETE-ERROR: a link lies in the path of " + full); return 1; }
                        else RemoveOpen(handle, full, result);
                    }
                }
                else
                {
                    HashSet<string> trusted = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                    foreach (string sid in (trustedSids ?? "").Split(new char[] { ';' }, StringSplitOptions.RemoveEmptyEntries))
                    {
                        if (!Regex.IsMatch(sid, @"^S-1-[0-9]+(-[0-9]+)+\z")) { Console.WriteLine("SELFX-SAFEDELETE-ERROR: invalid SID in /trusted:."); return 2; }
                        trusted.Add(sid);
                    }
                    string skip = null;
                    if (!string.IsNullOrEmpty(skipRelative))
                    {
                        if (skipRelative.Contains("..") || Path.IsPathRooted(skipRelative)) { Console.WriteLine("SELFX-SAFEDELETE-ERROR: invalid /skip:."); return 2; }
                        skip = Path.GetFullPath(Path.Combine(full, skipRelative)).TrimEnd('\\');
                    }
                    using (SafeFileHandle handle = Open(full, FILE_READ_ATTRIBUTES))
                    {
                        uint attributes;
                        if (handle.IsInvalid) { result.Fail(full, Marshal.GetLastWin32Error()); }
                        else if (!PathMatches(handle, full)) { Console.WriteLine("SELFX-SAFEDELETE-ERROR: a link lies in the path of " + full); return 1; }
                        else if (!GetAttributes(handle, out attributes) || (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0 || (attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0)
                        {
                            Console.WriteLine("SELFX-SAFEDELETE-ERROR: " + full + " is not a real folder.");
                            return 1;
                        }
                        else CleanFolder(full, trusted, skip, result);
                    }
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine("SELFX-SAFEDELETE-ERROR: " + ex.GetType().Name);
                return 1;
            }
            foreach (string message in result.Messages) Console.WriteLine(message);
            if (result.Failed > 0) { Console.WriteLine("SELFX-SAFEDELETE-FAILED: " + result.Failed); return 1; }
            Console.WriteLine("SELFX-SAFEDELETE-OK");
            return 0;
        }
    }

    /// <summary>
    /// Authenticode checks of Windows (WinVerifyTrust) for the trust mode Signature. Every check works on a handle that the
    /// caller keeps open, never shows a window and never asks the network: revocation is checked for the chain without the
    /// root from the local cache only (WTD_CACHE_ONLY_URL_RETRIEVAL), so a device without a network does not wait. A revocation
    /// list that is not in the cache does not make a signature invalid (the rule of Windows for Authenticode); a certificate that
    /// is known as revoked does. The thumbprint (SHA1) of the signer is read from the state data of the same call.
    /// </summary>
    internal static class SelfXTrust
    {
        internal sealed class Verdict
        {
            public string Reason = "Error";
            public string Thumbprint = "";
        }

        static readonly Guid GenericVerifyV2 = new Guid("00AAC56B-CD44-11d0-8CC2-00C04FC295EE");
        const uint WTD_UI_NONE = 2;
        const uint WTD_REVOKE_WHOLECHAIN = 1;
        const uint WTD_CHOICE_FILE = 1;
        const uint WTD_CHOICE_CATALOG = 2;
        const uint WTD_STATEACTION_VERIFY = 1;
        const uint WTD_STATEACTION_CLOSE = 2;
        const uint WTD_REVOCATION_CHECK_CHAIN_EXCLUDE_ROOT = 0x80;
        const uint WTD_CACHE_ONLY_URL_RETRIEVAL = 0x1000;
        const uint WTD_DISABLE_MD2_MD4 = 0x2000;

        [StructLayout(LayoutKind.Sequential)]
        struct WINTRUST_FILE_INFO
        {
            public uint cbStruct;
            public IntPtr pcwszFilePath;
            public IntPtr hFile;
            public IntPtr pgKnownSubject;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct WINTRUST_CATALOG_INFO
        {
            public uint cbStruct;
            public uint dwCatalogVersion;
            public IntPtr pcwszCatalogFilePath;
            public IntPtr pcwszMemberTag;
            public IntPtr pcwszMemberFilePath;
            public IntPtr hMemberFile;
            public IntPtr pbCalculatedFileHash;
            public uint cbCalculatedFileHash;
            public IntPtr pcCatalogContext;
            public IntPtr hCatAdmin;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct WINTRUST_DATA
        {
            public uint cbStruct;
            public IntPtr pPolicyCallbackData;
            public IntPtr pSIPClientData;
            public uint dwUIChoice;
            public uint fdwRevocationChecks;
            public uint dwUnionChoice;
            public IntPtr pInfo;
            public uint dwStateAction;
            public IntPtr hWVTStateData;
            public IntPtr pwszURLReference;
            public uint dwProvFlags;
            public uint dwUIContext;
            public IntPtr pSignatureSettings;
        }

        [DllImport("wintrust.dll", ExactSpelling = true)]
        static extern int WinVerifyTrust(IntPtr window, ref Guid action, ref WINTRUST_DATA data);
        [DllImport("wintrust.dll", ExactSpelling = true)]
        static extern IntPtr WTHelperProvDataFromStateData(IntPtr stateData);
        [DllImport("wintrust.dll", ExactSpelling = true)]
        static extern IntPtr WTHelperGetProvSignerFromChain(IntPtr providerData, uint signerIndex, [MarshalAs(UnmanagedType.Bool)] bool counterSigner, uint counterSignerIndex);
        [DllImport("wintrust.dll", ExactSpelling = true)]
        static extern IntPtr WTHelperGetProvCertFromChain(IntPtr signer, uint certificateIndex);
        [DllImport("wintrust.dll", ExactSpelling = true, SetLastError = true, CharSet = CharSet.Unicode)]
        [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool CryptCATAdminAcquireContext2(out IntPtr catAdmin, IntPtr subsystem, string hashAlgorithm, IntPtr strongHashPolicy, uint flags);
        [DllImport("wintrust.dll", ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool CryptCATAdminCalcHashFromFileHandle2(IntPtr catAdmin, SafeFileHandle file, ref uint hashSize, byte[] hash, uint flags);
        [DllImport("wintrust.dll", ExactSpelling = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool CryptCATAdminReleaseContext(IntPtr catAdmin, uint flags);

        /// <summary>Fixed text for a result of WinVerifyTrust (for the log; no text of the system is passed on).</summary>
        static string ReasonOf(int code)
        {
            switch (unchecked((uint)code))
            {
                case 0: return "Ok";
                case 0x800B0100: return "NoSignature";
                case 0x80096010: return "BadDigest";
                case 0x800B0109: return "UntrustedRoot";
                case 0x800B010A: return "Chaining";
                case 0x800B0101: return "Expired";
                case 0x800B010C: return "Revoked";
                case 0x800B0111: return "ExplicitDistrust";
                case 0x800B0004: return "SubjectNotTrusted";
                case 0x800B0003: return "SubjectFormUnknown";
                case 0x800B0001: return "ProviderUnknown";
                case 0x80092026: return "SecuritySettings";
                default: return "Error 0x" + code.ToString("X8", CultureInfo.InvariantCulture);
            }
        }

        /// <summary>WinVerifyTrust with the state data kept, the thumbprint of the signer read, the state data closed.</summary>
        static void Verify(uint choice, IntPtr info, Verdict verdict)
        {
            Guid action = GenericVerifyV2;
            WINTRUST_DATA data = new WINTRUST_DATA();
            data.cbStruct = (uint)Marshal.SizeOf(typeof(WINTRUST_DATA));
            data.dwUIChoice = WTD_UI_NONE;
            data.fdwRevocationChecks = WTD_REVOKE_WHOLECHAIN;
            data.dwUnionChoice = choice;
            data.pInfo = info;
            data.dwStateAction = WTD_STATEACTION_VERIFY;
            data.dwProvFlags = WTD_REVOCATION_CHECK_CHAIN_EXCLUDE_ROOT | WTD_CACHE_ONLY_URL_RETRIEVAL | WTD_DISABLE_MD2_MD4;
            IntPtr noWindow = new IntPtr(-1);
            try
            {
                int code = WinVerifyTrust(noWindow, ref action, ref data);
                string thumbprint = "";
                if (data.hWVTStateData != IntPtr.Zero)
                {
                    IntPtr provider = WTHelperProvDataFromStateData(data.hWVTStateData);
                    IntPtr signer = provider == IntPtr.Zero ? IntPtr.Zero : WTHelperGetProvSignerFromChain(provider, 0, false, 0);
                    IntPtr providerCert = signer == IntPtr.Zero ? IntPtr.Zero : WTHelperGetProvCertFromChain(signer, 0);
                    if (providerCert != IntPtr.Zero)
                    {
                        // CRYPT_PROVIDER_CERT: DWORD cbStruct, then (aligned to the pointer size) PCCERT_CONTEXT pCert.
                        IntPtr context = Marshal.ReadIntPtr(providerCert, IntPtr.Size);
                        if (context != IntPtr.Zero)
                        {
                            using (X509Certificate2 certificate = new X509Certificate2(context)) { thumbprint = certificate.Thumbprint.ToUpperInvariant(); }
                        }
                    }
                }
                verdict.Thumbprint = thumbprint;
                verdict.Reason = ReasonOf(code);
            }
            finally
            {
                data.dwStateAction = WTD_STATEACTION_CLOSE;
                WinVerifyTrust(noWindow, ref action, ref data);
            }
        }

        /// <summary>
        /// Embedded signature of the file behind the open handle. The path names the file type (Windows chooses the reader for
        /// .ps1 or .dll by the extension); the content is the one of the handle, which the caller keeps open without write and
        /// delete sharing. Never throws: anything unexpected is the reason "Error".
        /// </summary>
        internal static Verdict VerifyEmbedded(string path, FileStream pinned)
        {
            Verdict verdict = new Verdict();
            IntPtr pathText = IntPtr.Zero, info = IntPtr.Zero;
            try
            {
                pinned.Position = 0;
                pathText = Marshal.StringToHGlobalUni(path);
                info = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(WINTRUST_FILE_INFO)));
                WINTRUST_FILE_INFO file = new WINTRUST_FILE_INFO();
                file.cbStruct = (uint)Marshal.SizeOf(typeof(WINTRUST_FILE_INFO));
                file.pcwszFilePath = pathText;
                file.hFile = pinned.SafeFileHandle.DangerousGetHandle();
                Marshal.StructureToPtr(file, info, false);
                Verify(WTD_CHOICE_FILE, info, verdict);
            }
            catch (Exception)
            {
                verdict.Reason = "Error";
                verdict.Thumbprint = "";
            }
            finally
            {
                if (info != IntPtr.Zero) Marshal.FreeHGlobal(info);
                if (pathText != IntPtr.Zero) Marshal.FreeHGlobal(pathText);
                GC.KeepAlive(pinned);
            }
            return verdict;
        }

        /// <summary>
        /// The file behind the open handle is a member of the given catalog, and the catalog is signed: the catalog hash of the
        /// handle (CryptCATAdminCalcHashFromFileHandle2, SHA256; for XML and JSON the SHA256 of the bytes) is looked up in the
        /// catalog (WINTRUST_CATALOG_INFO with the calculated hash; the member tag is the hash as text, as New-FileCatalog writes
        /// it). The thumbprint is the one of the signer of the catalog. The caller keeps the catalog file pinned too. Never
        /// throws. A file that is not in the catalog and an unsigned catalog both give NoSignature.
        /// </summary>
        internal static Verdict VerifyCatalogMember(string catalogPath, string memberPath, FileStream pinned)
        {
            Verdict verdict = new Verdict();
            IntPtr admin = IntPtr.Zero, catalogText = IntPtr.Zero, memberText = IntPtr.Zero, tagText = IntPtr.Zero, hashMemory = IntPtr.Zero, info = IntPtr.Zero;
            try
            {
                if (!CryptCATAdminAcquireContext2(out admin, IntPtr.Zero, "SHA256", IntPtr.Zero, 0)) { admin = IntPtr.Zero; return verdict; }
                pinned.Position = 0;
                byte[] buffer = new byte[64];
                uint size = (uint)buffer.Length;
                if (!CryptCATAdminCalcHashFromFileHandle2(admin, pinned.SafeFileHandle, ref size, buffer, 0) || size != 32) return verdict;
                StringBuilder tag = new StringBuilder(64);
                for (int i = 0; i < 32; i++) tag.Append(buffer[i].ToString("X2", CultureInfo.InvariantCulture));
                pinned.Position = 0;
                catalogText = Marshal.StringToHGlobalUni(catalogPath);
                memberText = Marshal.StringToHGlobalUni(memberPath);
                tagText = Marshal.StringToHGlobalUni(tag.ToString());
                hashMemory = Marshal.AllocHGlobal(32);
                Marshal.Copy(buffer, 0, hashMemory, 32);
                WINTRUST_CATALOG_INFO catalog = new WINTRUST_CATALOG_INFO();
                catalog.cbStruct = (uint)Marshal.SizeOf(typeof(WINTRUST_CATALOG_INFO));
                catalog.pcwszCatalogFilePath = catalogText;
                catalog.pcwszMemberTag = tagText;
                catalog.pcwszMemberFilePath = memberText;
                catalog.hMemberFile = pinned.SafeFileHandle.DangerousGetHandle();
                catalog.pbCalculatedFileHash = hashMemory;
                catalog.cbCalculatedFileHash = 32;
                catalog.hCatAdmin = admin;
                info = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(WINTRUST_CATALOG_INFO)));
                Marshal.StructureToPtr(catalog, info, false);
                Verify(WTD_CHOICE_CATALOG, info, verdict);
            }
            catch (Exception)
            {
                verdict.Reason = "Error";
                verdict.Thumbprint = "";
            }
            finally
            {
                if (info != IntPtr.Zero) Marshal.FreeHGlobal(info);
                if (hashMemory != IntPtr.Zero) Marshal.FreeHGlobal(hashMemory);
                if (tagText != IntPtr.Zero) Marshal.FreeHGlobal(tagText);
                if (memberText != IntPtr.Zero) Marshal.FreeHGlobal(memberText);
                if (catalogText != IntPtr.Zero) Marshal.FreeHGlobal(catalogText);
                if (admin != IntPtr.Zero) CryptCATAdminReleaseContext(admin, 0);
                GC.KeepAlive(pinned);
            }
            return verdict;
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

            // Installer helper (Install.ps1, Uninstall.ps1): delete folders without following links. No service is started.
            string treeMode = null, treePath = null, treeTrusted = null, treeSkip = null;
            foreach (string arg in args)
            {
                if (arg.StartsWith("/removetree:", StringComparison.OrdinalIgnoreCase)) { treeMode = "removetree"; treePath = arg.Substring(12); }
                else if (arg.StartsWith("/cleandata:", StringComparison.OrdinalIgnoreCase)) { treeMode = "cleandata"; treePath = arg.Substring(11); }
                else if (arg.StartsWith("/trusted:", StringComparison.OrdinalIgnoreCase)) { treeTrusted = arg.Substring(9); }
                else if (arg.StartsWith("/skip:", StringComparison.OrdinalIgnoreCase)) { treeSkip = arg.Substring(6); }
            }
            if (treeMode != null) return SafeTree.Run(treeMode, treePath, treeTrusted, treeSkip);

            // Free disk space (SelfX_Device_FreeSpace.ps1): delete old entries below one fixed folder. No service is started.
            string oldKey = null, oldPath = null, oldAge = null;
            bool oldMode = false;
            foreach (string arg in args)
            {
                if (arg.StartsWith("/cleanold:", StringComparison.OrdinalIgnoreCase)) { oldMode = true; oldKey = arg.Substring(10); }
                else if (arg.StartsWith("/cleanoldpath:", StringComparison.OrdinalIgnoreCase)) { oldMode = true; oldPath = arg.Substring(14); }
                else if (arg.StartsWith("/minage:", StringComparison.OrdinalIgnoreCase)) { oldAge = arg.Substring(8); }
            }
            if (oldMode) return SafeTree.RunCleanOld(oldKey, oldPath, oldAge);

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
