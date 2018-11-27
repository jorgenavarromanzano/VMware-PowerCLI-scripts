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
#change $hours

#change this variables to your emails and smtpserver:
$destemail = "tso.sspp3@mail.com"
$origemail = "vmwarepowercli@mail.es"
$smtpserver = "localhost"
$hours = 25
$datebegin = get-date -format yyyyMMdd

$error.clear()

function Get-VIEventPlus {
<#   
.SYNOPSIS  Returns vSphere events    
.DESCRIPTION The function will return vSphere events. With
    the available parameters, the execution time can be
   improved, compered to the original Get-VIEvent cmdlet. 
.NOTES  Author:  Luc Dekens   
.PARAMETER Entity
   When specified the function returns events for the
   specific vSphere entity. By default events for all
   vSphere entities are returned. 
.PARAMETER EventType
   This parameter limits the returned events to those
   specified on this parameter. 
.PARAMETER Start
   The start date of the events to retrieve 
.PARAMETER Finish
   The end date of the events to retrieve. 
.PARAMETER Recurse
   A switch indicating if the events for the children of
   the Entity will also be returned 
.PARAMETER User
   The list of usernames for which events will be returned 
.PARAMETER System
   A switch that allows the selection of all system events. 
.PARAMETER ScheduledTask
   The name of a scheduled task for which the events
   will be returned 
.PARAMETER FullMessage
   A switch indicating if the full message shall be compiled.
   This switch can improve the execution speed if the full
   message is not needed.   
.EXAMPLE
   PS> Get-VIEventPlus -Entity $vm
.EXAMPLE
   PS> Get-VIEventPlus -Entity $cluster -Recurse:$true
#>
 
  param(
    [VMware.VimAutomation.ViCore.Impl.V1.Inventory.InventoryItemImpl[]]$Entity,
    [string[]]$EventType,
    [DateTime]$Start,
    [DateTime]$Finish = (Get-Date),
    [switch]$Recurse,
    [string[]]$User,
    [Switch]$System,
    [string]$ScheduledTask,
    [switch]$FullMessage = $false
  )
 
  process {
    $eventnumber = 100
    $events = @()
    $eventMgr = Get-View EventManager
    $eventFilter = New-Object VMware.Vim.EventFilterSpec
    $eventFilter.disableFullMessage = ! $FullMessage
    $eventFilter.entity = New-Object VMware.Vim.EventFilterSpecByEntity
    $eventFilter.entity.recursion = &{if($Recurse){"all"}else{"self"}}
    $eventFilter.eventTypeId = $EventType
    if($Start -or $Finish){
      $eventFilter.time = New-Object VMware.Vim.EventFilterSpecByTime
    if($Start){
        $eventFilter.time.beginTime = $Start
    }
    if($Finish){
        $eventFilter.time.endTime = $Finish
    }
    }
  if($User -or $System){
    $eventFilter.UserName = New-Object VMware.Vim.EventFilterSpecByUsername
    if($User){
      $eventFilter.UserName.userList = $User
    }
    if($System){
      $eventFilter.UserName.systemUser = $System
    }
  }
  if($ScheduledTask){
    $si = Get-View ServiceInstance
    $schTskMgr = Get-View $si.Content.ScheduledTaskManager
    $eventFilter.ScheduledTask = Get-View $schTskMgr.ScheduledTask |
      where {$_.Info.Name -match $ScheduledTask} |
      Select -First 1 |
      Select -ExpandProperty MoRef
  }
  if(!$Entity){
    $Entity = @(Get-Folder -Name Datacenters)
  }
  $entity | %{
      $eventFilter.entity.entity = $_.ExtensionData.MoRef
      $eventCollector = Get-View ($eventMgr.CreateCollectorForEvents($eventFilter))
      $eventsBuffer = $eventCollector.ReadNextEvents($eventnumber)
      while($eventsBuffer){
        $events += $eventsBuffer
        $eventsBuffer = $eventCollector.ReadNextEvents($eventnumber)
      }
      $eventCollector.DestroyCollector()
    }
    $events
  }
}
 
