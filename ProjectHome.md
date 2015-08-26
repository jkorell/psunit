A simple unit testing framework for powershell.

For example, here is a test for the code at http://tasteofpowershell.blogspot.com/2008/10/defrag-your-servers-remotely-with.html.

```
. .\unittest.ps1
. .\Run-Defrag.ps1

function TestRunDefrag() {
  MockFunction 'Get-WmiObject' 'Write-Host'
  $volume = MockObject
  $volume.AddMethod('Defrag')
  
  $volume.Defrag($false).AndReturn((MockObject -ReturnValue 5))
  $query = "Select * from Win32_Volume where DriveType = 3 And DriveLetter LIKE 'c:%'" 
  Get-WmiObject -Query $query -ComputerName 'my-server' -Return $volume 
  Write-Host 'Defragmenting ...' -noNewLine
  Write-Host $defrag_messages[5]
  
  PlaybackMocks
  Run-Defrag 'my-server' 'c:'
}

RunTests
```