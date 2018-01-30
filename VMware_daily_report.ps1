#JORGE NAVARRO MANZANO Script daily report vmware
#daily report of one or multiples vcenters with warnings, errors, alarms, vmotions etc.
#https://linkedin.com/in/jorgenavarromanzano
#more scripts here: https://github.com/jorgenavarromanzano
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
$destemail = "destmail@mail.com"
$origemail = "origmail@mail.com"
$smtpserver = "localhost"

$error.clear()

Add-PSSnapin VMware.VimAutomation.Core
#function Get-VIEventPlus for vmotions from LUCD http://www.lucd.info/2013/03/31/get-the-vmotionsvmotion-history/
#-----------------#
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
#-----------------#
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
#---------------------------------------------------#
EXAMPLE OF MAIL RECEIVED WITH THIS SCRIPT:


-----Original Message-----
From: xxxxxx@xxxxxx.xxxxx [mailto:xxxxxx@xxxxxx.xxxxx] 
Sent: martes, xx de octubre de xxxx xx:xx
To: xxxxxx@xxxxxx.xxxxx <xxxxxx@xxxxxx.xxxxx>
Subject: VMware PowerCLI daily report 2016XXXX

------------------------------------------
           vcenter1
alarms: 0 **********
vmotions: 0 **********
------------------------------------------
           vcenter2
vcenter2 xx/xx/2016 9:11:47  Cannot login userxxxx@172.x.x.x

vcenter2 xx/xx/2016 17:11:35  Cannot login useryyyy@172.x.x.x

alarms: 1 **********
vcenter2 xxxxx_xxxxx red xx/xx/2016 14:24:31
vmotions: 0 **********
------------------------------------------
           vcenter3
alarms: 0 **********
vmotions: 0 **********
------------------------------------------
           vcenter4
vcenter4 xx/xx/2016 15:18:15 esx02 Error detected on esx02 in XXXXX: Agent can't send heartbeats: Host is down

vcenter4 xx/xx/2016 15:00:33 esx01 The vSphere HA agent on the host esx01 in cluster XXXXX in XXXXX cannot reach some of the management network addresses of other hosts, and thus HA may not be able to restart VMs if a host failure occurs:  xxxxx:172.xx.xx.xx

vcenter4 xx/xx/2016 14:59:54 esx02 Host esx02 in XXXXX is not responding

alarms: 5 **********
esx01 XXXXX_alarm_HA red xx/xx/2016 12:55:46
esx02 XXXXX_alarm_HA red xx/xx/2016 12:56:29
esx02 XXXXX_alarm_VMNIC red xx/xx/2016 14:43:08
esx02 XXXXX_alarm_CONNECTION_FAILURE red xx/xx/2016 12:59:55
esx03 XXXXX_alarm_HA red xx/xx/2016 12:56:15
vmotions: 0 **********
------------------------------------------
           vcenter5
alarms: 1 **********
LUN5_900Gb Datastore usage on disk yellow xx/xx/2016 11:34:16
vmotions: 0 **********
------------------------------------------
           vcenter6
vcenter6 xx/xx/2016 2:36:25  Cannot login userxxxxx@172.xx.xx.xx

vcenter6 xx/xx/2016 1:51:48  Cannot login useryyyyy@172.yy.yy.yy

vcenter6 xx/xx/2016 17:36:25  Cannot login userzzzzz@172.zz.zz.zz

alarms: 1 **********
vmxxxx Virtual machine CPU usage yellow xx/xx/2016 8:51:15
vmotions: 0 **********
------------------------------------------
           vcenter7
alarms: 0 **********
vmotions: 0 **********
------------------------------------------
           vcenter8
alarms: 2 **********
xxxesx01.xxxx.xxxx xxxxx_alarm_Connection_Failure red xx/xx/2016 16:02:57
xxxesx02.xxxx.xxxx xxxxx_alarm_Connection_Failure red xx/xx/2016 15:55:51
vmotions: 0 **********
------------------------------------------
           vcenter9
alarms: 0 **********
vmotions: 0 **********
------------------------------------------
           vcenter10
alarms: 0 **********
vmotions: 0 **********
------------------------------------------
           vcenter11
