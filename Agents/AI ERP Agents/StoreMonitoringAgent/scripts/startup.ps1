.\scripts\stop-arc-services.ps1 -DisableAutoStart

.\scripts\start-arc-services.ps1 -EnableAutoStart

Get-Service -Name "himds","GCArcService","ExtensionService","ArcProxy" | Select-Object Name, DisplayName, Status, StartType
