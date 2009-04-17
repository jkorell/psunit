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
# Unit tests for Unit tests for Powershell
#

Set-PSDebug -strict

. .\unittest.ps1

$exit_count = 0

$error_msg = ''

function TestPop() {
  $stack = @(1,2,3)
  $stack = Pop $stack

  AssertEquals @(2,3) $stack

  $stack = @(1,2)
  $stack = Pop $stack
  AssertEquals @(2) $stack

  $stack = @(1)
  $stack = Pop $stack
  AssertEquals @() $stack
}


function MockErrorHandling() {
  $script:error_fn = $function:_Error
  $function:_Error = {
    $script:error_msg = $args[0]
  }
}

function UnmockErrorHandling() {
  $function:_Error = $script:error_fn
}

function Error() {
  $script:exit_count += 1
}

$foo_called = 0
function foo() {
  $script:foo_called += 1
}

function TestCompare() {
  AssertTrue (Compare 1 1)
  AssertFalse (Compare 1 2)

  AssertTrue (Compare $null $null)
  AssertFalse (Compare $null 1)

  $obj1 = New-Object System.Object
  AssertTrue (Compare $obj1 $obj1)

  $obj2 = New-Object System.Object
  AssertFalse (Compare $obj1 $obj2)

  AssertFalse (Compare @(,$obj1) @(,$obj2))

  # -eq will find everything on the left that matches the elt on the right :-(.
  AssertFalse (Compare @(3,4) 3)

  AssertFalse (Compare (1,2,3,4) (1,2,99,4))

  AssertFalse (Compare (1,2,3) (1,2,3,4))
}


function TestMultipleReturnsMultipleFunctions() {
  MockFunction 'Foo' 'Bar'

  Foo -Return 'woof1'
  Foo -Return 'woof2'
  Foo -Return 'woof3'

  Bar -Return 'meow'
  Bar -Return 'meow'

  PlaybackMocks

  AssertEquals 'woof1' (Foo)
  AssertEquals 'woof2' (Foo)
  AssertEquals 'woof3' (Foo)
  AssertEquals 'meow' (Bar)
  AssertEquals 'meow' (Bar)
}

function TestRestoreMockedFunction() {
  foo
  MockFunction 'foo'

  RemoveMocks
  foo
}


function TestMockFunctionNoArgs() {
  MockFunction 'Bow'

  Bow -Return 'wow'

  PlaybackMocks

  AssertEquals 'wow' (Bow)
}

function TestMockFunction() {
  MockFunction 'mock_fn'
  mock_fn 'arg1' -Return 'some_return_val'
  mock_fn 'arg2' -Return 'some_other_return_val'

  PlaybackMocks

  AssertEquals 'some_return_val' (mock_fn 'arg1')
  AssertEquals 'some_other_return_val' (mock_fn 'arg2')
}


function TestMockFunctionNoCall() {
#  MockFunction 'mock_fn'

#  PlaybackMocks
  #should give an error
#  mock_fn
}


function TestMockFunctionTwoArgs() {
  MockFunction 'mock_fn'
  mock_fn 'arg1' 'arg2' -Return 'some_return_val'

  PlaybackMocks

  AssertEquals 'some_return_val' (mock_fn 'arg1' 'arg2')
}

function TestMockFunctionNoReturn() {
  MockFunction 'mock_fn'
  mock_fn 'arg1'
  mock_fn 'arg2'

  PlaybackMocks

  mock_fn 'arg1'
  mock_fn 'arg2'
}

function TestMockFunctionTwoArgsNoReturn() {
  MockFunction 'mock_fn'
  mock_fn 'arg1' 'arg2'

  PlaybackMocks

  mock_fn 'arg1' 'arg2'
}

function TestMultipleMockFunctions() {
  MockFunction 'mock_fn1' 'mock_fn2'
  mock_fn1 'arg1' -Return 'some_return_val'
  mock_fn2 'arg1' -Return 'some_other_return_val'

  PlaybackMocks

  AssertEquals 'some_return_val' (mock_fn1 'arg1')
  AssertEquals 'some_other_return_val' (mock_fn2 'arg1')
}