vcenter11 xx/xx/2016 3:12:14  Cannot login userxxxxx@172.xx.xx.xx

vcenter11 xx/xx/2016 2:02:20 esx_yy_xxxx Warning message on vmbdyyyy_xxx on esx_yy_xxxx in cluster_sitea_xxx: Failed to start quiescing operation in the virtual machine.
The error message was: Quiesce operation already in progress.


vcenter11 xx/xx/2016 2:02:09 esx_yy_xxxx Warning message on vmbdyyyy_xxx on esx_yy_xxxx in cluster_sitea_xxx: Failed to start quiescing operation in the virtual machine.
The error message was: Quiesce operation already in progress.


vcenter11 xx/xx/2016 2:01:57 esx_yy_xxxx Warning message on vmbdyyyy_xxx on esx_yy_xxxx in cluster_sitea_xxx: Failed to start quiescing operation in the virtual machine.
The error message was: Quiesce operation already in progress.


vcenter11 xx/xx/2016 2:01:46 esx_yy_xxxx Warning message on vmbdyyyy_xxx on esx_yy_xxxx in cluster_sitea_xxx: Failed to start quiescing operation in the virtual machine.
The error message was: Quiesce operation already in progress.


vcenter11 xx/xx/2016 2:01:35 esx_yy_xxxx Warning message on vmbdyyyy_xxx on esx_yy_xxxx in cluster_sitea_xxx: Failed to start quiescing operation in the virtual machine.
The error message was: Quiesce operation already in progress.


vcenter11 xx/xx/2016 2:01:22 esx_yy_xxxx Warning message on vmbdyyyy_xxx on esx_yy_xxxx in cluster_sitea_xxx: Failed to start quiescing operation in the virtual machine.
The error message was: Quiesce operation already in progress.


vcenter11 xx/xx/2016 2:01:11 esx_yy_xxxx Warning message on vmbdyyyy_xxx on esx_yy_xxxx in cluster_sitea_xxx: Failed to start quiescing operation in the virtual machine.
The error message was: Quiesce operation already in progress.


vcenter11 xx/xx/2016 2:01:00 esx_yy_xxxx Warning message on vmbdyyyy_xxx on esx_yy_xxxx in cluster_sitea_xxx: Failed to start quiescing operation in the virtual machine.
The error message was: Quiesce operation already in progress.


vcenter11 xx/xx/2016 2:00:49 esx_yy_xxxx Warning message on vmbdyyyy_xxx on esx_yy_xxxx in cluster_sitea_xxx: Cannot quiesce this virtual machine because VMware Tools is not currently available.


vcenter11 xx/xx/2016 2:00:38 esx_yy_xxxx Warning message on vmbdyyyy_xxx on esx_yy_xxxx in cluster_sitea_xxx: A timeout occurred while communicating with VMware Tools in the virtual machine.

vcenter11 xx/xx/2016 1:43:49 esx_zz_yyy Renamed vm333xxxx from vm333xxxx to /vmfs/volumes/xxxxxxx-yyyyyyyyyyy-zzzzzzzzz/vm333zzzzz/vm333zzzzz.vmx in cluster_sitea_xxx

vcenter11 xx/xx/2016 0:49:19 esx_zz_yyy Renamed vm222zzzzz from vm222zzzzz to /vmfs/volumes/xxxxxxx-hhhhhhhh-mmmmmmmmm/vm222zzzzz/vm222zzzzz.vmx in cluster_sitea_xxx

vcenter11 xx/xx/2016 17:00:31  Cannot login Adminyyyyy@172.xx.xx.xx

vcenter11 xx/xx/2016 16:59:48  Cannot login Adminyyyyy@172.xx.xx.xx

vcenter11 xx/xx/2016 16:59:22  Cannot login Adminyyyyy@172.xx.xx.xx

vcenter11 xx/xx/2016 10:37:48 esx_00_yyy Migration of vm_xx_20 from esx_01_yyy to esx_zz_yyy and resource pool Resources in cluster_sitea_xxx: No guest OS heartbeats are being received. Either the guest OS is not responding or VMware Tools is not configured correctly.

