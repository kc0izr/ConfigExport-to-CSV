# ConfigExport-to-CSV
Parse MOVEit Automation ConfigExport to CSV Files
    - MOVEit Hosts
    - MOVEit Tasks
    - MOVEit Hosts to Tasks Dependencies

Export the Configuration of the MOVEit Automation to XML file and save it to a known directory.

Instructions for use below:

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

