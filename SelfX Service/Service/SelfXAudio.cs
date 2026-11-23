/*
.SYNOPSIS
    SelfXAudio.dll - switch the sound of the default playback device on again (Core Audio) for PowerShell 7.
.DESCRIPTION
    The legacy script pressed the mute key through SendKeys, which toggles: a device that was audible became silent.
    This small library reads the state of the default playback device through the Core Audio COM interfaces
    (IMMDeviceEnumerator, IMMDevice, IAudioEndpointVolume) and changes only what is needed:
      - a muted device is unmuted,
      - a volume below the given minimum is raised to the minimum (never lowered).
    It never toggles, does not change the default device, the microphone, drivers, services or the registry, starts no
    process, reads no file and needs no administrator rights (it acts on the endpoint of the signed-in user). The only
    input is the minimum volume in percent (0 to 100). The library is built by tools\Build-SelfXBinaries.ps1, listed with
    its SHA256 in Bin\SelfX.Binaries.json and SelfX.Files.json and installed by Install.ps1 into the folder Audio of the
    install folder (writable only by administrators); the script checks the hash before it loads the library
    (Sources\SelfXAudio.ps1).

    Name    : SelfXAudio.cs
    Package : SelfX Service
    Context : Loaded by PowerShell 7 as the user (action "No sound")

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    2.8.18   2026-11-23  fubu2k               Initial version (replaces the SendKeys mute toggle).
*/
using System;
using System.Runtime.InteropServices;

namespace SelfX
{
    /// <summary>What the call found and what it changed.</summary>
    public sealed class SelfXAudioResult
    {
        public bool WasMuted { get; internal set; }
        public int VolumeBeforePercent { get; internal set; }
        public int VolumeAfterPercent { get; internal set; }
        public bool Unmuted { get; internal set; }
        public bool VolumeRaised { get; internal set; }
    }

    public static class SelfXAudio
    {
        // Core Audio interfaces: only the methods that are called are used, but the order of ALL methods is the order in the
        // virtual table and must not change.
        [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
        private class MMDeviceEnumeratorClass { }

        [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IMMDeviceEnumerator
        {
            [PreserveSig] int EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr devices);
            [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice endpoint);
            [PreserveSig] int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IMMDevice device);
            [PreserveSig] int RegisterEndpointNotificationCallback(IntPtr client);
            [PreserveSig] int UnregisterEndpointNotificationCallback(IntPtr client);
        }

        [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IMMDevice
        {
            [PreserveSig] int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object interfacePointer);
            [PreserveSig] int OpenPropertyStore(int access, out IntPtr properties);
            [PreserveSig] int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
            [PreserveSig] int GetState(out int state);
        }

        [ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IAudioEndpointVolume
        {
            [PreserveSig] int RegisterControlChangeNotify(IntPtr notify);
            [PreserveSig] int UnregisterControlChangeNotify(IntPtr notify);
            [PreserveSig] int GetChannelCount(out uint channelCount);
            [PreserveSig] int SetMasterVolumeLevel(float levelDb, ref Guid eventContext);
            [PreserveSig] int SetMasterVolumeLevelScalar(float level, ref Guid eventContext);
            [PreserveSig] int GetMasterVolumeLevel(out float levelDb);
            [PreserveSig] int GetMasterVolumeLevelScalar(out float level);
            [PreserveSig] int SetChannelVolumeLevel(uint channel, float levelDb, ref Guid eventContext);
            [PreserveSig] int SetChannelVolumeLevelScalar(uint channel, float level, ref Guid eventContext);
            [PreserveSig] int GetChannelVolumeLevel(uint channel, out float levelDb);
            [PreserveSig] int GetChannelVolumeLevelScalar(uint channel, out float level);
            [PreserveSig] int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, ref Guid eventContext);
            [PreserveSig] int GetMute([MarshalAs(UnmanagedType.Bool)] out bool mute);
        }

        private const int ERender = 0;      // playback devices
        private const int EConsole = 0;     // the default device for games, system sounds and apps
        private const int ClsCtxAll = 23;   // CLSCTX_INPROC_SERVER | INPROC_HANDLER | LOCAL_SERVER | REMOTE_SERVER
        private static readonly Guid AudioEndpointVolumeId = new Guid("5CDF2C82-841E-4546-9722-0CF74078229A");

        private static void Check(int hr, string what)
        {
            if (hr < 0) { throw new InvalidOperationException(what + " failed (0x" + hr.ToString("X8") + ")."); }
        }

        /// <summary>Unmute the default playback device and raise its volume to at least minimumPercent (0 to 100). Never lowers the volume.</summary>
        public static SelfXAudioResult Restore(int minimumPercent)
        {
            if (minimumPercent < 0 || minimumPercent > 100) { throw new ArgumentOutOfRangeException("minimumPercent", "The minimum volume must be between 0 and 100."); }
            IMMDeviceEnumerator enumerator = null;
            IMMDevice device = null;
            object volumeObject = null;
            try
            {
                enumerator = (IMMDeviceEnumerator)new MMDeviceEnumeratorClass();
                int hr = enumerator.GetDefaultAudioEndpoint(ERender, EConsole, out device);
                if (hr == unchecked((int)0x80070490)) { throw new InvalidOperationException("There is no playback device."); }
                Check(hr, "Reading the default playback device");
                Guid iid = AudioEndpointVolumeId;
                Check(device.Activate(ref iid, ClsCtxAll, IntPtr.Zero, out volumeObject), "Opening the volume control");
                IAudioEndpointVolume volume = (IAudioEndpointVolume)volumeObject;
                Guid context = Guid.Empty;

                bool muted;
                float level;
                Check(volume.GetMute(out muted), "Reading the mute state");
                Check(volume.GetMasterVolumeLevelScalar(out level), "Reading the volume");
                SelfXAudioResult result = new SelfXAudioResult();
                result.WasMuted = muted;
                result.VolumeBeforePercent = (int)Math.Round(level * 100.0);

                if (muted)
                {
                    Check(volume.SetMute(false, ref context), "Switching the sound on");
                    result.Unmuted = true;
                }
                // Compare in whole percent, so 29.6 % counts as 30 % and nothing is set needlessly.
                if (result.VolumeBeforePercent < minimumPercent)
                {
                    Check(volume.SetMasterVolumeLevelScalar(minimumPercent / 100.0f, ref context), "Setting the volume");
                    result.VolumeRaised = true;
                }
                float after;
                Check(volume.GetMasterVolumeLevelScalar(out after), "Reading the volume again");
                result.VolumeAfterPercent = (int)Math.Round(after * 100.0);
                return result;
            }
            catch (COMException exception)
            {
                throw new InvalidOperationException("The audio service answered with an error (0x" + exception.HResult.ToString("X8") + ").");
            }
            finally
            {
                if (volumeObject != null) { Marshal.ReleaseComObject(volumeObject); }
                if (device != null) { Marshal.ReleaseComObject(device); }
                if (enumerator != null) { Marshal.ReleaseComObject(enumerator); }
            }
        }
    }
}
