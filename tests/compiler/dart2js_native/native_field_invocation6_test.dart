// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:_js_helper";
import "package:expect/expect.dart";

makeA() native ;
nativeFirst(x, y) native ;

void setup() native """
nativeFirst = function(x, y) { return x; }

function A() {}
makeA = function() { return new A; }
""";

@Native("A")
class A {
  var _foo;

  get foo => _foo;

  init() {
    _foo = () => 42;
  }
}

class B {
  var foo = 499;
}

class C {
  foo() => 499;
}

class D {
  var foo = () => 499;
}

main() {
  setup();
  var a = makeA();
  a.init();
  var b = new B();
  var c = new C();
  var d = new D();
  a = nativeFirst(a, b);
  a = nativeFirst(a, c);
  a = nativeFirst(a, d);
  // The variable a is still an instance of class A, but dart2js can't infer
  // that anymore.
  Expect.equals(42, a.foo());
}
