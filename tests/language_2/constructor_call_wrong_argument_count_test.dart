// Copyright (c) 2011, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

class Stockhorn {
  Stockhorn(int a);
}

main() {
  new Stockhorn(1);
  new Stockhorn(); //# 01: compile-time error
}
