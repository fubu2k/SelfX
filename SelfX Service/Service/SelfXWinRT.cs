/*
.SYNOPSIS
    SelfXWinRT.dll - access to the Windows Update orchestrator (WinRT) for PowerShell 7.
.DESCRIPTION
    PowerShell 7 cannot load Windows Runtime types by name any more (the syntax
    [Windows.Management.Update.WindowsUpdateManager, ..., ContentType = WindowsRuntime] works in Windows
    PowerShell 5.1 only). This small library is built with the Windows SDK projection of .NET 10 and returns the
    manager object. The scripts then use the same members as before (StartScan, IsScanning, GetApplicableUpdates).
    It contains no logic of its own, starts no process and reads no file. The library is built by
    tools\Build-SelfXBinaries.ps1, listed with its SHA256 in Bin\SelfX.Binaries.json and installed by
    Install.ps1 into the folder WinRT of the install folder (writable only by administrators).
    On Windows without the orchestrator (before Windows 11 24H2) creating the manager throws; the scripts catch
    this and fall back to the Windows Update Agent.

    Name    : SelfXWinRT.cs
    Package : SelfX Service
    Context : Loaded by PowerShell 7 as the user (status checks) or as SYSTEM (service actions)

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.0    2026-11-22  fubu2k               Initial version (phase 2b of the move to PowerShell 7).
*/
using System;
using Windows.Management.Update;

namespace SelfX
{
    public static class SelfXWinRT
    {
        /// <summary>Create the orchestrator manager. The client id only labels the caller (letters, digits, dot, minus, underscore; up to 64 characters).</summary>
        public static WindowsUpdateManager CreateUpdateManager(string clientId)
        {
            if (string.IsNullOrEmpty(clientId) || clientId.Length > 64) { throw new ArgumentException("Invalid client id."); }
            foreach (char c in clientId)
            {
                bool allowed = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '.' || c == '-' || c == '_';
                if (!allowed) { throw new ArgumentException("Invalid client id."); }
            }
            return new WindowsUpdateManager(clientId);
        }
    }
}
