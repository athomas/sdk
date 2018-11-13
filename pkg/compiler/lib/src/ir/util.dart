// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:kernel/ast.dart' as ir;
import 'package:kernel/class_hierarchy.dart' as ir;
import 'package:kernel/core_types.dart' as ir;
import 'package:kernel/type_environment.dart' as ir;

import '../common.dart';
import '../elements/entities.dart';

/// Comparator for the canonical order or named arguments.
// TODO(johnniwinther): Remove this when named parameters are sorted in dill.
int namedOrdering(ir.VariableDeclaration a, ir.VariableDeclaration b) {
  return a.name.compareTo(b.name);
}

SourceSpan computeSourceSpanFromTreeNode(ir.TreeNode node) {
  // TODO(johnniwinther): Use [ir.Location] directly as a [SourceSpan].
  Uri uri;
  int offset;
  while (node != null) {
    if (node.fileOffset != ir.TreeNode.noOffset) {
      offset = node.fileOffset;
      // @patch annotations have no location.
      uri = node.location?.file;
      break;
    }
    node = node.parent;
  }
  if (uri != null) {
    return new SourceSpan(uri, offset, offset + 1);
  }
  return null;
}

/// Returns the `AsyncMarker` corresponding to `node.asyncMarker`.
AsyncMarker getAsyncMarker(ir.FunctionNode node) {
  switch (node.asyncMarker) {
    case ir.AsyncMarker.Async:
      return AsyncMarker.ASYNC;
    case ir.AsyncMarker.AsyncStar:
      return AsyncMarker.ASYNC_STAR;
    case ir.AsyncMarker.Sync:
      return AsyncMarker.SYNC;
    case ir.AsyncMarker.SyncStar:
      return AsyncMarker.SYNC_STAR;
    case ir.AsyncMarker.SyncYielding:
    default:
      throw new UnsupportedError(
          "Async marker ${node.asyncMarker} is not supported.");
  }
}

/// Kernel encodes a null-aware expression `a?.b` as
///
///     let final #1 = a in #1 == null ? null : #1.b
///
/// [getNullAwareExpression] recognizes such expressions storing the result in
/// a [NullAwareExpression] object.
///
/// [syntheticVariable] holds the synthesized `#1` variable. [expression] holds
/// the `#1.b` expression. [receiver] returns `a` expression. [parent] returns
/// the parent of the let node, i.e. the parent node of the original null-aware
/// expression. [let] returns the let node created for the encoding.
class NullAwareExpression {
  final ir.VariableDeclaration syntheticVariable;
  final ir.Expression expression;

  NullAwareExpression(this.syntheticVariable, this.expression);

  ir.Expression get receiver => syntheticVariable.initializer;

  ir.TreeNode get parent => syntheticVariable.parent.parent;

  ir.Let get let => syntheticVariable.parent;

  String toString() => let.toString();
}

NullAwareExpression getNullAwareExpression(ir.TreeNode node) {
  if (node is ir.Let) {
    ir.Expression body = node.body;
    if (node.variable.name == null &&
        node.variable.isFinal &&
        body is ir.ConditionalExpression &&
        body.condition is ir.MethodInvocation &&
        body.then is ir.NullLiteral) {
      ir.MethodInvocation invocation = body.condition;
      ir.Expression receiver = invocation.receiver;
      if (invocation.name.name == '==' &&
          receiver is ir.VariableGet &&
          receiver.variable == node.variable &&
          invocation.arguments.positional.single is ir.NullLiteral) {
        // We have
        //   let #t1 = e0 in #t1 == null ? null : e1
        return new NullAwareExpression(node.variable, body.otherwise);
      }
    }
  }
  return null;
}
