##David Hahn##
##Powershell script to interact with the LANDesk webservices using the webservices proxy in powershell 2
##Using an example here: http://thepowershellguy.com/blogs/posh/archive/2009/05/15/powershell-v2-get-weather-function-using-a-web-service.aspx
##used regexp for matching GUIDS from here: http://unlockpowershell.wordpress.com/2010/06/15/powershell-use-regex-to-validate-a-guid/
##regexp's make my brain hurt
##Select-Item function from here: http://blogs.technet.com/b/jamesone/archive/2009/06/24/how-to-get-user-input-more-nicely-in-powershell.aspx


Function Select-Item 
{    <# 
     .Synopsis        Allows the user to select simple items, returns a number to indicate the selected item. 
    .Description 
        Produces a list on the screen with a caption followed by a message, the options are then        displayed one after the other, and the user can one. 
          Note that help text is not supported in this version. 
    .Example 
        PS> select-item -Caption "Configuring RemoteDesktop" -Message "Do you want to: " -choice "&Disable Remote Desktop",           "&Enable Remote Desktop","&Cancel"  -default 1       Will display the following 
          Configuring RemoteDesktop           Do you want to:           [D] Disable Remote Desktop  [E] Enable Remote Desktop  [C] Cancel  [?] Help (default is "E"): 
    .Parameter Choicelist 
        An array of strings, each one is possible choice. The hot key in each choice must be prefixed with an & sign 
    .Parameter Default 
        The zero based item in the array which will be the default choice if the user hits enter. 
    .Parameter Caption 
        The First line of text displayed 
     .Parameter Message 
        The Second line of text displayed     #> 
Param(   [String[]]$choiceList, 
         [String]$Caption="Please make a selection", 
         [String]$Message="Choices are presented below", 
         [int]$default=0 
      ) 
   $choicedesc = New-Object System.Collections.ObjectModel.Collection[System.Management.Automation.Host.ChoiceDescription] 
   $choiceList | foreach  { $choicedesc.Add((New-Object "System.Management.Automation.Host.ChoiceDescription" -ArgumentList $_))} 
   $Host.ui.PromptForChoice($caption, $message, $choicedesc, $default) }  

function Usage($version) {
	
	Write-Host "This script uses the LANDesk MBSDK and a file with a list of DeviceID's to delete machines from the LANDesk system"
	Write-Host "Usage --> LANDesk-WebServices-Deletecomputer.ps1 pathtofile"
	Write-Host
	Write-Host "Example: The usage below will delete the computers identified by the DeviceID's found in c:\temp\computers.txt"
	Write-Host "LANDesk-WebServices-Deletecomputer.ps1 c:\temp\computers.txt"
	Write-Host "If the path to the file that contains the GUID has a space in it, make sure to enclose in double quotes"
	
}

#Function will log information to the console
#$info is the string to write to the console and log file
#$errormsg is a bool that tells the function if the message should be written as an error
#errors are written to the console in RED text.
function WriteLog($info, $logpath, $errormsg=$false)
{
	#Funtion will write log entries along with a time and date stamp
	
	$nowdate = date -format G
	if ($errormsg) {
		Write-Host "[$nowdate] $info" -foregroundcolor Red
	}
	else {
		Write-Host "[$nowdate] $info"
	}
	
	"[$nowdate] $info" | out-file "$logpath" -enc ASCII -append
	
}

$logfile = "$env:temp\ld_deletecomputers.txt"
$ErrorActionPreference = "SilentlyContinue" #we will handle errors ourselves. Thanks anyway, powershell.
$version = "1.0" ##version of the script
$invalidGUID = $false ##prime variable
$LDServerName = "landesk.contoso.com" ##what server has the SDK on it?
$LANDesk_URI = "http://$LDServerName/MBSDKService/MsgSDK.asmx?WSDL" ##URI to the SDK

WriteLog "--------------------------------------------" $logfile
WriteLog "LANDesk machine deletion script - v$version" $logfile
WriteLog "written by David Hahn - 2012" $logfile
writelog "Logging to: $logfile" $logfile

#check that the arguments that were passed 
if ($args.length -eq 0) {
	WriteLog "ERROR: You didn't supply any parameters. You need to supply the path to the file that has the DeviceID's of the machines you want to delete" $logfile
	usage $version
}
else
{
	#they supplied something, check that it's valid
	if (!(Test-Path $args[0])) {
		WriteLog "ERROR: You supplied $args This is not a valid file path." $logfile $true
		usage $version
	}
	else { ##do some validation on the file that's been specified. It should be 1 GUID per line
		writelog "You specified $args as an input file.The file should have one GUID per line" $logfile
		writelog "Examining the file for valid GUIDS..." $logfile
		
		$GUIDS = Get-Content $args[0]
		
		foreach ($GUID in $GUIDS) {
			if (!($GUID -match("^(\{){0,1}[0-9a-fA-F]{8}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{12}(\}){0,1}$"))) {
				WriteLog "ERROR: Found an invalid GUID in the file you specified. $GUID is not a valid GUID" $logfile $true
				$invalidGUID = $true
			}	
		}
	
		if (!($invalidGUID)) { ##the file contained valid GUIDS
			writelog "File input validated. The GUIDs provided are of the right format."
			
			#ask if they want to continue
			$numcomputers = $GUIDS.Count
			$selection = select-item -Caption "**Delete Computers**" -Message "This will delete $numcomputers computers from the LANDesk database. Do you want to continue?" -choice "&Yes","&No" -default 1
			
			if ($selection -eq 0) { ## they want to continue
			
				writelog "Getting Handle to LANDesk web service on $LDServerName using the credentials of the user running the script" $logfile
				
				$landeskService = New-WebServiceProxy -Uri $LANDesk_URI -UseDefaultCredential -errorvariable lderror
				
				if ($lderror.count -eq 0) {
					##we have a handle to the web service
					##loop through the GUID's and call the DeleteComputerbyGUID Method
								
					writelog "Successfully got a handle to the web service." $logfile
					
					foreach ($GUID in $GUIDS) {
						
						#get some data about the machine to report in the log.
						$info = $landeskService.GetMachineData($GUID,'<Columns><Column>Computer."Device Name"</Column><Column>Computer.Description</Column></Columns>')
						$device_name=$info.MachineData[0].Value
						$device_description = $info.MachineData[1].Value
						
						writelog "Trying to delete computer with GUID $GUID." 
						writelog "Device Name: $device_name Device Description: $device_description" $logfile
											
						$del_result = $landeskService.DeleteComputerByGUID($GUID)
						if ($del_result -eq 1) {
							writelog "Successfully deleted computer with GUID $GUID" $logfile
						}
						elseif ($del_result -eq 2) {
							writelog "ERROR: Computer with GUID $GUID was not found in the database" $logfile $true
						}
						elseif ($del_result -eq -1) {
							writelog "ERROR: General Error occurred. Computer with GUID $GUID was not deleted" $logfile $true
						}
					}
				
				}
				else {
					##there was an error while connecting to the LANDesk web service.
					writelog "ERROR: Could not connect to the LANDesk Web Service. Message was: $lderror" $logfile $true
					
				}
			}
			else { ##they did not want to continue
				writelog "You chose not to continue. Nothing to do" $logfile
			}
				
		}
		else {
			WriteLog "ERROR: Found at least one invalid GUID in the input." $logfile $true
		}
	}
}