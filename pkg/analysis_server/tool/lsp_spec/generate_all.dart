// Copyright (c) 2018, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import 'codegen_dart.dart';
import 'markdown.dart';
import 'typescript.dart';

main() async {
  final String script = Platform.script.toFilePath();
  // 3x parent = file -> lsp_spec -> tool -> analysis_server.
  final String packageFolder = new File(script).parent.parent.parent.path;
  final String outFolder = path.join(packageFolder, 'lib', 'lsp_protocol');
  new Directory(outFolder).createSync();

  final String spec = await fetchSpec();
  final List<ApiItem> types = extractAllTypes(extractTypeScriptBlocks(spec));
  types.addAll(_getSpecialCaseTypes());
  final String output = generateDartForTypes(types);

  new File(path.join(outFolder, 'protocol_generated.dart'))
      .writeAsStringSync(_generatedFileHeader + output);
}

const _generatedFileHeader = '''
// Copyright (c) 2018, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// This file has been automatically generated. Please do not edit it manually.
// To regenerate the file, use the script
// "pkg/analysis_server/tool/lsp_spec/generate_all.dart".

import 'dart:core' hide deprecated;
import 'dart:core' as core show deprecated;
import 'package:analysis_server/lsp_protocol/protocol_special.dart';

''';

final Uri specUri = Uri.parse(
    'https://raw.githubusercontent.com/Microsoft/language-server-protocol/gh-pages/specification.md');

Future<String> fetchSpec() async {
  final resp = await http.get(specUri);
  return resp.body;
}

/// Fabricates types for things that don't parse well from the TS spec,
/// such as anonymous types:
///     type MarkedString = string | { language: string; value: string };
List<ApiItem> _getSpecialCaseTypes() {
  return [
    // For MarkedString, we drop the string-only version since we can always
    // supply a language and it makes the type a little simpler.
    new Interface('MarkedString', null, [], [
      new Field('language', null, ['string'], false, false),
      new Field('value', null, ['string'], false, false)
    ])
  ];
}
