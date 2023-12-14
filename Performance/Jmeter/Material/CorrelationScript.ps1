Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Get-BrowseLocation($FileType)
{
    $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{ 
        InitialDirectory = [Environment]::GetFolderPath('Desktop') 
        Filter = $FileType 
    }
    
    $null=$FileBrowser.ShowDialog()

    $FileBrowser.FileName
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Correlation recorder script details v2'
$form.Size = New-Object System.Drawing.Size(500,180)
$form.StartPosition = 'CenterScreen'

$label1 = New-Object System.Windows.Forms.Label
$label1.Location = New-Object System.Drawing.Point(10,20)
$label1.Size = New-Object System.Drawing.Size(100,30)
$label1.Text = 'Select Script file:'
$form.Controls.Add($label1)

$textBox1 = New-Object System.Windows.Forms.TextBox
$textBox1.Location = New-Object System.Drawing.Point(110,20)
$textBox1.Size = New-Object System.Drawing.Size(260,20)
$form.Controls.Add($textBox1)

$browseButton1 = New-Object System.Windows.Forms.Button
$browseButton1.Location = New-Object System.Drawing.Point(380,20)
$browseButton1.Size = New-Object System.Drawing.Size(75,20)
$browseButton1.Text = 'Browse'
$browseButton1_OnClick= 
{
    $textBox1.Text=Get-BrowseLocation -FileType 'JMX (*.jmx)|*.jmx'
}
$browseButton1.add_Click($browseButton1_OnClick)
$form.AcceptButton = $browseButton1
$form.Controls.Add($browseButton1)

$labe2 = New-Object System.Windows.Forms.Label
$labe2.Location = New-Object System.Drawing.Point(10,60)
$labe2.Size = New-Object System.Drawing.Size(100,30)
$labe2.Text = 'Select Results file:'
$form.Controls.Add($labe2)

$textBox2 = New-Object System.Windows.Forms.TextBox
$textBox2.Location = New-Object System.Drawing.Point(110,60)
$textBox2.Size = New-Object System.Drawing.Size(260,20)
$form.Controls.Add($textBox2)

$browseButton2 = New-Object System.Windows.Forms.Button
$browseButton2.Location = New-Object System.Drawing.Point(380,60)
$browseButton2.Size = New-Object System.Drawing.Size(75,20)
$browseButton2.Text = 'Browse'
$browseButton2_OnClick= 
{
    $textBox2.Text=Get-BrowseLocation -FileType 'XML (*.xml)|*.xml|jtl (*.jtl)|*.jtl'
}
$browseButton2.add_Click($browseButton2_OnClick)
$form.AcceptButton = $browseButton2
$form.Controls.Add($browseButton2)

$form.Topmost = $true

$form.Add_Shown({$textBox1.Select()})
$form.Add_Shown({$textBox2.Select()})

$okButton = New-Object System.Windows.Forms.Button
$okButton.Location = New-Object System.Drawing.Point(295,100)
$okButton.Size = New-Object System.Drawing.Size(75,20)
$okButton.Text = 'OK'
$okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
$form.AcceptButton = $okButton
$form.Controls.Add($okButton)

$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Location = New-Object System.Drawing.Point(380,100)
$cancelButton.Size = New-Object System.Drawing.Size(75,20)
$cancelButton.Text = 'Cancel'
$cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
$form.CancelButton = $cancelButton
$form.Controls.Add($cancelButton)

$result = $form.ShowDialog()

if ($result -eq [System.Windows.Forms.DialogResult]::OK)
{
    $JMXFilePath = $textBox1.Text
    $JTLFilePath = $textBox2.Text
    
}
else
{
    $JMXFilePath=''
    $JTLFilePath=''
}

$JMXFilePath #= "C:\Users\Admincc80f44c87\Downloads\apache-jmeter-5.4.3\apache-jmeter-5.4.3\bin\Scripts\SO_TestAutoCorrelation\SOE2E_1255-3_Recording_PS.jmx"
$JTLFilePath #= "C:\Users\Admincc80f44c87\Downloads\apache-jmeter-5.4.3\apache-jmeter-5.4.3\bin\Scripts\SO_TestAutoCorrelation\SOE2E_1255-3_Recording.xml"

#Get the XML result file
$ResultsFile = [xml](Get-Content $JTLFilePath)

#Extract Transaction Names
$RequestIds=@()
$ResultsFile.testResults.httpSample | Select lb |
  ForEach-Object {
             $RequestIds += $_."lb"       
                 }

#################### Extract ControldIds from requests ####################

#Create empty csv with headers
$ObjectCreation = [pscustomobject]@{'ControlId' = ""; 'RequestId' = ""}
$ObjectCreation | Export-Csv -Path C:\Temp\Test.csv -NoTypeInformation

$TotControlIds=@()

#Extract all RootId, TargetId and ThrottleId used in all requests
foreach ($RequestId in $RequestIds)
{
    #Pick a request at once
    $RequestQuerystr=$ResultsFile.SelectSingleNode("testResults/httpSample[@lb='$RequestId']").SelectNodes("queryString").innertext
    
    #Fetch all ControlIds in the request
    $IdValRegex = '([0-9]+_[0-9]+)[_TG]*'
    $ControlIds=$RequestQuerystr | select-string  -Pattern $IdValRegex -AllMatches | % { $_.Matches } | % { $_.Value } 
    
    $TotControlIds += $ControlIds
    
    #Add ControlIds to csv
    foreach ($ControlId in $ControlIds)
    {
        Add-Content -Path C:\Temp\Test.csv -Value "`"$ControlId`",`"$RequestId`""
    }  
}

#Remove empty records in csv
Import-Csv -Path C:\Temp\Test.csv  | Where-Object { $_.PSObject.Properties.Value -ne '' } | Export-Csv -Path C:\Temp\Extract.csv -NoTypeInformation
Remove-item "C:\Temp\Test.csv"

#################### Extract Controls details from response ####################

#Create empty csv with headers
$ObjectCreation = [pscustomobject]@{'ControlId' = "";'ControlName'=""; 'RequestId' = ""}
$ObjectCreation | Export-Csv -Path C:\Temp\Test.csv -NoTypeInformation

$ResponseList = @()
$RequestIdsList = @()

#Process ThrottleIds to get only ControlId values and select distinct list
$TotControlIds = $TotControlIds | ForEach-Object TrimEnd("_TG") | Select-Object -Unique

foreach ($ControlId in $TotControlIds)
{
    foreach ($RequestId in $RequestIds)
    {
        #Pick a request at once
        $RespData=$ResultsFile.SelectSingleNode("testResults/httpSample[@lb='$RequestId']").SelectNodes("responseData").innertext 

        #RexEx for fetching Control details
        $ControlIdRegex = '"Id":"('+$ControlId+')","Name":"(\w+)"'    

        $StoreExtractedResp=@()
        $StoreExtractedResp += $RespData | select-string -Pattern $ControlIdRegex -AllMatches| % { $_.Matches } | % { $_.Value } 

        if($StoreExtractedResp -ne $null)
        {
            #Select only the first response which generated the control
            $FirstResponse= $StoreExtractedResp[0]
            if($FirstResponse -in $ResponseList)
            {
               break
            }
            else
            {
                #Add Control details to csv
                Add-Content -Path C:\Temp\Test.csv -Value "`"$FirstResponse`",`"$RequestId`""
                $ResponseList += $FirstResponse
                $RequestIdsList += $RequestId
            }
        }
    }
}

#Remove empty records in csv
Import-Csv -Path C:\Temp\Test.csv  | Where-Object { $_.PSObject.Properties.Value -ne '' } | Export-Csv -Path C:\Temp\ExtractcleanResp.csv -NoTypeInformation
Remove-item "C:\Temp\Test.csv"

#################### Updated the script with Regular Expression extractors for each control ####################

#Get the JMX script file
$ScriptFile = [xml](Get-Content $JMXFilePath)

Import-Csv -Path C:\Temp\ExtractcleanResp.csv  | ForEach {
   #For each Control
   $CtrlId = ($_.ControlId).TrimStart('Id":"').TrimEnd('"') #| select ControlId -Pattern '([0-9]+_[0-9]+)' -AllMatches | % { $_.Matches } | % { $_.Value } 
   $CtrlName = ($_.ControlName).TrimStart('Name:"').TrimEnd('"')
   $RqId = $_.RequestId
   $one='$1'

   $newRegexExtractorNode = [xml]@"
            <RegexExtractor guiclass="RegexExtractorGui" testclass="RegexExtractor" testname="Regular Expression Extractor$CtrlName$CtrlId" enabled="true">
              <stringProp name="RegexExtractor.useHeaders">false</stringProp>
              <stringProp name="RegexExtractor.refname">$CtrlName$CtrlId</stringProp>
              <stringProp name="RegexExtractor.regex">&quot;Id&quot;:&quot;([0-9]+_[0-9]+)&quot;,&quot;Name&quot;:&quot;$CtrlName&quot;</stringProp>
              <stringProp name="RegexExtractor.template">$one$</stringProp>
              <stringProp name="RegexExtractor.default">NOTFOUND</stringProp>
              <stringProp name="RegexExtractor.match_number">1</stringProp>
            </RegexExtractor>
"@
    $newhashTreeNode = $ScriptFile.CreateElement("hashTree")

    $nodes=$ScriptFile.SelectNodes("jmeterTestPlan/hashTree/hashTree/hashTree/hashTree")

    #Trcaverse through the tree and add new Regex extractor nodes for each control
    for ($i = 0; $i -lt $nodes.ChildNodes.Count; $i++) {
        if($nodes.ChildNodes[$i].testname -eq $RqId)
        {
            $nodes.ChildNodes[$i].NextSibling.AppendChild($ScriptFile.ImportNode($newRegexExtractorNode.RegexExtractor,$true))  #$RegExpExtr)
            $nodes.ChildNodes[$i].NextSibling.AppendChild($newhashTreeNode)  #$RegExpExtr)
        } 
    }
}

$ScriptFile.save($JMXFilePath)

#################### Replace the controlIds in the script with new variables created through RegEx extractors ####################

Import-Csv -Path C:\Temp\ExtractcleanResp.csv  | ForEach {
   #Get the JMX script file
   $ScriptFile = Get-Content -Path $JMXFilePath

   $CtrlId = ($_.ControlId).TrimStart('Id":"').TrimEnd('"') 
   $CtrlName = ($_.ControlName).TrimStart('Name:"').TrimEnd('"')
   
   $a='Id&quot;:&quot;'+$CtrlId+'&quot;'
   $b='Id&quot;:&quot;${'+$CtrlName+$CtrlId+'}&quot;'
   $c='Id&quot;:&quot;'+$CtrlId+'_TG&quot;'
   $d='Id&quot;:&quot;${'+$CtrlName+$CtrlId+'}_TG&quot;'
   $e='Id":"'+$CtrlId+'"'
   $f='Id":"${'+$CtrlName+$CtrlId+'}"'
   $g='Id":"'+$CtrlId+'_TG"'
   $h='Id":"${'+$CtrlName+$CtrlId+'}_TG"'

   $ScriptFile = $ScriptFile -replace $a,$b
   $ScriptFile = $ScriptFile -replace $c,$d
   $ScriptFile = $ScriptFile -replace $e,$f
   $ScriptFile = $ScriptFile -replace $g,$h
   
   $ScriptFile | Set-Content -Path $JMXFilePath
   
} 

#Remove any unwanted whitespaces or new lines
$ScriptFile = (Get-Content -Path $JMXFilePath)-join''
$ScriptFile = $ScriptFile -replace '[\s]+/>', '/>'
$ScriptFile = $ScriptFile -replace '">[\s]+</', '"></'
$ScriptFile | Set-Content -Path $JMXFilePath
