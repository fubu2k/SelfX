/*
.SYNOPSIS
    SelfXDisturb.dll - state of the notification area of the own session (SHQueryUserNotificationState) for PowerShell 7.
.DESCRIPTION
    Returns the value 1 to 7 of QUERY_USER_NOTIFICATION_STATE that the shell reports for the session of the caller, or 0 when
    the state cannot be read. The window uses it only to add a hint to the confirmation of a disruptive action ("You appear
    to be in a meeting or presentation"). The library reads one value from shell32.dll (documented API). It takes no input,
    starts no process, reads no file, registry value or other session, changes nothing and needs no administrator rights.
    shell32.dll is loaded from the system folder only (DefaultDllImportSearchPaths). The library is built by
    tools\Build-SelfXBinaries.ps1, listed with its SHA256 in Bin\SelfX.Binaries.json and SelfX.Code.json and installed by
    Install.ps1 into the folder Disturb of the install folder (writable only by administrators); the script checks the hash
    before it loads the library (Sources\SelfXDisturb.ps1). Nothing is compiled on the device.

    Name    : SelfXDisturb.cs
    Package : SelfX Service
    Context : Loaded by PowerShell 7 as the user (window Self_X.ps1)

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    3.1.0    2026-11-28  fubu2k               Initial version (replaces Add-Type with source text in SelfXDisturb.ps1).
*/
using System;
using System.Runtime.InteropServices;

namespace SelfX
{
    public static class SelfXDisturb
    {
        // QUERY_USER_NOTIFICATION_STATE: 1 not present, 2 busy, 3 Direct3D full screen, 4 presentation mode,
        // 5 accepts notifications, 6 quiet time, 7 Windows Store app.
        private const int StateMin = 1;
        private const int StateMax = 7;

        [DllImport("shell32.dll", ExactSpelling = true)]
        [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
        private static extern int SHQueryUserNotificationState(out int state);

        /// <summary>1 to 7 = state of the own session, 0 = the state cannot be read (never throws).</summary>
        public static int GetNotificationState()
        {
            try
            {
                int state;
                int result = SHQueryUserNotificationState(out state);
                if (result != 0 || state < StateMin || state > StateMax) return 0;
                return state;
            }
            catch (DllNotFoundException) { return 0; }
            catch (EntryPointNotFoundException) { return 0; }
            catch (MarshalDirectiveException) { return 0; }
        }
    }
}
