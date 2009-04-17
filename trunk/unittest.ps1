# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Author: Stephen Ng <stephen5.ng@gmail.com>
#
# Unit test support for Powershell
#

Set-PSDebug -strict
$ReportErrorShowStackTrace = $True

# These might get mocked; save them away.
$WRITE_HOST = Get-Command Write-Host
$REMOVE_ITEM = Get-Command Remove-Item
$TEST_PATH = Get-Command Test-Path

$MSG_CALLED_WITH_NONE = 'called with no arguments, but expected:'

$TEST_MODE = $True

$expectations = @{}
$returns = @{}
$mock_objects = @()
$mock_functions = @()
$original_functions = @{}

function Pop($stack) {
  ,$stack[1..$stack.length]
}

function _Error($msg) {
  LogPosition
  throw "$msg"
}

function _MethodCall($method_name, $method_args) {
  $hash = $this.GetHashCode()
  $key = $method_name + $hash
  if ($this.RecordMode) {
    $script:expectations[$key] += @(,@($method_args))
    $this
  } else {
    $expectation = $script:expectations[$key][0]
    if (($method_args.length -ne 0) -and ($expectation.length -ne 0)) {
      AssertEquals $expectation $method_args
    } elseif (($method_args.length -eq 0) -and ($expectation.length -ne 0)) {
      _Error ("$method_name $MSG_CALLED_WITH_NONE $expectation.")
    } elseif (($method_args.length -ne 0) -and 
      ($expectation.length -eq 0)) {
      _Error ("$method_name called with $method_args, but expected none.")
    }

    $script:expectations[$key] = Pop $script:expectations[$key]

    if ($script:returns[$hash].length -gt 0) {
      $script:returns[$hash][0]
      $script:returns[$hash] = Pop $script:returns[$hash]
    }
  }
}

function _AddMethod($method_name) {
  $method_call = $ExecutionContext.InvokeCommand.NewScriptBlock(
    '_MethodCall ' + $method_name + ' $args')
  $this | Add-Member scriptmethod -force -name $method_name -value $method_call
}


function _AndReturn($return_value) {
  $script:returns[$this.GetHashCode()] += ,($return_value)
}

function MockObject() {
  # Create a new mock object.
  #
  # Add noteproperties by passing in -PropertyName VALUE
  # Declare new methods by calling $obj.AddMethod(METHODNAME)
  # Set methods expectations using $obj.MyMethod(arg1, arg2)
  # Set expected return values with AndReturn: 
  #   $obj.MyMethod(arg1).AndReturn($foo)

  $mo = New-Object System.Object
  AddNotePropertiesToMockObject $mo $args
  $mo | Add-Member scriptmethod AddMethod { _AddMethod $args[0] }
  $mo | Add-Member scriptmethod AndReturn { _AndReturn $args[0] }
  $mo | Add-Member noteproperty RecordMode -Value $True
  $script:mock_objects += $mo
  $mo
}

function AddNotePropertiesToMockObject($obj, $members) {
  # Add note properties to an object.  Members is an array containing 
  # ('-ValueName', 'property', '-ValueName2', 'property2', ...)
  # Usually you don't need to call this function because you can set these
  # values in the initial call to MockObject.

  for ($i = 0; $i -lt $members.length; $i+=2) {
    $obj | Add-Member noteproperty $members[$i].Substring(1) `
      -value $members[$i+1]
  }
}

function _RecordExpectations() {
  $command_name = $MyInvocation.MyCommand.Name

  # Peel off "-return #return_value" from end of argument list.
  if (($args.length -ge 2) -and
      ($args[$args.length-2] -ieq '-return')) {
    $script:returns[$command_name] += ,$args[-1]
    if ($args.length -ge 3) {
      $expected_args = @(,@($args[0..($args.length-3)]))
    }
    else {
      $expected_args = @(,@())
    }
  } else {
    $expected_args = @(,@($args))
  }

  $script:expectations[$command_name] += $expected_args
}


function MockFunction() {
  # Declare mock functions:  MockFunction 'FunctionName1' 'FunctionName2' ... 

  foreach ($n in $args) {
    if (&$TEST_PATH "function:$n") {
      $script:original_functions[$n] = (get-item "function:$n").Definition
    }
    $script:mock_functions += (New-Item "function:script:$n" `
      -value $function:_RecordExpectations -force)
  }
}


