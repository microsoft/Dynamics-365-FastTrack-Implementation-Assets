# Dynamics 365/Power Platform DevOps Pipelines

This repository contains Azure DevOps pipeline configurations for automated deployment of Dynamics 365/Power Platform solutions between environments.

## Pipeline Overview

The setup consists of two main pipelines:

### 1. Export from Source (`D365_DevOps_Export_from_Source.yaml`)
This pipeline exports solutions from the source environment and commits them to the repository. It:
- Publishes all customizations in the source environment
- Updates the solution version
- Exports both managed and unmanaged versions of the solution
- Unpacks the solution files
- Commits changes to the GitHub repository

### 2. Push to Target (`D365_DevOps_Push_to_Target.yaml`)
This pipeline deploys solutions to the target environment. It:
- Packs the solution files from the repository
- Imports the managed solution to the target environment
- Publishes customizations

## Prerequisites

- Azure DevOps environment with:
  - Service Principal (SPN) configured for both source and target Dataverse environments
  - GitHub PAT (Personal Access Token) for repository access
- GitHub repository
- Power Platform environments (source and target)

## Configuration

Before using these pipelines, update the following placeholders:
- `YourSolutionUniqueName`: Your solution's unique name
- `YourGitHubOrgName`: Your GitHub organization name
- `YourGitHubRepoName`: Your GitHub repository name
- `youruser@domain.com`: Your Git commit email
- `youruser`: Your Git commit username

## Usage

Both pipelines are configured with `trigger: none` and should be manually triggered or integrated into a release strategy as needed.

## Security Note

Ensure all credentials and service principals are properly secured using Azure DevOps variable groups or secure variables.