function TestMockFunctionArgCountMismatch() {
  MockFunction 'mock_fn'
  mock_fn -arg1 'arg1' -arg2 'arg2'

  PlaybackMocks

  MockErrorHandling
  mock_fn -arg1 'arg1'
  UnmockErrorHandling

  AssertEquals 'Expected -arg1 arg1 -arg2 arg2, got -arg1 arg1.' `
    $script:error_msg

}

function TestMockNoteProperties() {
  $cat = MockObject -Color 'black' -Texture 'furry'

  PlaybackMocks
  AssertEquals 'black' $cat.Color
  AssertEquals 'furry' $cat.Texture
}

function TestOverrideMethod() { 
  $obj = MockObject
  $obj.AddMethod('GetType')
#  $obj | Add-Member scriptmethod -force -name 'GetType' -value {}
}

function TestNoArgs() {
  $dog = MockObject
  $dog.AddMethod('Eat')
  [void]$dog.Eat()

  PlaybackMocks
  $dog.Eat()
}

function TestMethodCall_ExpectOneGotNone() {
  $dog = MockObject
  $dog.AddMethod('Eat')
  [void]$dog.Eat('chow')

  PlaybackMocks
  MockErrorHandling
  [void]$dog.Eat()
  UnmockErrorHandling

  AssertEquals "Eat $MSG_CALLED_WITH_NONE chow." $script:error_msg 
}

function TestMethodCall_ExpectNoneGotOne() {
  $dog = MockObject
  $dog.AddMethod('Eat')
  [void]$dog.Eat()

  PlaybackMocks
  MockErrorHandling
  [void]$dog.Eat('bone')
  UnmockErrorHandling

  AssertEquals "Eat called with bone, but expected none." $script:error_msg 
}

function TestOneMockObject() {
  $obj = MockObject

  $obj.AddMethod('SomeNewMethod')
  $obj.SomeNewMethod(1,2,3).AndReturn(12)

  PlaybackMocks
  AssertEquals 12 $obj.SomeNewMethod(1,2,3)
}

function TestMockObject_ArgCountMismatch() {
  $obj = MockObject
  $obj.AddMethod('Foo')
  [void]$obj.Foo(1,2)

  PlaybackMocks

  MockErrorHandling
  [void]$obj.Foo(1)
  UnmockErrorHandling
  AssertEquals 'Expected 1 2, got 1.' $script:error_msg 
}

function TestOneMockObjectTwoCalls() {
  $obj = MockObject

  $obj.AddMethod('SomeNewMethod')
  $obj.SomeNewMethod(1,2,3).AndReturn(12)
  $obj.SomeNewMethod(4,5,6).AndReturn(99)

  PlaybackMocks
  AssertEquals 12 $obj.SomeNewMethod(1,2,3)
  AssertEquals 99 $obj.SomeNewMethod(4,5,6)
}

function TestTwoMockObjects() {
  $dog = MockObject
  $cat = MockObject

  $dog.AddMethod('Fetch')
  $dog.Fetch('sticks', 'frisbee').AndReturn('woof')
  $dog.AddMethod('Eat')
  $dog.Eat('chow').AndReturn('yum!')

  $cat.AddMethod('Suggest')
  $cat.Suggest('come', 'here').AndReturn('forget it')
  $cat.AddMethod('Eat')
  $cat.Eat('tuna').AndReturn('whatever')

  PlaybackMocks

  AssertEquals 'woof' $dog.Fetch('sticks', 'frisbee')
  AssertEquals 'forget it' $cat.Suggest('come', 'here')
  AssertEquals 'yum!' $dog.Eat('chow')
  AssertEquals 'whatever' $cat.Eat('tuna')
}

function TestAssertEquals() {
#  AssertEquals $null 3
}


RunTests

