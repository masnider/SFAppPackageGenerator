#####################################################################################################
### SET THESE PARAMETERS TO YOUR DESIRED VALUES #####################################################
#####################################################################################################
$SolutionRootPath = "C:\Users\masnider\source\repos\masnider\service-fabric-dotnet-data-aggregation"
$DesiredOutputPath = "C:\Temp\genpkg" + [DateTime]::UtcNow.Millisecond
$OutputApplicationPackageType = "HealthMetrics"
$BuildConfiguration = "Release"
$OutputApplicationPackageVersion = "1.0.0.0"

#####################################################################################################
### NO MODIFICATIONS BELOW HERE SHOULD BE NECESSARY ##################################################
#####################################################################################################

$applicationParameterSet = @{}
$xmlns = "http://schemas.microsoft.com/2011/01/fabric"

$ManifestXML = [System.Xml.XmlDocument](Get-Content "c:\Temp\AppManifestTemplate.xml")
$ApplicationManifestOutput = Join-Path -Path $DesiredOutputPath -ChildPath "ApplicationManifest.xml"

$HasAnyConfigOverrides = $false

$ManifestXML.ApplicationManifest.ApplicationTypeName = $OutputApplicationPackageType
$ManifestXML.ApplicationManifest.ApplicationTypeVersion = $OutputApplicationPackageVersion

New-Item -ItemType Directory -Force -Path $DesiredOutputPath
$ServicePackagePaths = Get-ChildItem -Path $SolutionRootPath -Filter "ServiceManifest.xml" -Recurse

