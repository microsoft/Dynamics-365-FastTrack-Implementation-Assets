# Use at Your Own Risk:
# The following open-source code is provided "as is," without warranty of any kind, express or implied. Users are solely responsible for its usage and any consequences that may arise. 
# The developers of this code make no guarantees regarding its functionality, reliability, or suitability for any specific purpose.

# No Liability:
# In no event shall the developers be liable for any direct, indirect, incidental, special, exemplary, or consequential damages 
# (including, but not limited to, procurement of substitute goods or services, loss of use, data, or profits, or business interruption) 
# arising in any way out of the use of this software, even if advised of the possibility of such damage.

# Not a Product:
# This code is not a finished product and may be subject to errors or bugs. It is provided for educational and collaborative purposes. 
# Users are encouraged to review and modify the code according to their needs.

# Community Collaboration:
# This open-source project encourages collaboration and welcomes contributions from the community. 
# However, contributors should be aware that the acceptance of changes is at the discretion of the maintainers, and they reserve the right to reject 
# any contributions that do not align with the project's goals or quality standards.

# Acknowledgment:
# The developers appreciate any feedback, bug reports, or contributions from users. 
# By using this code, you agree to respect the intentions and efforts of the original authors and the open-source community.

# By using this open-source code, you acknowledge that you have read and understood this disclaimer. 
# If you do not agree with these terms, do not use the code.

# January 2023 update - added support to create entities as views within Fabric

function Get-Menu {
    Clear
    Write-Host ''
    Write-Host 'Which step in the entity util would you like to run?'
    Write-Host ''
    Write-Host '1. Create the JOSN file with a list of all dependencies for the identified entities from a sandbox environment.'
    Write-Host '2. Create missing tables and views in an Azure Synapse or SQL database.'
    Write-Host '3. Delete all of the tables and views in the target database.'
    Write-Host '4. Delete all of the tables and views in the source serverless database.'
    Write-Host '5. Create the inherited tables in Fabric. (ONLY required to support Fabric.)'
    Write-Host ''
    Write-Host 'Q - Quit'
    Write-Host ''
    if($WarningMsg) { 
        Write-Host ''
        Write-Warning $WarningMsg
        Clear-Variable WarningMsg }
    Write-Host '════════════════════════════════════════════════════════════'
    $Prompt = Read-Host "Option"

    Switch($Prompt.ToUpper().ToString())  {
        1 {
            Write-Host ''			
            Write-Host 'Generating list of dependencies.'
			Write-Host ''			
             .\GenerateEntityDependency.ps1
        }
        2 {
			Write-Host ''
			Write-Host 'Building views.'	
            Write-Host ''		
             .\EntityUtil.ps1
        }
        3 {
			Write-Host ''
			Write-Host 'Deleting target tables and views.'	
            Write-Host ''		
             .\DeleteViewsFromSynapse.ps1 "target"
        }
        4 {
			Write-Host ''
			Write-Host 'Deleting source tables and views.'	
            Write-Host ''		
             .\DeleteViewsFromSynapse.ps1 "source"
        }
        5 {
			Write-Host ''
			Write-Host 'Creating inherited tables in Fabric.'	
            Write-Host ''		
             .\GenerateInheritedTables.ps1
        }
        Q {
            Clear-Host
            Exit
        }
        Default {
            if($Prompt -notlike "[12345Q]") {
                $WarningMsg = 'Invalid Option. Retry.'
                Get-Menu
            }
        }
    }
}

Get-Menu