<#
.SYNOPSIS
    Exports MOVEit Automation Tasks, Hosts, Schedule metadata and a Host to Task Dependency Report.

.DESCRIPTION
    - MOVEit_Hosts.csv (one row per host)
    - MOVEit_Tasks.csv (one row per Source → Destination → Schedule)
    - MOVEit_Host_Task_Dependencies.csv (one row per Host used in any Task, including usage type: Source / Destination / NextAction)
    - Linked using HostID

.PARAMETER <XmlPath>
    Path to the ConfigExport.xml file exported from MOVEit Automation.
.PARAMETER <OutDir>
    Directory to write the CSV output files. Defaults to current directory.

.EXAMPLE
    .\ConfigExport_to_CSV.ps1 -XmlPath "C:\Exports\ConfigExport.xml" -OutDir "C:\Exports\CSV"

.NOTES
    Author: Rhonda Richardson Kovanda
    Date: 2026-04-28
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$XmlPath,
    [string]$OutDir = "."
)

# Load XML File from the parameter
if (-not (Test-Path $XmlPath)) {
    throw "XML file not found: $XmlPath"
}

[xml]$xml = Get-Content $XmlPath

function Get-FirstNonNullValue {
    param(
        [object[]]$Values
    )

    foreach ($value in $Values) {
        if ($null -ne $value -and $value.ToString().Trim().Length -gt 0) {
            return $value
        }
    }

    return $null
}

function Get-HostEntry {
    param(
        [string]$HostID
    )

    if (-not $HostID) {
        return $null
    }

    if ($HostLookup.ContainsKey($HostID)) {
        return $HostLookup[$HostID]
    }

    return $null
}

# Build Hosts File

$HostLookup = @{}
$HostCsv    = @()

foreach ($hostNode in $xml.Settings.Hosts.ChildNodes) {

    $hostRow = [pscustomobject]@{
        HostID                  = $hostNode.ID
        HostName                = $hostNode.Name
        HostType                = $hostNode.LocalName
        Host                    = Get-FirstNonNullValue -Values @($hostNode.Host, $hostNode.UNC, $hostNode.Path)
        Port                    = $hostNode.Port
        Username                = Get-FirstNonNullValue -Values @($hostNode.Username, $hostNode.DefUsername)
        Disabled                = $hostNode.Disabled
        TenantName              = $hostNode.TenantName
        Site                    = $hostNode.Site
        SiteUrlPrefix           = $hostNode.SiteUrlPrefix
        UsingAppAuthentication  = $hostNode.UsingAppAuthentication
        ClientID                = $hostNode.ClientID
        TenantID                = $hostNode.TenantID
        DefDocumentLibrary      = $hostNode.DefDocumentLibrary
    }

    $HostLookup[$hostNode.ID] = $hostRow
    $HostCsv += $hostRow
}

$HostCsv |
    Sort-Object HostType, HostName |
    Export-Csv (Join-Path $OutDir "MOVEit_Hosts.csv") -NoTypeInformation

# Build Schedules for Tasks File

function Get-ScheduleRow {
    param ($Schedule)

    # Days of week -- SelectNodes returns one XmlElement per <DayOfWeek> node
    $daysOfWeek = ($Schedule.SelectNodes('Days/DayOfWeek') |
                   ForEach-Object { $_.InnerText }) -join ","

    # Day of month -- same pattern
    $dayOfMonth = ($Schedule.SelectNodes('Days/DayOfMonth') |
                   ForEach-Object { $_.InnerText }) -join ","

    # Intervals -- a schedule can have multiple <Interval> elements (up to 6 seen
    # in this export).  Collect all start/end/frequency values and join with ";"
    # so a reader can see the full picture in one cell.
    $intervals  = $Schedule.SelectNodes('Frequency/Interval')
    $startTimes = ($intervals | ForEach-Object { $_.GetAttribute('StartTime')    }) -join ";"
    $endTimes   = ($intervals | ForEach-Object { $_.GetAttribute('EndTime')      }) -join ";"
    $everyMins  = ($intervals | ForEach-Object { $_.GetAttribute('EveryMinutes') }) -join ";"

    return [pscustomobject]@{
        OnlyUntilFirstSuccess  = $Schedule.GetAttribute('OnlyUntilFirstSuccess')
        FailIfNoSuccessInSched = $Schedule.GetAttribute('FailIfNoSuccessInSched')
        RunEvenIfNotif         = $Schedule.GetAttribute('RunEvenIfNotif')
        DaysOfWeek             = $daysOfWeek
        DayOfMonth             = $dayOfMonth
        StartTime              = $startTimes
        EndTime                = $endTimes
        EveryMinutes           = $everyMins
    }
}