alarms: 1 **********
vcenter11 Virtual machine Consolidation Needed status yellow xx/xx/2016 20:34:17
vmotions: 7 **********
xx/xx/2016 10:38:29 vm_xx_1 System srcHost: esx_00_yyy dstHost: esx_zz_yyy vMotion srcLUN: datastore1 dstLUN: datastore2
xx/xx/2016 16:48:08 vm_xx_1 System srcHost: esx_zz_yyy dstHost: esx_00_yyy vMotion srcLUN: datastore2 dstLUN: 
xx/xx/2016 19:18:23 vm_xx_1 System srcHost: esx_00_yyy dstHost: esx_zz_yyy vMotion srcLUN: datastore3 dstLUN: 
xx/xx/2016 0:49:22 vm_xx_2 System srcHost: esx_zz_yyy dstHost: esx_10_yyy vMotion srcLUN: datastore4 dstLUN: datastore5
xx/xx/2016 1:43:52 vm_xx_3 System srcHost: esx_zz_yyy dstHost: esx_10_yyy vMotion srcLUN: datastore5 dstLUN: 
xx/xx/2016 6:08:47 vm_xx_4 System srcHost: esx_10_yyy dstHost: esx_zz_yyy vMotion srcLUN: datastore6 dstLUN: 
xx/xx/2016 6:09:01 vm_xx_4 System srcHost: esx_09_yyy dstHost: esx_07_yyy vMotion srcLUN: datastore8 dstLUN: 
------------------------------------------
           vcenter12
vcenter12 xx/xx/2016 3:22:34 esx_11 Migration of vm33 from esx_11 to esx_05 and resource pool Resources in cluster_site_xxb: No guest OS heartbeats are being received. Either the guest OS is not responding or VMware Tools is not configured correctly.

vcenter12 xx/xx/2016 3:22:32 esx_02 Migration of vm44 from esx_02 to esx_10 and resource pool Resources in cluster_site_xxb: No guest OS heartbeats are being received. Either the guest OS is not responding or VMware Tools is not configured correctly.

vcenter12 xx/xx/2016 23:22:39 esx_05 Warning message on vmdc1 on esx_05 in cluster_site_xxb: The guest OS has reported an error during quiescing.
The error code was: 5
The error message was: 'VssSyncStart' operation failed: IDispatch error #8449 (0x80042301)


vcenter12 xx/xx/2016 23:22:12 esx_05 Warning message on vmdc1 on esx_05 in cluster_site_xxb: The guest OS has reported an error during quiescing.
The error code was: 5
The error message was: 'VssSyncStart' operation failed: IDispatch error #8449 (0x80042301)


vcenter12 xx/xx/2016 22:05:06  Cannot login userxxxxx@172.xx.xx.xx

vcenter12 xx/xx/2016 22:04:58  Cannot login userxxxxx@172.xx.xx.xx

vcenter12 xx/xx/2016 16:37:07 esx_10 Migration of vm_130 from esx_10 to esx_06 and resource pool Resources in cluster_site_xxb: No guest OS heartbeats are being received. Either the guest OS is not responding or VMware Tools is not configured correctly.

alarms: 1 **********
vcenter12 Virtual machine Consolidation Needed status yellow xx/xx/2016 19:21:50
vmotions: 6 **********
xx/xx/2016 11:42:40 vm1 System srcHost: esx_05 dstHost: esx_11 vMotion srcLUN: datastore1 dstLUN: datastore3
xx/xx/2016 16:37:33 vm2 System srcHost: esx_11 dstHost: esx_06 vMotion srcLUN: datastore2 dstLUN: 
xx/xx/2016 3:17:49 vm3 System srcHost: esx_11 dstHost: esx_05 vMotion srcLUN: datastore3 dstLUN: 
xx/xx/2016 3:22:51 vm4 System srcHost: esx_11 dstHost: esx_05 vMotion srcLUN: datastore4 dstLUN: 
xx/xx/2016 3:23:24 vm5 System srcHost: esx_02 dstHost: esx_10 vMotion srcLUN: datastore5 dstLUN: datastore4
xx/xx/2016 3:48:20 vm6 System srcHost: esx_11 dstHost: esx_10 vMotion srcLUN: datastore6 dstLUN: 
------------------------------------------


#---------------------------------------------------#
