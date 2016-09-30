#JORGE NAVARRO MANZANO Script daily report vmware
#daily report of one or multiples vcenters with warnings, errors, alarms, vmotions etc.
#https://es.linkedin.com/in/jorgenavarromanzano
#used Get-VIEventPlus function for vmotions from LUCD http://www.lucd.info/2013/03/31/get-the-vmotionsvmotion-history/

#Instructions:
#create ..\vcenters.txt
#example:
#vcenter1
#vcenterb
#vcenter2000
#create ..\credentials.txt
#example:
#useradminvcenter,passwordoftheuser
#you need access to port 443 of the vcenters

#change this variables to your emails and smtpserver:
$destemail = "tso.sspp3@telefonica.com"
$origemail = "vmwarepowercli@telefonica.es"
$smtpserver = "localhost"

$error.clear()

Add-PSSnapin VMware.VimAutomation.Core
. .\funciones.ps1
Start-Transcript log.txt -append
$vcenters = Get-Content -Path ..\vcenters.txt
$credentials = Get-Content -Path ..\credentials.txt
$user = ($credentials -split ",")[0]
$password = ($credentials -split ",")[1]

$texto = @()
$texto += "------------------------------------------"

foreach ($vcenter in $vcenters)
{
	#ERRORS-WARNINGS
	$texto+="           " + $vcenter
	write-host "           " + $vcenter
	Connect-VIServer $vcenter -User $user -Password $password
	get-vievent -Types Error,Warning -Start (get-date).addhours(-25) | %{
		$fecha = $_.CreatedTime.ToString()
		$mensaje = $_.fullFormattedMessage
		$nodo = $_.host.name
		write-host $vcenter + " " + $fecha + " " + $nodo + " " + $mensaje
		$texto += $vcenter + " " + $fecha + " " + $nodo + " " + $mensaje + "`n"
	}
	#ALARMS
	$objetos = @()
	$objetos += Get-View -ViewType Datastore -Property Name,OverallStatus,TriggeredAlarmstate | Where-Object {$_.OverallStatus -ne "Green"}
	$objetos += Get-View -ViewType HostSystem -Property Name,OverallStatus,TriggeredAlarmstate | Where-Object {$_.OverallStatus -ne "Green"}
	$objetos += Get-View -ViewType Network -Property Name,OverallStatus,TriggeredAlarmstate | Where-Object {$_.OverallStatus -ne "Green"}
	$objetos += Get-View -ViewType VirtualMachine -Property Name,OverallStatus,TriggeredAlarmstate | Where-Object {$_.OverallStatus -ne "Green"}
			
	$texto += "alarms: " + $objetos.triggeredalarmstate.count + " **********"
	write-host "alarms: " + $objetos.triggeredalarmstate.count + " **********"
	
	if($objetos.count -gt 0)
	{
		foreach ($objeto in $objetos)
		{
			foreach ($alarma in $objeto.TriggeredAlarmstate)
			{
				$alarmaID = $alarma.Alarm.ToString()
				$object = New-Object PSObject
				Add-Member -InputObject $object NoteProperty Name $objeto.Name
				Add-Member -InputObject $object NoteProperty Alarmas ("$(Get-AlarmDefinition -Id $alarmaID)")
				Add-Member -InputObject $object NoteProperty Estado $alarma.OverAllStatus
				Add-Member -InputObject $object NoteProperty Fecha $alarma.Time.tostring()
				$texto += $object.Name + " " + $object.Alarmas + " " + $object.Estado + " " + $object.Fecha
				write-host $object.Name + " " + $object.Alarmas + " " + $object.Estado + " " + $object.Fecha
			}
		}
	}
	#VMOTIONS
	$vmotions = @()
	$vmotions = get-cluster | Get-MotionHistory -Hours 25 -Recurse:$true
	$texto += "vmotions: " + $vmotions.count + " **********"
	write-host "vmotions: " + $vmotions.count + " **********"
	foreach ($vmotion in $vmotions)
	{
		$texto += ($vmotion.CreatedTime.addhours(+2)).tostring() + " " + $vmotion.VM + " " + $vmotion.UserName + " srcHost: " + $vmotion.SrcVMHost + " dstHost: " + $vmotion.TgtVMHost + " " + $vmotion.Type + " srcLUN: " + $vmotion.SrcDatastore + " dstLUN: " + $vmotion.TgtDatastore
		write-host ($vmotion.CreatedTime.addhours(+2)).tostring() + " " + $vmotion.VM + " " + $vmotion.UserName + " srcHost: " + $vmotion.SrcVMHost + " dstHost: " + $vmotion.TgtVMHost + " " + $vmotion.Type + " srcLUN: " + $vmotion.SrcDatastore + " dstLUN: " + $vmotion.TgtDatastore
	}
	
	$texto += "------------------------------------------"
	write-host "------------------------------------------"
	Disconnect-VIServer $vcenter -confirm:$false
}

$texto = Out-String -Inputobject $texto
$fecha = get-date -format yyyyMMdd
$asunto = "VMware PowerCLI daily report " + $fecha

write-host $texto

send-mailmessage -from $origemail -to $destemail -subject $asunto -body $texto -smtpServer $smtpserver

if($error.count -gt 0)
{
	$errores = Out-String -Inputobject $error
	send-mailmessage -from $origemail -to $destemail -subject "VMware PowerCLI daily report, execution error" -body $errores -smtpServer $smtpserver
}

Stop-Transcript

if( [int]((Get-ChildItem .\log.txt).Length / 1024 / 1024) -gt 200)
{
	if(test-path .\log.txt.old)
	{
		remove-item	.\log.txt.old
	}
	Rename-Item .\log.txt .\log.txt.old
}
