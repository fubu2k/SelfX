/*
Summary:
    Experiment for the signature check of the SelfX service: WinVerifyTrust for a file with an embedded signature and for a
    file that is a member of one given catalog.

Description:
    Test class, compiled in memory by tools\Measure-SelfXTrustCheck.ps1 (Add-Type). It is not part of the package and not
    used by the service; it answers two questions before SelfXService.cs gets the check:
      1. Embedded signature: WinVerifyTrust (WINTRUST_FILE_INFO with the open handle) and the certificate of the signer from
         the state data (WTHelperProvDataFromStateData, WTHelperGetProvSignerFromChain, WTHelperGetProvCertFromChain).
      2. One given catalog: the hash of the open handle (CryptCATAdminCalcHashFromFileHandle2, SHA256) and WinVerifyTrust with
         WINTRUST_CATALOG_INFO (catalog path, member tag = the hash as hexadecimal text, the calculated hash, the catalog
         administrator context for SHA256). The signer of the catalog is read like in 1.
    For comparison a second way without WINTRUST_CATALOG_INFO: the signature of the catalog file itself (it carries an embedded
    signature) and the list of its members (CryptCATOpen, CryptCATEnumerateMember).
    Every file is opened once, readable for others but not writable and not deletable (FileShare.Read), and is checked through
    that handle. Revocation: whole chain without the root; with cacheOnly only the local cache is used (no network request).
    No user interface. Nothing is written.

Notes:
    Name    : SelfXTrustProbe.cs
    Package : tools
    Context : Test device (signed-in user; not installed, not shipped)
    Version : 3.1.0

    History:
    Version  Date        Author               Change
    -------  ----------  -------------------  ------------------------------------------------------------
    3.1.0    2026-11-27  fubu2k               Initial version
*/

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace SelfXProbe
{
    public sealed class TrustResult
    {
        public string Reason;
        public int Code;
        public string Thumbprint = "";
        public string Hash = "";
        public double Milliseconds;
        public override string ToString() { return Reason + " (0x" + Code.ToString("X8") + ")"; }
    }

    public static class TrustProbe
    {
        public static readonly Guid GenericVerifyV2 = new Guid("00AAC56B-CD44-11d0-8CC2-00C04FC295EE");
        public static readonly Guid DriverVerify = new Guid("F750E6C3-38EE-11d1-85E5-00C04FC295EE");

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

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct CATALOG_INFO
        {
            public uint cbStruct;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string wszCatalogFile;
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
        [DllImport("wintrust.dll", ExactSpelling = true, SetLastError = true)]
        static extern IntPtr CryptCATAdminEnumCatalogFromHash(IntPtr catAdmin, byte[] hash, uint hashSize, uint flags, IntPtr previous);
        [DllImport("wintrust.dll", ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool CryptCATCatalogInfoFromContext(IntPtr catInfo, ref CATALOG_INFO info, uint flags);
        [DllImport("wintrust.dll", ExactSpelling = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool CryptCATAdminReleaseCatalogContext(IntPtr catAdmin, IntPtr catInfo, uint flags);
        [DllImport("wintrust.dll", ExactSpelling = true, SetLastError = true, CharSet = CharSet.Unicode)]
        static extern IntPtr CryptCATOpen(string file, uint flags, IntPtr provider, uint publicVersion, uint encodingType);
        [DllImport("wintrust.dll", ExactSpelling = true)]
        static extern IntPtr CryptCATEnumerateMember(IntPtr catalog, IntPtr previous);
        [DllImport("wintrust.dll", ExactSpelling = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool CryptCATClose(IntPtr catalog);

        /// <summary>Text for the result codes of WinVerifyTrust that the experiment expects; anything else is "Other".</summary>
        public static string ReasonOf(int code)
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
                default: return "Other";
            }
        }

        /// <summary>Opens a file once: others may read it, nobody may write, replace or delete it while the handle is open.</summary>
        public static FileStream OpenPinned(string path)
        {
            return new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        }

        static string Hex(byte[] bytes, int count)
        {
            StringBuilder text = new StringBuilder(count * 2);
            for (int i = 0; i < count; i++) text.Append(bytes[i].ToString("X2"));
            return text.ToString();
        }

        /// <summary>WinVerifyTrust with the state data kept, the thumbprint of the signer read, the state data closed.</summary>
        static void Verify(Guid action, uint choice, IntPtr info, bool cacheOnly, TrustResult result)
        {
            WINTRUST_DATA data = new WINTRUST_DATA();
            data.cbStruct = (uint)Marshal.SizeOf(typeof(WINTRUST_DATA));
            data.dwUIChoice = WTD_UI_NONE;
            data.fdwRevocationChecks = WTD_REVOKE_WHOLECHAIN;
            data.dwUnionChoice = choice;
            data.pInfo = info;
            data.dwStateAction = WTD_STATEACTION_VERIFY;
            data.dwProvFlags = WTD_REVOCATION_CHECK_CHAIN_EXCLUDE_ROOT | WTD_DISABLE_MD2_MD4 | (cacheOnly ? WTD_CACHE_ONLY_URL_RETRIEVAL : 0);
            IntPtr noWindow = new IntPtr(-1);
            try
            {
                result.Code = WinVerifyTrust(noWindow, ref action, ref data);
                result.Reason = ReasonOf(result.Code);
                if (data.hWVTStateData != IntPtr.Zero)
                {
                    IntPtr provider = WTHelperProvDataFromStateData(data.hWVTStateData);
                    IntPtr signer = provider == IntPtr.Zero ? IntPtr.Zero : WTHelperGetProvSignerFromChain(provider, 0, false, 0);
                    IntPtr providerCert = signer == IntPtr.Zero ? IntPtr.Zero : WTHelperGetProvCertFromChain(signer, 0);
                    if (providerCert != IntPtr.Zero)
                    {
                        // CRYPT_PROVIDER_CERT: DWORD cbStruct, then (aligned) PCCERT_CONTEXT pCert.
                        IntPtr context = Marshal.ReadIntPtr(providerCert, IntPtr.Size);
                        if (context != IntPtr.Zero)
                        {
                            using (X509Certificate2 certificate = new X509Certificate2(context)) { result.Thumbprint = certificate.Thumbprint.ToUpperInvariant(); }
                        }
                    }
                }
            }
            finally
            {
                data.dwStateAction = WTD_STATEACTION_CLOSE;
                WinVerifyTrust(noWindow, ref action, ref data);
            }
        }

        /// <summary>1: embedded signature of the file behind the open handle. The path only names the file type (extension).</summary>
        public static TrustResult VerifyEmbedded(string path, FileStream pinned, bool cacheOnly)
        {
            TrustResult result = new TrustResult { Reason = "Error", Code = -1 };
            Stopwatch watch = Stopwatch.StartNew();
            IntPtr pathText = Marshal.StringToHGlobalUni(path);
            IntPtr info = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(WINTRUST_FILE_INFO)));
            try
            {
                pinned.Position = 0;
                WINTRUST_FILE_INFO file = new WINTRUST_FILE_INFO();
                file.cbStruct = (uint)Marshal.SizeOf(typeof(WINTRUST_FILE_INFO));
                file.pcwszFilePath = pathText;
                file.hFile = pinned.SafeFileHandle.DangerousGetHandle();
                Marshal.StructureToPtr(file, info, false);
                Verify(GenericVerifyV2, WTD_CHOICE_FILE, info, cacheOnly, result);
            }
            finally
            {
                Marshal.FreeHGlobal(info);
                Marshal.FreeHGlobal(pathText);
                GC.KeepAlive(pinned);
            }
            result.Milliseconds = watch.Elapsed.TotalMilliseconds;
            return result;
        }

        /// <summary>The catalog hash (SHA256) of the file behind the open handle, or null.</summary>
        public static byte[] CatalogHash(FileStream pinned)
        {
            IntPtr admin;
            if (!CryptCATAdminAcquireContext2(out admin, IntPtr.Zero, "SHA256", IntPtr.Zero, 0)) return null;
            try { return CatalogHash(admin, pinned); }
            finally { CryptCATAdminReleaseContext(admin, 0); }
        }

        static byte[] CatalogHash(IntPtr admin, FileStream pinned)
        {
            pinned.Position = 0;
            byte[] buffer = new byte[64];
            uint size = (uint)buffer.Length;
            if (!CryptCATAdminCalcHashFromFileHandle2(admin, pinned.SafeFileHandle, ref size, buffer, 0) || size != 32) return null;
            byte[] hash = new byte[32];
            Array.Copy(buffer, hash, 32);
            return hash;
        }

        /// <summary>
        /// 2: the file behind the open handle is a member of the given catalog, and the catalog is signed. tagMode: "hash" (the
        /// hash as text, as New-FileCatalog writes it), "none" (no tag) or "wrong" (a tag that no member has), to see what decides.
        /// </summary>
        public static TrustResult VerifyCatalogMember(string catalogPath, string memberPath, FileStream pinned, bool cacheOnly, string tagMode, bool driverAction)
        {
            TrustResult result = new TrustResult { Reason = "Error", Code = -1 };
            Stopwatch watch = Stopwatch.StartNew();
            IntPtr admin;
            if (!CryptCATAdminAcquireContext2(out admin, IntPtr.Zero, "SHA256", IntPtr.Zero, 0)) { result.Reason = "NoCatAdmin"; return result; }
            IntPtr catalogText = IntPtr.Zero, memberText = IntPtr.Zero, tagText = IntPtr.Zero, hashMemory = IntPtr.Zero, info = IntPtr.Zero;
            try
            {
                byte[] hash = CatalogHash(admin, pinned);
                if (hash == null) { result.Reason = "NoHash"; return result; }
                result.Hash = Hex(hash, hash.Length);
                pinned.Position = 0;
                catalogText = Marshal.StringToHGlobalUni(catalogPath);
                memberText = Marshal.StringToHGlobalUni(memberPath);
                if (tagMode == "hash") tagText = Marshal.StringToHGlobalUni(result.Hash);
                else if (tagMode == "wrong") tagText = Marshal.StringToHGlobalUni("0000");
                hashMemory = Marshal.AllocHGlobal(hash.Length);
                Marshal.Copy(hash, 0, hashMemory, hash.Length);
                WINTRUST_CATALOG_INFO catalog = new WINTRUST_CATALOG_INFO();
                catalog.cbStruct = (uint)Marshal.SizeOf(typeof(WINTRUST_CATALOG_INFO));
                catalog.pcwszCatalogFilePath = catalogText;
                catalog.pcwszMemberTag = tagText;
                catalog.pcwszMemberFilePath = memberText;
                catalog.hMemberFile = pinned.SafeFileHandle.DangerousGetHandle();
                catalog.pbCalculatedFileHash = hashMemory;
                catalog.cbCalculatedFileHash = (uint)hash.Length;
                catalog.hCatAdmin = admin;
                info = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(WINTRUST_CATALOG_INFO)));
                Marshal.StructureToPtr(catalog, info, false);
                Verify(driverAction ? DriverVerify : GenericVerifyV2, WTD_CHOICE_CATALOG, info, cacheOnly, result);
            }
            finally
            {
                if (info != IntPtr.Zero) Marshal.FreeHGlobal(info);
                if (hashMemory != IntPtr.Zero) Marshal.FreeHGlobal(hashMemory);
                if (tagText != IntPtr.Zero) Marshal.FreeHGlobal(tagText);
                if (memberText != IntPtr.Zero) Marshal.FreeHGlobal(memberText);
                if (catalogText != IntPtr.Zero) Marshal.FreeHGlobal(catalogText);
                CryptCATAdminReleaseContext(admin, 0);
                GC.KeepAlive(pinned);
            }
            result.Milliseconds = watch.Elapsed.TotalMilliseconds;
            return result;
        }

        /// <summary>The member tags of a catalog (CryptCATOpen, CryptCATEnumerateMember), at most max.</summary>
        public static List<string> CatalogTags(string catalogPath, int max)
        {
            List<string> tags = new List<string>();
            IntPtr catalog = CryptCATOpen(catalogPath, 2 /* CRYPTCAT_OPEN_EXISTING */, IntPtr.Zero, 0, 0x00010001);
            if (catalog == IntPtr.Zero || catalog == new IntPtr(-1)) return null;
            try
            {
                IntPtr member = IntPtr.Zero;
                while ((member = CryptCATEnumerateMember(catalog, member)) != IntPtr.Zero && tags.Count < max)
                {
                    // CRYPTCATMEMBER: DWORD cbStruct, then (aligned) LPWSTR pwszReferenceTag.
                    IntPtr tag = Marshal.ReadIntPtr(member, IntPtr.Size);
                    tags.Add(tag == IntPtr.Zero ? "" : Marshal.PtrToStringUni(tag));
                }
            }
            finally { CryptCATClose(catalog); }
            return tags;
        }

        /// <summary>
        /// Comparison without WINTRUST_CATALOG_INFO: the catalog file itself has a valid embedded signature (through its open
        /// handle) and one of its members has the hash of the file as its tag.
        /// </summary>
        public static TrustResult VerifyCatalogByList(string catalogPath, FileStream pinnedCatalog, FileStream pinnedMember, bool cacheOnly)
        {
            Stopwatch watch = Stopwatch.StartNew();
            TrustResult result = VerifyEmbedded(catalogPath, pinnedCatalog, cacheOnly);
            byte[] hash = CatalogHash(pinnedMember);
            if (hash == null) { result.Reason = "NoHash"; result.Code = -1; }
            else
            {
                result.Hash = Hex(hash, hash.Length);
                List<string> tags = CatalogTags(catalogPath, 100000);
                bool found = false;
                if (tags != null) { foreach (string tag in tags) { if (string.Equals(tag, result.Hash, StringComparison.OrdinalIgnoreCase)) found = true; } }
                if (!found) { result.Reason = tags == null ? "CatalogNotReadable" : "NotInCatalog"; result.Code = -1; }
            }
            result.Milliseconds = watch.Elapsed.TotalMilliseconds;
            return result;
        }

        /// <summary>The path of one catalog of Windows that lists the file behind the handle (for a positive test with a trusted signer), or null.</summary>
        public static string FindSystemCatalog(FileStream pinned)
        {
            IntPtr admin;
            if (!CryptCATAdminAcquireContext2(out admin, IntPtr.Zero, "SHA256", IntPtr.Zero, 0)) return null;
            try
            {
                byte[] hash = CatalogHash(admin, pinned);
                if (hash == null) return null;
                IntPtr found = CryptCATAdminEnumCatalogFromHash(admin, hash, (uint)hash.Length, 0, IntPtr.Zero);
                if (found == IntPtr.Zero) return null;
                try
                {
                    CATALOG_INFO info = new CATALOG_INFO();
                    info.cbStruct = (uint)Marshal.SizeOf(typeof(CATALOG_INFO));
                    return CryptCATCatalogInfoFromContext(found, ref info, 0) ? info.wszCatalogFile : null;
                }
                finally { CryptCATAdminReleaseCatalogContext(admin, found, 0); }
            }
            finally { CryptCATAdminReleaseContext(admin, 0); }
        }
    }
}