function Get-MotionHistory {
<#   
.SYNOPSIS  Returns the vMotion/svMotion history    
.DESCRIPTION The function will return information on all
   the vMotions and svMotions that occurred over a specific
    interval for a defined number of virtual machines 
.NOTES  Author:  Luc Dekens   
.PARAMETER Entity
   The vSphere entity. This can be one more virtual machines,
   or it can be a vSphere container. If the parameter is a
    container, the function will return the history for all the
   virtual machines in that container. 
.PARAMETER Days
   An integer that indicates over how many days in the past
   the function should report on. 
.PARAMETER Hours
   An integer that indicates over how many hours in the past
   the function should report on. 
.PARAMETER Minutes
   An integer that indicates over how many minutes in the past
   the function should report on. 
.PARAMETER Sort
   An switch that indicates if the results should be returned
   in chronological order. 
.EXAMPLE
   PS> Get-MotionHistory -Entity $vm -Days 1
.EXAMPLE
   PS> Get-MotionHistory -Entity $cluster -Sort:$false
.EXAMPLE
   PS> Get-Datacenter -Name $dcName |
   >> Get-MotionHistory -Days 7 -Sort:$false
#>
 
  param(
    [CmdletBinding(DefaultParameterSetName="Days")]
    [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
    [VMware.VimAutomation.ViCore.Impl.V1.Inventory.InventoryItemImpl[]]$Entity,
    [Parameter(ParameterSetName='Days')]
    [int]$Days = 1,
    [Parameter(ParameterSetName='Hours')]
    [int]$Hours,
    [Parameter(ParameterSetName='Minutes')]
    [int]$Minutes,
    [switch]$Recurse = $false,
    [switch]$Sort = $true
  )
 
  begin{
    $history = @()
    switch($psCmdlet.ParameterSetName){
      'Days' {
        $start = (Get-Date).AddDays(- $Days)
      }
      'Hours' {
        $start = (Get-Date).AddHours(- $Hours)
      }
      'Minutes' {
        $start = (Get-Date).AddMinutes(- $Minutes)
      }
    }
    $eventTypes = "DrsVmMigratedEvent","VmMigratedEvent"
  }
 
  process{
    $history += Get-VIEventPlus -Entity $entity -Start $start -EventType $eventTypes -Recurse:$Recurse |
    Select CreatedTime,
    @{N="Type";E={
        if($_.SourceDatastore.Name -eq $_.Ds.Name){"vMotion"}else{"svMotion"}}},
    @{N="UserName";E={if($_.UserName){$_.UserName}else{"System"}}},
    @{N="VM";E={$_.VM.Name}},
    @{N="SrcVMHost";E={$_.SourceHost.Name.Split('.')[0]}},
    @{N="TgtVMHost";E={if($_.Host.Name -ne $_.SourceHost.Name){$_.Host.Name.Split('.')[0]}}},
    @{N="SrcDatastore";E={$_.SourceDatastore.Name}},
    @{N="TgtDatastore";E={if($_.Ds.Name -ne $_.SourceDatastore.Name){$_.Ds.Name}}}
  }
 
  end{
    if($Sort){
      $history | Sort-Object -Property CreatedTime
    }
    else{
      $history
    }
  }
}

Start-Transcript log.txt -append
$vcenters = @()
$vcenters = Get-Content -Path ..\vcenters.txt
$vcenters += "vdc-vcsalres01.vdc.adm"
$vcenters += "vdc-vcsalres02.vdc.adm"
$vcenters += "vdc-vcsjcres01.vdc.adm"
$vcenters += "vdc-vcsjcres02.vdc.adm"
$vcenters += "vdc-vcsalmgt01.vdc.adm"
$vcenters += "vdc-vcsjcmgt01.vdc.adm"
$vcenters += "vcenter01.vmware.adm"
$vcenters += "vcenter02.vmware.adm"
$credentials = Get-Content -Path ..\credentials.txt
$user = ($credentials -split ",")[0]
$password = ($credentials -split ",")[1]

$hostsnotconnectedmail = @()
$texto = @()
$texto += "------------------------------------------"

foreach ($vcenter in $vcenters)
{
	#ERRORS-WARNINGS
	$texto+="           " + $vcenter
	write-host "           " + $vcenter
	if($vcenter -like "*vdc*")
	{
		Connect-VIServer $vcenter -User "VDC\powercli" -Password "Password01"
	}
	elseif($vcenter -like "*vmware.adm*")
	{
		Connect-VIServer $vcenter -User "powercli" -Password "Password01"
	}
	else
	{
		Connect-VIServer $vcenter -User $user -Password $password
	}
	$errors_warnings = get-vievent -Types Error,Warning -Start (get-date).addhours(-$hours)
	$texto += $vcenter + "_errors/warnings: | " + $errors_warnings.count + " **********"
	write-host $vcenter + "_errors/warnings: | " + $errors_warnings.count + " **********"
	$errors_warnings | %{
		$dateew = $_.CreatedTime.ToString()
		$mensaje = $_.fullFormattedMessage
		$nodo = $_.host.name
		write-host $vcenter + " | " + $dateew + " | " + $nodo + " | " + $mensaje
		$texto += $vcenter + " | " + $dateew + " | " + $nodo + " | " + $mensaje + "`n"
	}
	#ALARMS
	$objetos = @()
	$objetos += Get-View -ViewType ComputeResource -Property Name,OverallStatus,TriggeredAlarmstate -filter @{"OverallStatus"="yellow"}
	$objetos += Get-View -ViewType ComputeResource -Property Name,OverallStatus,TriggeredAlarmstate -filter @{"OverallStatus"="red"}
	$objetos += Get-View -ViewType Datacenter -Property Name,OverallStatus,TriggeredAlarmstate -filter @{"OverallStatus"="yellow"}
	$objetos += Get-View -ViewType Datacenter -Property Name,OverallStatus,TriggeredAlarmstate -filter @{"OverallStatus"="red"}
	$objetos += Get-View -ViewType Datastore -Property Name,OverallStatus,TriggeredAlarmstate -filter @{"OverallStatus"="yellow"}
	$objetos += Get-View -ViewType Datastore -Property Name,OverallStatus,TriggeredAlarmstate -filter @{"OverallStatus"="red"}
	$objetos += Get-View -ViewType DistributedVirtualSwitch -Property Name,OverallStatus,TriggeredAlarmstate -filter @{"OverallStatus"="red"}
	$objetos += Get-View -ViewType DistributedVirtualSwitch -Property Name,OverallStatus,TriggeredAlarmstate -filter @{"OverallStatus"="yellow"}
	$objetos += Get-View -ViewType Folder -Property Name,OverallStatus,TriggeredAlarmstate -filter @{"OverallStatus"="yellow"}
	$objetos += Get-View -ViewType Folder -Property Name,OverallStatus,TriggeredAlarmstate -filter @{"OverallStatus"="red"}
	$objetos += Get-View -ViewType HostSystem -Property Name,OverallStatus,TriggeredAlarmstate -filter @{"OverallStatus"="red"}
	$objetos += Get-View -ViewType HostSystem -Property Name,OverallStatus,TriggeredAlarmstate -filter @{"OverallStatus"="yellow"}
	$objetos += Get-View -ViewType Network -Property Name,OverallStatus,TriggeredAlarmstate -filter @{"OverallStatus"="yellow"}
	$objetos += Get-View -ViewType Network -Property Name,OverallStatus,TriggeredAlarmstate -filter @{"OverallStatus"="red"}
	$objetos += Get-View -ViewType Resourcepool -Property Name,OverallStatus,TriggeredAlarmstate -filter @{"OverallStatus"="yellow"}
	$objetos += Get-View -ViewType Resourcepool -Property Name,OverallStatus,TriggeredAlarmstate -filter @{"OverallStatus"="red"}
	$objetos += Get-View -ViewType VirtualMachine -Property Name,OverallStatus,TriggeredAlarmstate -filter @{"OverallStatus"="red"}
	$objetos += Get-View -ViewType VirtualMachine -Property Name,OverallStatus,TriggeredAlarmstate -filter @{"OverallStatus"="yellow"}

	$texto += $vcenter + "_alarms: | " + $objetos.triggeredalarmstate.count + " **********"
	write-host $vcenter + "_alarms: | " + $objetos.triggeredalarmstate.count + " **********"
	
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
				$texto += $object.Name + " | " + $object.Alarmas + " | " + $object.Estado + " | " + $object.Fecha
				write-host $object.Name + " | " + $object.Alarmas + " | " + $object.Estado + " | " + $object.Fecha
			}
		}
	}
	#VMOTIONS
	$clusters = get-cluster
	foreach ($cluster in $clusters)
	{
		$vmotions = get-cluster $cluster | Get-MotionHistory -Hours $hours -Recurse:$true
		$texto += $vcenter +"_" + $cluster.name + "_vmotions_"+$datebegin+": | " + $vmotions.count + " **********"
		write-host $vcenter +"_" + $cluster.name + "_vmotions_"+$datebegin+": | " + $vmotions.count + " **********"
		foreach ($vmotion in $vmotions)
		{
			$texto += ($vmotion.CreatedTime.addhours(1)).tostring() + " | " + $vmotion.VM + " | " + $vmotion.UserName + " | srcHost:" + $vmotion.SrcVMHost + "|  dstHost:" + $vmotion.TgtVMHost + " | " + $vmotion.Type + " | srcLUN:" + $vmotion.SrcDatastore + " | dstLUN:" + $vmotion.TgtDatastore
			write-host ($vmotion.CreatedTime.addhours(1)).tostring() + " | " + $vmotion.VM + " | " + $vmotion.UserName + " | srcHost:" + $vmotion.SrcVMHost + " | dstHost:" + $vmotion.TgtVMHost + " | " + $vmotion.Type + " | srcLUN:" + $vmotion.SrcDatastore + " | dstLUN:" + $vmotion.TgtDatastore
		}
	}
	#latency events (number of events with latency increased in each vcenter)
	$latencyevents = Get-VIEventPlus -EventType "esx.problem.scsi.device.io.latency.high" -Start (get-date).addhours(-$hours)
	$texto += $vcenter + "_latencyevents_" + $datebegin + ": | " + $latencyevents.count + " **********"
	write-host $vcenter + "_latencyevents_" + $datebegin + ": | " + $latencyevents.count + " **********"
	$texto += "------------------------------------------"
	write-host "------------------------------------------"
	
	#HOSTS-NotConnected
	$hostsnotconnected = @()
	$hostsnotconnected += get-vmhost | ? {$_.connectionstate -ne "Connected"} | select Name,@{Name="vcenter";Expression={$vcenter}},Connectionstate,Powerstate | sort vcenter,name
	foreach ($hostnotconnected in $hostsnotconnected)
	{
		$hostsnotconnectedmail += $hostnotconnected.vcenter + " | " + $hostnotconnected.name + " | " + $hostnotconnected.connectionstate + " | " + $hostnotconnected.Powerstate 
	}
	
	Disconnect-VIServer $vcenter -confirm:$false
}

$texto += "HOSTS NOT CONNECTED:"
$texto += $hostsnotconnectedmail
$texto += "------------------------------------------"
$texto = Out-String -Inputobject $texto
$asunto = "VMware PowerCLI daily report " + $datebegin

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
