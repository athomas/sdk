// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:expect/expect.dart';
import 'package:async_helper/async_helper.dart';
import 'package:compiler/src/compiler.dart';
import 'package:compiler/src/elements/entities.dart';
import 'package:compiler/src/inferrer/typemasks/masks.dart';
import 'package:compiler/src/types/types.dart';
import 'package:compiler/src/world.dart' show JClosedWorld;
import '../inference/type_mask_test_helper.dart';
import '../helpers/memory_compiler.dart';

const Map<String, String> MEMORY_SOURCE_FILES = const {
  'main.dart': r"""
import 'package:expect/expect.dart';

int method(String arg) => arg.length;

@AssumeDynamic()
int methodAssumeDynamic(String arg) => arg.length;

@TrustTypeAnnotations()
int methodTrustTypeAnnotations(String arg) => arg.length;

@NoInline()
int methodNoInline(String arg) => arg.length;

@NoInline() @TrustTypeAnnotations()
int methodNoInlineTrustTypeAnnotations(String arg) => arg.length;

@AssumeDynamic() @TrustTypeAnnotations()
int methodAssumeDynamicTrustTypeAnnotations(String arg) => arg.length;


void main(List<String> args) {
  print(method(args[0]));
  print(methodAssumeDynamic('foo'));
  print(methodTrustTypeAnnotations(42 as dynamic));
  print(methodTrustTypeAnnotations("fourtyTwo"));
  print(methodNoInline('bar'));
  print(methodNoInlineTrustTypeAnnotations(42 as dynamic));
  print(methodNoInlineTrustTypeAnnotations("fourtyTwo"));
  print(methodAssumeDynamicTrustTypeAnnotations(null));
}
"""
};

main() {
  asyncTest(() async {
    await runTest();
  });
}

runTest() async {
  CompilationResult result =
      await runCompiler(memorySourceFiles: MEMORY_SOURCE_FILES);
  Compiler compiler = result.compiler;
  JClosedWorld closedWorld = compiler.backendClosedWorldForTesting;
  Expect.isFalse(compiler.compilationFailed, 'Unsuccessful compilation');
  Expect.isNotNull(closedWorld.commonElements.expectNoInlineClass,
      'NoInlineClass is unresolved.');
  Expect.isNotNull(closedWorld.commonElements.expectTrustTypeAnnotationsClass,
      'TrustTypeAnnotations is unresolved.');
  Expect.isNotNull(closedWorld.commonElements.expectAssumeDynamicClass,
      'AssumeDynamicClass is unresolved.');

  void testTypeMatch(FunctionEntity function, TypeMask expectedParameterType,
      TypeMask expectedReturnType, GlobalTypeInferenceResults results) {
    compiler.codegenWorldBuilder.forEachParameterAsLocal(function,
        (Local parameter) {
      TypeMask type = results.resultOfParameter(parameter);
      Expect.equals(
          expectedParameterType, simplify(type, closedWorld), "$parameter");
    });
    if (expectedReturnType != null) {
      TypeMask type = results.resultOfMember(function).returnType;
      Expect.equals(
          expectedReturnType, simplify(type, closedWorld), "$function");
    }
  }

  void test(String name,
      {bool expectNoInline: false,
      bool expectTrustTypeAnnotations: false,
      TypeMask expectedParameterType: null,
      TypeMask expectedReturnType: null,
      bool expectAssumeDynamic: false}) {
    LibraryEntity mainApp = closedWorld.elementEnvironment.mainLibrary;
    FunctionEntity method =
        closedWorld.elementEnvironment.lookupLibraryMember(mainApp, name);
    Expect.isNotNull(method);
    Expect.equals(
        expectNoInline,
        closedWorld.annotationsData.nonInlinableFunctions.contains(method),
        "Unexpected annotation of @NoInline() on '$method'.");
    Expect.equals(
        expectTrustTypeAnnotations,
        closedWorld.annotationsData.trustTypeAnnotationsMembers
            .contains(method),
        "Unexpected annotation of @TrustTypeAnnotations() on '$method'.");
    Expect.equals(
        expectAssumeDynamic,
        closedWorld.annotationsData.assumeDynamicMembers.contains(method),
        "Unexpected annotation of @AssumeDynamic() on '$method'.");
    GlobalTypeInferenceResults results =
        compiler.globalInference.resultsForTesting;
    if (expectTrustTypeAnnotations && expectedParameterType != null) {
      testTypeMatch(method, expectedParameterType, expectedReturnType, results);
    } else if (expectAssumeDynamic) {
      testTypeMatch(
          method, closedWorld.abstractValueDomain.dynamicType, null, results);
    }
  }

  TypeMask jsStringType = closedWorld.abstractValueDomain.stringType;
  TypeMask jsIntType = closedWorld.abstractValueDomain.intType;
  TypeMask coreStringType =
      new TypeMask.subtype(closedWorld.commonElements.stringClass, closedWorld);

  test('method');
  test('methodAssumeDynamic', expectAssumeDynamic: true);
  test('methodTrustTypeAnnotations',
      expectTrustTypeAnnotations: true, expectedParameterType: jsStringType);
  test('methodNoInline', expectNoInline: true);
  test('methodNoInlineTrustTypeAnnotations',
      expectNoInline: true,
      expectTrustTypeAnnotations: true,
      expectedParameterType: jsStringType,
      expectedReturnType: jsIntType);
  test('methodAssumeDynamicTrustTypeAnnotations',
      expectAssumeDynamic: true,
      expectTrustTypeAnnotations: true,
      expectedParameterType: coreStringType);
}
