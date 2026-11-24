# offline-feed

Local NuGet package source for the offline build (`NuGet.config` in the repository root).
Contains the `.nupkg` files that `dotnet publish` needs and `SelfX.OfflineFeed.json` with the SHA512 of every file.

Do not edit by hand. Create or renew the folder with `tools\Export-SelfXOfflineFeed.ps1` on a computer with internet access
(see `docs/Installation.md`, "Offline build"). `tools\Build-SelfXBinaries.ps1` refuses to build when a file is missing, changed or not listed.