function _CheckExpectations() {
  $command_name = $MyInvocation.MyCommand.Name
  $cmd_expects = $script:expectations[$command_name]
  if ($cmd_expects.length -le 0) {
    Get-Variable MyInvocation -scope 0
    _Error "CheckExpectations Fail--unexpected call:"
  }

  AssertEquals $cmd_expects[0] $args
  $script:expectations[$command_name] = Pop $script:expectations[$command_name]

  if ($script:returns[$command_name].length -gt 0) {
    $script:returns[$command_name][0]

    $script:returns[$command_name] = Pop $script:returns[$command_name]
  }
}

function PlaybackMocks() {
    foreach ($fn_name in $script:mock_functions) {
    [void](New-Item "function:script:$fn_name" -value `
      $function:_CheckExpectations -force)
  }
  foreach ($mock_object in $script:mock_objects) {
    $mock_object.RecordMode = $False
  }
}

function RemoveMocks() {
  foreach ($fn in $script:expectations.keys) {
    if ($script:expectations[$fn].length -gt 0) {
      $expected_args = ""
      foreach ($arg in $script:expectations[$fn]) {
        $expected_args += "$arg,"
      }
      _Error ("Expected call to " + $fn + "(" + $expected_args + ")")
    }
  }

  foreach ($fn_name in $script:mock_functions) {
    &$REMOVE_ITEM "function:$fn_name"
    if (&$TEST_PATH "function:script:$fn_name") {
       write-host "Remove $fn_name failed."
       exit 1
    }
  }
  $script:mock_functions = @()
  $script:mock_objects = @()

  foreach ($fn_name in $script:original_functions.keys) {
    [void](New-Item -path "function:script:$fn_name" `
      -value $script:original_functions[$fn_name])
  }
  $script:original_functions = @{}

  $script:expectations = @{}
  $script:returns = @{}
}


function LogPosition() {
  $ErrorActionPreference = 'Continue'
  &$WRITE_HOST ((Get-Variable -scope 1 MyInvocation).Value.PositionMessage)
  &$WRITE_HOST ((Get-Variable -scope 2 MyInvocation).Value.PositionMessage)
  &$WRITE_HOST ((Get-Variable -scope 3 MyInvocation).Value.PositionMessage)
  &$WRITE_HOST ((Get-Variable -scope 4 MyInvocation).Value.PositionMessage)
  &$WRITE_HOST ((Get-Variable -scope 5 MyInvocation).Value.PositionMessage)
  $ErrorActionPreference = 'Stop'
}

function Log([string]$text) {
  &$WRITE_HOST $text
}

function AssertTrue($bool) {
  if (!$bool) {
    _Error "AssertTrue Fail:"
  }
}

function AssertFalse($bool) {
  if ($bool) {
    _Error "AssertFalse Fail:"
  }
}

function Compare($x, $y) {
  if ($x -isnot [array] -and $y -isnot [array]) {
    $x -eq $y
    return
  }

  if (($x -is [array] -and $y -isnot [array]) -or 
      ($x -isnot [array] -and $y -is [array])) {
    $False
    return
  }

  if ($x.length -ne $y.length) {
    $False
    return
  }

  $enum_x = $x.GetEnumerator()
  $enum_y = $y.GetEnumerator()
  while ($enum_x.MoveNext() -and $enum_y.MoveNext()) {
    if (!(Compare $enum_x.Current $enum_y.Current)) {
      $False
      return
    }
  }
  $True
}

function AssertEquals($x, $y) {
  # Powershell apparently doesn't have a primitive for comparing any objects.
  if (!(Compare $x $y)) {
    _Error "Expected $x, got $y."
  }
}

function RunTests() {
  $tests = Get-Command -CommandType function "Test*"
  foreach ($test in $tests) {
    Log "running $test."
    & $test
    RemoveMocks
  }
}