# Export Tasks With Schedules
$TaskCsv = @()

foreach ($task in $xml.Settings.Tasks.Task) {

    # Description and Notes live in an optional <Info> child element
    $description = $task.Info.Description
    $notes       = $task.Info.Notes

    # Use XPath to retrieve schedule elements -- avoids the PS XML adapter
    # double-wrapping bug where @($task.Schedules.Schedule) can return a
    # nested object[] when there is exactly one <Schedule> child.
    $scheduleNodes = $task.SelectNodes('Schedules/Schedule')

    $taskSchedules =
        if ($scheduleNodes.Count -gt 0) {
            $scheduleNodes | ForEach-Object { Get-ScheduleRow -Schedule $_ }
        }
        else {
            @(
                [pscustomobject]@{
                    OnlyUntilFirstSuccess  = ""
                    FailIfNoSuccessInSched = ""
                    RunEvenIfNotif         = ""
                    DaysOfWeek             = ""
                    DayOfMonth             = ""
                    StartTime              = ""
                    EndTime                = ""
                    EveryMinutes           = ""
                }
            )
        }

    foreach ($schedule in $taskSchedules) {

        foreach ($source in $task.SelectNodes('Source')) {
            foreach ($dest in $task.SelectNodes('.//Destination')) {

                $sourceHostEntry = Get-HostEntry -HostID $source.HostID
                $destHostEntry   = Get-HostEntry -HostID $dest.HostID

                $TaskCsv += [pscustomobject]@{
                    TaskID                      = $task.ID
                    TaskName                    = $task.Name
                    Active                      = $task.Active
                    AutoRetry                   = $task.AR
                    Description                 = $description
                    Notes                       = $notes
                    SchedOnlyUntilFirstSuccess  = $schedule.OnlyUntilFirstSuccess
                    SchedFailIfNoSuccessInSched = $schedule.FailIfNoSuccessInSched
                    SchedRunEvenIfNotif         = $schedule.RunEvenIfNotif
                    SchedDaysOfWeek             = $schedule.DaysOfWeek
                    SchedDayOfMonth             = $schedule.DayOfMonth
                    SchedStartTime              = $schedule.StartTime
                    SchedEndTime                = $schedule.EndTime
                    SchedEveryMinutes           = $schedule.EveryMinutes
                    SourceType                  = $source.Type
                    SourceHostID                = $source.HostID
                    SourceHostName              = if ($sourceHostEntry) { $sourceHostEntry.HostName } else { "" }
                    SourcePath                  = Get-FirstNonNullValue -Values @($source.Path, $source.FolderName)
                    SourceFileMask              = $source.FileMask
                    SourceExcludeMask           = $source.ExFile
                    SourceDeleteOrig            = $source.DeleteOrig
                    SourceNewFilesOnly          = $source.NewFilesOnly
                    SourceSearchSubdirs         = $source.SearchSubdirs
                    DestinationType             = $dest.Type
                    DestinationHostID           = $dest.HostID
                    DestinationHostName         = if ($destHostEntry) { $destHostEntry.HostName } else { "" }
                    DestinationPath             = Get-FirstNonNullValue -Values @($dest.Path, $dest.FolderName)
                    DestinationFileName         = $dest.FileName
                    DestinationAddressTo        = $dest.AddressTo
                    DestinationSubject          = $dest.Subject
                    DestinationOverwrite        = $dest.OverwriteOrig
                    DestinationForceDir         = $dest.ForceDir
                    DestinationZip              = $dest.Zip
                }
            }
        }
    }
}

