# EventLog Sink Config Service Installer

This installer creates a Windows MSI package for the **EventLog Sink Config Service** using [WiX v4](https://wixtoolset.org/). The service monitors and validates that the Store Commerce `config.json` has the EventLog sink properly configured.

## Prerequisites

- [.NET 8.0 SDK](https://dotnet.microsoft.com/download/dotnet/8.0) (includes WiX v4 via NuGet - no separate WiX install needed)

## Building the Installer

### Using the build script (recommended)

```powershell
cd installer-eventlogsink\scripts
.\build-installer.ps1
```

For a specific configuration:

```powershell
.\build-installer.ps1 -Configuration Debug
```

### Manual build

1. **Publish the service:**

   ```powershell
   cd services\EventLogSinkConfigService
   dotnet publish -c Release -r win-x64 --self-contained false
   ```

2. **Build the installer:**
   ```powershell
   cd installer-eventlogsink\WixProject
   dotnet build -c Release -p:Platform=x64
   ```

The MSI output will be in `WixProject\bin\Release\x64\`.

## Installing

### Interactive install

Double-click the `.msi` file or run:

```powershell
msiexec /i EventLogSinkConfigService.Installer.msi
```

The installer prompts for an install directory. Configuration settings (`ConfigFilePath`, `CollectionIntervalMinutes`) are defined in the service's `appsettings.json` and can be edited after installation.

### Silent install

```powershell
msiexec /i EventLogSinkConfigService.Installer.msi /qn
```

## Uninstalling

### Via Settings

Go to **Settings > Apps > Installed apps**, find "EventLog Sink Config Service", and click **Uninstall**.

### Via command line

```powershell
msiexec /x EventLogSinkConfigService.Installer.msi /qn
```

## Post-Install Configuration

The service configuration is stored in:

```
C:\Program Files\StoreMonitoring\EventLogSinkConfigService\appsettings.json
```

Default settings:

- **ConfigFilePath** - `C:\Program Files\Microsoft Dynamics 365\10.0\Store Commerce\Microsoft\contentFiles\Pos\config.json`
- **CollectionIntervalMinutes** - `1440` (24 hours)

To update configuration, use the included script:

```powershell
cd "C:\Program Files\StoreMonitoring\EventLogSinkConfigService"
.\Configure-Service.ps1 -ConfigFilePath "C:\path\to\config.json" -CollectionIntervalMinutes 720
```

Or edit `appsettings.json` directly and restart the service:

```powershell
Restart-Service EventLogSinkConfigService
```

## Troubleshooting

### Build issues

- Ensure .NET 8.0 SDK is installed: `dotnet --list-sdks`
- WiX v4 NuGet packages are restored automatically during build
- Check that `services\EventLogSinkConfigService` project builds successfully

### Installation issues

- Check `configure-service.log` in the installation directory for configuration errors
- Verify the service is registered: `Get-Service EventLogSinkConfigService`
- Check Windows Event Log for service startup errors

### Service issues

- Verify the `ConfigFilePath` in `appsettings.json` points to a valid file
- Ensure the service account has read access to the config file path
- Check service status: `Get-Service EventLogSinkConfigService | Format-List *`
