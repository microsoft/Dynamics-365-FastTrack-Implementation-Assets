# Description

This tool exports Entity Store metadata for a given measure into a zip file. The metadata package contains a definition of the measure, aggregate dimensions, views and their dependencies. 

# Requirements

Run Visual Studio as an Administrator on an AX OneBox.

# Develoment

This project can only be built in AX VMs. Please set the path to your AOS binaries like below if you path differs from the default one boxes (C:\AosService\PackagesLocalDirectory\bin)

msbuild *.sln /p:AOSBinPath="K:\AosService\PackagesLocalDirectory\bin"

# Run

You can run the tool as following:

```
 .\EntityStoreMetadataExporter.exe -m <aggregate_measurement_name> -o <output_path> -c <connection_string_to_axdb>
```

 