# Code signing certificate for SelfX

**English** | [Deutsch](de/Zertifikat.md)

With a code signing certificate of your organisation the package wizard signs every program, every
script and the two catalogs of the SelfX package (trust mode **Signature**). The devices then accept
only files signed by your certificate, and AppLocker and App Control need **one** publisher rule
that stays the same for every version, instead of new hash rules for each version
([Installation](Installation.md#set-up-once-instead-of-per-version)).

This guide is for the team that runs the PKI and for the administrator who builds the package.
Without a certificate SelfX works as well (trust mode **Hash**).

## Contents

- [What the certificate needs](#what-the-certificate-needs)
- [Request it from an internal PKI (AD CS)](#request-it-from-an-internal-pki-ad-cs)
- [Make the devices trust the certificate](#make-the-devices-trust-the-certificate)
- [Sign with the package wizard](#sign-with-the-package-wizard)
- [Time stamp](#time-stamp)
- [Expiry and change of the certificate](#expiry-and-change-of-the-certificate)
- [Sources](#sources)

## What the certificate needs

| Property | Requirement |
|---|---|
| Key usage | Enhanced key usage **Code Signing** (`1.3.6.1.5.5.7.3.3`); key usage **Digital Signature** |
| Private key | On the PC that builds the package (certificate store of the user or of the computer, smart card), or in a PFX file |
| Algorithm | RSA 2048 bit or more, signature hash SHA-256 |
| Subject | The name of your organisation, with `O=` (AppLocker shows it as the publisher) |
| Revocation list | A **public HTTP address in first place** of the CRL distribution points |
| Validity | As your PKI policy says, for example one to three years |

Why the HTTP address matters: Windows checks the revocation list named in the certificate when it
checks a signature. Devices outside the company network (the normal case with Intune) cannot reach
`ldap://` or `file://` addresses or internal names. `Install.ps1` then treats the signature as
valid (default of Windows); a revoked certificate is only noticed where the list is reachable. The
wizard shows the addresses of the chosen certificate and warns when there is no HTTP address or
only internal names.

Protect the key: anyone who can sign with it gets files allowed by your publisher rules. Use a smart
card, an HSM or one restricted signing PC, and allow export of the key only if you need a PFX file.

## Request it from an internal PKI (AD CS)

An enterprise certification authority of Active Directory Certificate Services has the certificate
template **Code Signing** ("Used to digitally sign software", subject type user). The PKI team:

1. Duplicates the template **Code Signing** under a new name (do not change the original), for example
   "SelfX Code Signing".
2. Restricts **Enroll** to a small group of package administrators and, if possible, requires the
   approval of a certificate manager.
3. Sets the key size (RSA 2048 or more), SHA-256, the validity, and whether the key may be exported.
4. Checks that the CA names a public HTTP address for the revocation list in first place.
5. Publishes the template on the CA.

The package administrator then requests the certificate on the signing PC: `certmgr.msc` → **Personal**
→ **Certificates** → **All Tasks** → **Request New Certificate**, choose the template and enroll. On the
**Details** tab check the key usage, on **Certification Path** the chain.

A certificate bought from a public certification authority works the same way; its chain is
already trusted by Windows.

## Make the devices trust the certificate

SelfX compares the thumbprint of the signer with the list of `-TrustedSigner` of the installation,
**and** Windows must accept the signature: the chain of the certificate has to be trusted on each
device, before SelfX is installed (also during Autopilot).

- **Root and intermediate certificate of your CA:** devices of a domain often trust them already
  (group policy). Otherwise distribute them with Intune: **Devices** → **Configuration** → **Create**
  → platform **Windows 10 and later** → **Templates** → **Trusted certificate**. Upload the root
  certificate as a DER-encoded `.cer` file (without the private key), destination store **Computer
  certificate store - Root**; a second profile with the intermediate certificate and destination
  **Computer certificate store - Intermediate**. Assign both to the same devices as SelfX. The
  profile only delivers root and intermediate certificates, not the signing certificate itself.
- **Signing certificate in "Trusted Publishers":** SelfX does **not** need it; `Install.ps1` and the
  service check the thumbprint themselves. You need it only if your own policies require it (for
  example an execution policy `AllSigned` for PowerShell). Intune can write it with a custom
  profile (OMA-URI) of the RootCATrustedCertificates CSP:
  `./Device/Vendor/MSFT/RootCATrustedCertificates/TrustedPublisher/<SHA1 thumbprint>/EncodedCertificate`,
  value: the certificate as Base64 text without line breaks. Not tried with SelfX.

## Sign with the package wizard

Window (`tools\Start-SelfXPackageWizard.cmd`), page **Signature**:

- **Certificate from the store:** the list shows only certificates with a private key, the key usage
  Code Signing and a valid period, from the stores of your user and of the computer. Expired
  certificates are not offered.
- **Certificate file (PFX):** choose the file and type the password. The file is opened in memory
  only (not imported); the password is used once and the field is emptied. The password is never
  shown, saved, logged or written to `selfx-answers.json`.
- **Time stamp service:** the address of the time stamp service of the vendor of your certificate or
  of your PKI (`http://` or `https://`, no user name or password in the address, at most 300
  characters). Leave it empty only together with the switch "Sign without a time stamp", which is
  meant for tests (see [Time stamp](#time-stamp)). The address is saved in `selfx-answers.json` and
  suggested again when you load that file.
- **Additional allowed signers:** only for a change of the certificate (below).

Console: `tools\New-SelfXPackage.ps1 -CertificateThumbprint <thumbprint>` or `-PfxPath <file>` (the
password is asked for, hidden), `-TimestampServer <address>` (or `-NoTimestamp`),
`-AdditionalSigner <thumbprint>` ([Package wizard](Guided-Setup.md)). Without either the console asks;
with an answer file it takes `TimestampServer` from the file.

The result page lists the steps for Intune with copy buttons; the install command contains
`-TrustedSigner` with the thumbprint(s).

## Time stamp

A time stamp is a countersignature of a time stamp service: it confirms when the file was signed.
Windows then accepts the signature as long as the certificate was valid at that time, also after
the certificate expired. The service is used **only while the package is built**: the devices do not
contact it, and the address is not written into the package or onto the device.

An internal time server (NTP) is not enough. NTP only sets the clock of a computer; it signs nothing.
A time stamp needs a time stamp service with its own certificate (RFC 3161), from the vendor of your
certificate or from your PKI.

Before the first file is signed, the wizard makes one test signature with the service. When it gives
no time stamp (wrong address, no network, service down), the build stops with a short message and
nothing is signed.

Without a time stamp the signatures become invalid on the day the certificate expires (see below).
The wizard therefore signs without one only when you switch it on explicitly (window: "Sign without a
time stamp"; console: `-NoTimestamp`).

## Expiry and change of the certificate

**With a time stamp** a signature stays valid after the certificate expired. **Without** it, the
signatures become invalid on the day the certificate expires: `Install.ps1` refuses the package, and
the service starts nothing (event 4007, reason `Expired`; it notices this after 60 minutes at the
latest, also for files that did not change).

Devices accept only the signers named in `-TrustedSigner` of their last installation (at most 10
thumbprints). Change the certificate in three steps:

1. **Announce the new certificate.** Build the package again with the **old** certificate and enter
   the thumbprint of the **new** one under "Additional allowed signers" (console:
   `-AdditionalSigner`). Upload it as a new version and wait until all devices have it.
2. **Switch.** Build with the **new** certificate; the old thumbprint may stay as an additional
   signer for a while.
3. **Clean up.** Later build without the old thumbprint.

AppLocker and App Control: a renewed certificate with the **same subject** needs no new rules. With
another subject, create the publisher rules again and roll them out before the first package with
the new certificate (during the change both rules are needed; App Control: `-AllowMultipleSigners`),
see [Set up once instead of per version](Installation.md#set-up-once-instead-of-per-version).

Revoked certificate (key lost or stolen): revoke it at the CA, request a new one and follow the
three steps without a waiting time between them. Devices that reach the revocation list refuse the
old signatures (event 4007, reason `Revoked`).

Not tried on a device: the Intune profile for "Trusted Publishers", a revoked certificate on a
device, and a signed package from the window with a real `IntuneWinAppUtil.exe`.

## Sources

- Microsoft Learn: [Certificate templates concepts (AD CS)](https://learn.microsoft.com/windows-server/identity/ad-cs/certificate-template-concepts),
  [Manage AD CS certificate templates](https://learn.microsoft.com/windows-server/identity/ad-cs/manage-certificate-templates)
- Microsoft Learn: [Create a code signing certificate for App Control for Business](https://learn.microsoft.com/windows/security/application-security/application-control/app-control-for-business/deployment/create-code-signing-cert-for-appcontrol)
- Microsoft Learn: [Trusted root certificate profiles for Microsoft Intune](https://learn.microsoft.com/intune/device-configuration/certificates/trusted-root-profiles)
- Microsoft Learn: [RootCATrustedCertificates CSP](https://learn.microsoft.com/windows/client-management/mdm/rootcacertificates-csp)
- Microsoft Learn: [Time stamping Authenticode signatures](https://learn.microsoft.com/windows/win32/seccrypto/time-stamping-authenticode-signatures)
  (a signature without a time stamp becomes invalid when the certificate expires)
