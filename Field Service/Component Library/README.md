# Field Service Component Library

## Universal Resource Scheduling (URS) Components

Microsoft's FastTrack implementation assets for Universal Resource Scheduling (URS) in Dynamics 365 Field Service provide components for managing schedule board settings, including both standard and virtual configurations. These components help organizations customize and optimize their resource scheduling capabilities within Field Service implementations.

### Schedule Board Settings Management Component

A Power Apps Component Framework (PCF) control that enhances Dynamics 365 Field Service by providing an intuitive interface for managing Schedule Board configurations, including the ability to copy, delete, and toggle schedule board tabs. This component helps dispatchers efficiently manage multiple board views with different settings, addressing a common need for "Save As" functionality in schedule board management.

### Schedule Board Settings Management Component (Virtual)

A specialized virtual PCF control variant of the Schedule Board Settings Management PCF control. This component provides the same robust configuration management capabilities as the standard version but is using the virtual PCF control framework for faster load times and a smaller bundle.js file size.

## Vendor Self-Service
The Vendor Self-Service solution enables organizations using Dynamics 365 Field Service to efficiently manage external vendors and contractors. This solution automates the process of setting up vendor resources, managing their characteristics, and handling their access to the system. Ultimately these resources can then login to the Field Service mobile app to do field work.

## Service Report
The service report is integrated into Field Service as a Power Apps component framework (PCF) control. An admin or developer can download and import the reporting package as a solution in Power Apps. In addition, the provided source code and templates allow developers to customize the report by updating branding, logos, and adding extra data fields. This report is considered a custom control and Microsoft doesn't provide support for it.