$TaskCsv |
    Sort-Object TaskName, SchedDaysOfWeek, SourceHostName, DestinationHostName |
    Export-Csv (Join-Path $OutDir "MOVEit_Tasks.csv") -NoTypeInformation

# Host → Task Dependency Report
$HostTaskDeps = @()

foreach ($task in $xml.Settings.Tasks.Task) {

    $taskId   = $task.ID
    $taskName = $task.Name
    $active   = $task.Active

    foreach ($src in $task.SelectNodes('Source')) {

        $hostEntry = Get-HostEntry -HostID $src.HostID

        $HostTaskDeps += [pscustomobject]@{
            HostID              = $src.HostID
            HostName            = if ($hostEntry) { $hostEntry.HostName } else { "" }
            HostType            = if ($hostEntry) { $hostEntry.HostType } else { "" }
            TaskID              = $taskId
            TaskName            = $taskName
            TaskActive          = $active
            UsageType           = "Source"
            PathOrAddress       = Get-FirstNonNullValue -Values @($src.Path, $src.FolderName)
            FileMaskOrName      = $src.FileMask
            ExcludeMask         = $src.ExFile
            DeleteOrig          = $src.DeleteOrig
            NewFilesOnly        = $src.NewFilesOnly
            SearchSubdirs       = $src.SearchSubdirs
            NotifAddressTo      = ""
            NotifSubject        = ""
            NotifDoIfFailure    = ""
            NotifDoIfSuccess    = ""
            NotifDoIfNoAction   = ""
        }
    }

    foreach ($dst in $task.SelectNodes('.//Destination')) {

        $hostEntry = Get-HostEntry -HostID $dst.HostID

        $HostTaskDeps += [pscustomobject]@{
            HostID          = $dst.HostID
            HostName        = if ($hostEntry) { $hostEntry.HostName } else { "" }
            HostType        = if ($hostEntry) { $hostEntry.HostType } else { "" }
            TaskID          = $taskId
            TaskName        = $taskName
            TaskActive      = $active
            UsageType       = "Destination"
            PathOrAddress   = Get-FirstNonNullValue -Values @($dst.Path, $dst.FolderName)
            FileMaskOrName  = $dst.FileName
            ExcludeMask     = ""
            DeleteOrig      = ""
            NewFilesOnly    = ""
            SearchSubdirs   = ""
            NotifAddressTo    = $dst.AddressTo
            NotifSubject      = $dst.Subject
            NotifDoIfFailure  = ""
            NotifDoIfSuccess  = ""
            NotifDoIfNoAction = ""
        }
    }

    foreach ($na in @($task.NextActions.NextAction)) {

        if (-not $na.HostID) { continue }

        $hostEntry = Get-HostEntry -HostID $na.HostID

        $HostTaskDeps += [pscustomobject]@{
            HostID              = $na.HostID
            HostName            = if ($hostEntry) { $hostEntry.HostName } else { "" }
            HostType            = if ($hostEntry) { $hostEntry.HostType } else { "" }
            TaskID              = $taskId
            TaskName            = $taskName
            TaskActive          = $active
            UsageType           = "NextAction-$($na.Type)"
            PathOrAddress       = ""
            FileMaskOrName      = ""
            ExcludeMask         = ""
            DeleteOrig          = ""
            NewFilesOnly        = ""
            SearchSubdirs       = ""
            NotifAddressTo      = $na.AddressTo                                    # NEW
            NotifSubject        = $na.Subject                                      # NEW
            NotifDoIfFailure    = $na.DoIfFailure                                  # NEW
            NotifDoIfSuccess    = $na.DoIfSuccess                                  # NEW
            NotifDoIfNoAction   = $na.DoIfNoAction                                 # NEW
        }
    }
}

$HostTaskDeps |
    Sort-Object HostName, UsageType, TaskName |
    Export-Csv (Join-Path $OutDir "MOVEit_Host_Task_Dependencies.csv") -NoTypeInformation

# Display completion message and output file names
Write-Host "Export complete:"
Write-Host " - MOVEit_Hosts.csv"
Write-Host " - MOVEit_Tasks.csv"
Write-Host " - MOVEit_Host_Task_Dependencies.csv"
