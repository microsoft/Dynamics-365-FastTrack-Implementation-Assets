# Description

This tool exports Entity Store metadata.

# Requirements

Run Visual Studio as an Administrator on an AX One Box.

# Build & Run

This project can only be built in AX VMs. Please set the path to your AOS binaries like below if you path differs from the default one boxes (C:\AosService\PackagesLocalDirectory\bin)

msbuild *.sln /p:AOSBinPath="K:\AosService\PackagesLocalDirectory\bin"