foreach($ServicePackagePath in $ServicePackagePaths)
{
    $ImportXml = $ManifestXML.CreateElement("ServiceManifestImport", $xmlns)
    $ManifestXML.DocumentElement.AppendChild($ImportXml)

    #Prep the Service manifest xml we'll be inserting into the application manifest
    $ServiceRefXml = $ManifestXML.CreateElement("ServiceManifestRef", $xmlns)
    $ImportXml.AppendChild($ServiceRefXml)
    
    #Get the xml from the service manifest that we're referencing currently
    $ServiceManifestXml = [System.Xml.XmlDocument](Get-Content $ServicePackagePath.FullName)

    $ServiceRefXml.SetAttribute("ServiceManifestName", $ServiceManifestXml.ServiceManifest.Name)
    $ServiceRefXml.SetAttribute("ServiceManifestVersion", $ServiceManifestXml.ServiceManifest.Version)

    #Does this package have a config package? Because we need to figure out if there are config overrides
    foreach($packageNode in $ServiceManifestXml.ServiceManifest.ChildNodes)
    {
        if($packageNode.LocalName -eq "ConfigPackage")
        {
            #yup
            $ConfigPackagePath = Join-Path -Path $ServicePackagePath.Directory.FullName -ChildPath $packageNode.Name

            #Let's presume there's only one Settings.xml file here, or none, and that there aren't nested config dirs
            $SettingsXmlPath = Get-ChildItem -Path $ConfigPackagePath -Filter "*Settings.xml"

            #if there was a settings.xml
            if($SettingsXmlPath -ne $null)
            {

               $ServiceHasOverrides = $false
               #Get the content
               $SettingsFileContent = [System.Xml.XmlDocument](Get-Content $SettingsXmlPath.FullName)
               foreach($Section in $SettingsFileContent.Settings.ChildNodes)
               {
                    $SectionHasOverrides = $false

                    foreach($Parameter in $Section.ChildNodes)
                    {
                        foreach($Attrib in $Parameter.Attributes)
                        {
                            if(($Attrib.LocalName -eq "MustOverride") -and ($Attrib.Value -eq "True"))
                            {
                                
                                if($HasAnyConfigOverrides -eq $false)
                                {
                                    #this is the first config parameter with an override, so we need the app parameters now
                                    $HasAnyConfigOverrides = $true
                                    $ApplicationParametersSection = $ManifestXML.CreateElement("Parameters", $xmlns)
                                    $ManifestXML.ApplicationManifest.AppendChild($ApplicationParametersSection)
                                }


                                if($ServiceHasOverrides -eq $false)
                                {
                                    #this is the first override for this particular service import, so we need to create the overrides settings items
                                    $ServiceHasOverrides = $true
                                    $Overrides = $ManifestXML.CreateElement("ConfigOverrides", $xmlns)
                                    $ImportXml.AppendChild($Overrides)
                                    $Override = $ManifestXML.CreateElement("ConfigOverride", $xmlns)
                                    $Override.SetAttribute("Name",$packageNode.Name)
                                    $Overrides.AppendChild($Override)
                                    $Settings = $ManifestXML.CreateElement("Settings", $xmlns)
                                    $Override.AppendChild($Settings)

                                }

                                if($SectionHasOverrides -eq $false)
                                {
                                    #this is the first time for a given section, so create that element 
                                    $SectionHasOverrides = $true
                                    $AppSection = $ManifestXML.CreateElement("Section", $xmlns)
                                    $AppSection.SetAttribute("Name",$Section.Name)
                                    $Settings.AppendChild($AppSection)
                                }
                                
                                $packageName = $packageNode.Name
                                $SectionName = $Section.Name
                                $paramName = $Parameter.Name
                                $paramValue = "["+$Parameter.Name+"]"

                                #find the right section since there might be multiple
                                $SelectedSection = (($ImportXml.ConfigOverrides.ChildNodes | Select-Object | where -Property Name -EQ $packageName).Settings.ChildNodes) | Where-Object -Property "Name" -eq $SectionName
                                $ConfigParameter = $ManifestXML.CreateElement("Parameter", $xmlns)
                                $ConfigParameter.SetAttribute("Name",$paramName)
                                $ConfigParameter.SetAttribute("Value",$paramValue)
                                $SelectedSection.AppendChild($ConfigParameter)

                                #check to see if this parameter is already in the app parameter set
                                #from some other service. If it is, don't add it again, otherwise do
                                if($applicationParameterSet[$paramName] -eq $null)
                                {
                                    $applicationParameterSet.Add($paramName,"")
                                    $AppParameter = $ManifestXML.CreateElement("Parameter", $xmlns)
                                    $AppParameter.SetAttribute("Name",$paramName)
                                    $AppParameter.SetAttribute("DefaultValue","")                                
                                    $aprms = ($ManifestXML.ApplicationManifest.ChildNodes | Select-Object | where -Property Name -EQ "Parameters") 
                                    $aprms.AppendChild($AppParameter)
                                }
                            }
                        }
                    }
               }
            }
        }
    }

    $ManifestXml.ApplicationManifest.AppendChild($ImportXml)

    #copy the package root structure
    $PackageOutputPath = Join-Path -Path $DesiredOutputPath -ChildPath $ServiceManifestXml.ServiceManifest.Name
    Copy-Item -Recurse -Force -Path $ServicePackagePath.Directory.FullName -Destination $PackageOutputPath
    
    #find and copy the output code
    $PackageOutputCodePath = Join-Path -Path $PackageOutputPath -ChildPath "Code"
    New-Item -ItemType Directory -Force $PackageOutputCodePath 
    
    #we have to do this currently since we don't know the type of structure the output has
    #we should probably be inspecting the csproj/sln configuration to find the output path that is currently configured
    $verifiedPath = ""
    
    $binPath = Join-Path -Path $ServicePackagePath.Directory.Parent.FullName -ChildPath "bin\x64\$BuildConfiguration"
    if(Test-Path -Path $binPath)
    {
        write-host "Copying Service files from $binPath to $PackageOutputCodePath for " + $ServicePackagePath.Directory.Parent.Name
        
        $ncBinPath = Join-Path -Path $binPath -ChildPath "\net461\win7-x64\" #netcore likes to append this no matter what by default, apparently?

        if(Test-Path -Path $ncBinPath)
        { 
           Copy-Item -Recurse -Force -Path "$ncBinPath\*" -Destination $PackageOutputCodePath
        }
        else
        {
            Copy-Item -Recurse -Force -Path "$binPath\*" -Destination $PackageOutputCodePath
        }

    }
    else
    {
        write-host "Can't find correct output bin path for some reason" -ForegroundColor Red -BackgroundColor Black
    }
}

$ManifestXML.Save($ApplicationManifestOutput)
Test-ServiceFabricApplicationPackage $DesiredOutputPath -Verbose