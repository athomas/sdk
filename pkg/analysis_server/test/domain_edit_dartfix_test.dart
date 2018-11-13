// Copyright (c) 2018, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/protocol/protocol.dart';
import 'package:analysis_server/protocol/protocol_generated.dart';
import 'package:analysis_server/src/edit/edit_dartfix.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:linter/src/rules.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'analysis_abstract.dart';

main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(EditDartfixDomainHandlerTest);
  });
}

@reflectiveTest
class EditDartfixDomainHandlerTest extends AbstractAnalysisTest {
  String libPath;

  void expectEdits(List<SourceFileEdit> fileEdits, String expectedSource) {
    expect(fileEdits, hasLength(1));
    expect(fileEdits[0].file, testFile);
    List<SourceEdit> edits = fileEdits[0].edits;
    String source = testCode;
    for (SourceEdit edit in edits) {
      source = edit.apply(source);
    }
    expect(source, expectedSource);
  }

  void expectSuggestion(DartFixSuggestion suggestion, String partialText,
      int offset, int length) {
    expect(suggestion.description, contains(partialText));
    expect(suggestion.location.offset, offset);
    expect(suggestion.location.length, length);
  }

  Future<EditDartfixResult> performFix() async {
    final request = new Request(
        '33', 'edit.dartfix', new EditDartfixParams([libPath]).toJson());

    final response = await new EditDartFix(server, request).compute();
    expect(response.id, '33');

    return EditDartfixResult.fromResponse(response);
  }

  @override
  void setUp() {
    super.setUp();
    registerLintRules();
    createProject();
    libPath = resourceProvider.convertPath('/project/lib');
    testFile = resourceProvider.convertPath('/project/lib/fileToBeFixed.dart');
  }

  test_dartfix_convertClassToMixin() async {
    addTestFile('''
class A {}
class B extends A {}
class C with B {}
    ''');
    EditDartfixResult result = await performFix();
    expect(result.suggestions, hasLength(1));
    expectSuggestion(result.suggestions[0], 'mixin', 17, 1);
    expectEdits(result.edits, '''
class A {}
mixin B implements A {}
class C with B {}
    ''');
  }

  test_dartfix_convertToIntLiteral() async {
    addTestFile('''
const double myDouble = 42.0;
    ''');
    EditDartfixResult result = await performFix();
    expect(result.suggestions, hasLength(1));
    expectSuggestion(result.suggestions[0], 'int literal', 24, 4);
    expectEdits(result.edits, '''
const double myDouble = 42;
    ''');
  }

  test_dartfix_moveTypeArgumentToClass() async {
    addTestFile('''
class A<T> { A.from(Object obj) { } }
main() {
  print(new A.from<String>([]));
}
    ''');
    EditDartfixResult result = await performFix();
    expect(result.suggestions, hasLength(1));
    expectSuggestion(result.suggestions[0], 'type arguments', 65, 8);
    expectEdits(result.edits, '''
class A<T> { A.from(Object obj) { } }
main() {
  print(new A<String>.from([]));
}
    ''');
  }
}
