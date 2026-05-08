# Database Metrics Service - WiX Installer

This directory contains the WiX Toolset installer project for creating an MSI package for the Database Metrics Service.

## Directory Structure

```
installer/
├── DatabaseMetricsService.Installer.sln  # Solution file
├── README.md                              # This file
├── scripts/
│   ├── build-installer.ps1                # Build automation script
│   ├── Configure-Service.ps1              # Service configuration script
│   ├── Grant-SqlPermissions.ps1           # Grant SQL permissions (run after install)
│   └── Revoke-SqlPermissions.ps1          # Revoke SQL permissions (run before uninstall)
└── WixProject/                            # WiX installer project
    ├── DatabaseMetricsService.Installer.wixproj
    └── Product.wxs                        # WiX source file
```

## Prerequisites

1. **.NET 8.0 SDK**
   - Required to build the main service and the WiX installer
   - Download from: https://dotnet.microsoft.com/download/dotnet/8.0

> **Note:** WiX Toolset v4 is included as an SDK-style NuGet package (`WixToolset.Sdk/4.0.6`) and does **not** require a separate installation.

## Building the Installer

### Option 1: Using PowerShell Script (Recommended)

```powershell
# Build Release installer
.\scripts\build-installer.ps1

# Build Debug installer
.\scripts\build-installer.ps1 -Configuration Debug
```

The script will:

1. Check for the .NET 8.0 SDK
2. Publish the `DatabaseMetricsService` project
3. Prepare installer resources (placeholder icon and license if missing)
4. Build the MSI using `dotnet build` with the WiX v4 SDK

### Option 2: Using Visual Studio

1. Open `DatabaseMetricsService.Installer.sln` in Visual Studio
2. Ensure the DatabaseMetricsService project is published first
3. Build the solution (F6)
4. The MSI will be created in `WixProject\bin\Release\`

### Option 3: Manual Build

```powershell
# 1. Build the main service
cd ..\services\DatabaseMetricsService
dotnet publish -c Release -r win-x64 --self-contained false

# 2. Build the WiX v4 installer
cd ..\..\installer\WixProject
dotnet build -c Release -p:Platform=x64
```

## Installing the Service

### Interactive Installation

Double-click the MSI file or run:

```cmd
msiexec /i DatabaseMetricsService.Installer.msi
```

The installer will:

1. Let you accept the license agreement
2. Let you choose the installation directory
3. Prompt for SQL Server connection details (server instance and database name)
4. Install the Windows service (runs as Virtual Service Account `NT SERVICE\DatabaseMetricsService`)
5. Run `Configure-Service.ps1` to update `appsettings.json` and start the service

> **Important:** After installation, you must manually run the SQL permissions script. See [Post-Install: SQL Permissions](#post-install-sql-permissions).

### Silent Installation

```cmd
msiexec /i DatabaseMetricsService.Installer.msi /quiet ^
    SQL_SERVER=localhost ^
    DATABASE_NAME=RetailOfflineDatabase ^
    INSTALLFOLDER="C:\Program Files\StoreMonitoring\DatabaseMetricsService"
```

### Installation with Logging

```cmd
msiexec /i DatabaseMetricsService.Installer.msi /l*v install.log
```

## Uninstalling the Service

### Interactive Uninstallation

```cmd
msiexec /x DatabaseMetricsService.Installer.msi
```

Or use Windows "Add or Remove Programs"

### Silent Uninstallation

```cmd
msiexec /x DatabaseMetricsService.Installer.msi /quiet
```

## Post-Install Configuration

During installation, the `Configure-Service.ps1` PowerShell script runs automatically to:

- Update `appsettings.json` with the SQL Server instance and database name provided during setup
- Start the `DatabaseMetricsService` Windows service

Configuration logs are written to `install-config.log` in the installation directory.

### Post-Install: SQL Permissions

The service runs as a Virtual Service Account (`NT SERVICE\DatabaseMetricsService`). After installation, grant SQL Server permissions by running:

```powershell
.\scripts\Grant-SqlPermissions.ps1 -SqlServer "localhost" -DatabaseName "RetailOfflineDatabase"
```

This creates the SQL login and grants `VIEW SERVER STATE`, `VIEW ANY DATABASE`, `VIEW DATABASE STATE`, and `VIEW DEFINITION`.

### Pre-Uninstall: Remove SQL Permissions

Before or after uninstalling, remove the SQL login by running:

```powershell
.\scripts\Revoke-SqlPermissions.ps1 -SqlServer "localhost" -DatabaseName "RetailOfflineDatabase"
```

## Troubleshooting

### SQL Configuration Fails

If the service fails to collect metrics, ensure SQL permissions have been granted. Run the `Grant-SqlPermissions.ps1` script or manually configure permissions using:

```sql
USE [master]
GO
CREATE LOGIN [NT SERVICE\DatabaseMetricsService] FROM WINDOWS
GO
GRANT VIEW SERVER STATE TO [NT SERVICE\DatabaseMetricsService]
GO
GRANT VIEW ANY DATABASE TO [NT SERVICE\DatabaseMetricsService]
GO
USE [YourDatabase]
GO
CREATE USER [NT SERVICE\DatabaseMetricsService] FOR LOGIN [NT SERVICE\DatabaseMetricsService]
GO
GRANT VIEW DATABASE STATE TO [NT SERVICE\DatabaseMetricsService]
GO
GRANT VIEW DEFINITION TO [NT SERVICE\DatabaseMetricsService]
GO
```

### Build Errors

- Ensure .NET 8.0 SDK is installed (WiX v4 SDK is restored automatically via NuGet)
- Build the main service before building the installer (`dotnet publish` in the service directory)
- If NuGet restore fails, run `dotnet restore` in the `WixProject` directory
