// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../ast.dart'
    show
        BottomType,
        DartType,
        DynamicType,
        FunctionType,
        InterfaceType,
        NamedType,
        TypeParameter,
        TypedefType,
        VoidType;

import '../type_algebra.dart' show substitute;

import '../type_environment.dart' show TypeEnvironment;

class TypeArgumentIssue {
  // The type argument that violated the bound.
  final DartType argument;

  // The type parameter with the bound that was violated.
  final TypeParameter typeParameter;

  // The enclosing type of the issue, that is, the one with [typeParameter].
  final DartType enclosingType;

  TypeArgumentIssue(this.argument, this.typeParameter, this.enclosingType);
}

// TODO(dmitryas):  Remove [typedefInstantiations] when type arguments passed to
// typedefs are preserved in the Kernel output.
List<TypeArgumentIssue> findTypeArgumentIssues(
    DartType type, TypeEnvironment typeEnvironment,
    {bool allowSuperBounded = false}) {
  List<TypeParameter> variables;
  List<DartType> arguments;
  List<TypeArgumentIssue> typedefRhsResult;

  if (type is FunctionType && type.typedefType != null) {
    // [type] is a function type that is an application of a parametrized
    // typedef.  We need to check both the l.h.s. and the r.h.s. of the
    // definition in that case.  For details, see [link]
    // (https://github.com/dart-lang/sdk/blob/master/docs/language/informal/super-bounded-types.md).
    FunctionType functionType = type;
    FunctionType cloned = new FunctionType(
        functionType.positionalParameters, functionType.returnType,
        namedParameters: functionType.namedParameters,
        typeParameters: functionType.typeParameters,
        requiredParameterCount: functionType.requiredParameterCount,
        typedefType: null);
    typedefRhsResult = findTypeArgumentIssues(cloned, typeEnvironment,
        allowSuperBounded: true);
    type = functionType.typedefType;
  }

  if (type is InterfaceType) {
    variables = type.classNode.typeParameters;
    arguments = type.typeArguments;
  } else if (type is TypedefType) {
    variables = type.typedefNode.typeParameters;
    arguments = type.typeArguments;
  } else if (type is FunctionType) {
    List<TypeArgumentIssue> result = <TypeArgumentIssue>[];
    for (TypeParameter parameter in type.typeParameters) {
      result.addAll(findTypeArgumentIssues(parameter.bound, typeEnvironment,
              allowSuperBounded: true) ??
          const <TypeArgumentIssue>[]);
    }
    for (DartType formal in type.positionalParameters) {
      result.addAll(findTypeArgumentIssues(formal, typeEnvironment,
              allowSuperBounded: true) ??
          const <TypeArgumentIssue>[]);
    }
    for (NamedType named in type.namedParameters) {
      result.addAll(findTypeArgumentIssues(named.type, typeEnvironment,
              allowSuperBounded: true) ??
          const <TypeArgumentIssue>[]);
    }
    result.addAll(findTypeArgumentIssues(type.returnType, typeEnvironment,
            allowSuperBounded: true) ??
        const <TypeArgumentIssue>[]);
    return result.isEmpty ? null : result;
  } else {
    return null;
  }

  if (variables == null) return null;

  List<TypeArgumentIssue> result;
  List<TypeArgumentIssue> argumentsResult;

  Map<TypeParameter, DartType> substitutionMap =
      new Map<TypeParameter, DartType>.fromIterables(variables, arguments);
  for (int i = 0; i < arguments.length; ++i) {
    DartType argument = arguments[i];
    if (argument is FunctionType && argument.typeParameters.length > 0) {
      // Generic function types aren't allowed as type arguments either.
      result ??= <TypeArgumentIssue>[];
      result.add(new TypeArgumentIssue(argument, variables[i], type));
    } else if (!typeEnvironment.isSubtypeOf(
        argument, substitute(variables[i].bound, substitutionMap))) {
      result ??= <TypeArgumentIssue>[];
      result.add(new TypeArgumentIssue(argument, variables[i], type));
    }

    List<TypeArgumentIssue> issues = findTypeArgumentIssues(
        argument, typeEnvironment,
        allowSuperBounded: true);
    if (issues != null) {
      argumentsResult ??= <TypeArgumentIssue>[];
      argumentsResult.addAll(issues);
    }
  }
  if (argumentsResult != null) {
    result ??= <TypeArgumentIssue>[];
    result.addAll(argumentsResult);
  }
  if (typedefRhsResult != null) {
    result ??= <TypeArgumentIssue>[];
    result.addAll(typedefRhsResult);
  }

  // [type] is regular-bounded.
  if (result == null) return null;
  if (!allowSuperBounded) return result;

  result = null;
  type = convertSuperBoundedToRegularBounded(typeEnvironment, type);
  List<DartType> argumentsToReport = arguments.toList();
  if (type is InterfaceType) {
    variables = type.classNode.typeParameters;
    arguments = type.typeArguments;
  } else if (type is TypedefType) {
    variables = type.typedefNode.typeParameters;
    arguments = type.typeArguments;
  }
  substitutionMap =
      new Map<TypeParameter, DartType>.fromIterables(variables, arguments);
  for (int i = 0; i < arguments.length; ++i) {
    DartType argument = arguments[i];
    if (argument is FunctionType && argument.typeParameters.length > 0) {
      // Generic function types aren't allowed as type arguments either.
      result ??= <TypeArgumentIssue>[];
      result
          .add(new TypeArgumentIssue(argumentsToReport[i], variables[i], type));
    } else if (!typeEnvironment.isSubtypeOf(
        argument, substitute(variables[i].bound, substitutionMap))) {
      result ??= <TypeArgumentIssue>[];
      result
          .add(new TypeArgumentIssue(argumentsToReport[i], variables[i], type));
    }
  }
  if (argumentsResult != null) {
    result ??= <TypeArgumentIssue>[];
    result.addAll(argumentsResult);
  }
  if (typedefRhsResult != null) {
    result ??= <TypeArgumentIssue>[];
    result.addAll(typedefRhsResult);
  }
  return result;
}

// TODO(dmitryas):  Remove [typedefInstantiations] when type arguments passed to
// typedefs are preserved in the Kernel output.
List<TypeArgumentIssue> findTypeArgumentIssuesForInvocation(
    List<TypeParameter> parameters,
    List<DartType> arguments,
    TypeEnvironment typeEnvironment,
    {Map<FunctionType, List<DartType>> typedefInstantiations}) {
  assert(arguments.length == parameters.length);
  List<TypeArgumentIssue> result;
  var substitutionMap = <TypeParameter, DartType>{};
  for (int i = 0; i < arguments.length; ++i) {
    substitutionMap[parameters[i]] = arguments[i];
  }
  for (int i = 0; i < arguments.length; ++i) {
    DartType argument = arguments[i];
    if (argument is FunctionType && argument.typeParameters.length > 0) {
      // Generic function types aren't allowed as type arguments either.
      result ??= <TypeArgumentIssue>[];
      result.add(new TypeArgumentIssue(argument, parameters[i], null));
    } else if (!typeEnvironment.isSubtypeOf(
        argument, substitute(parameters[i].bound, substitutionMap))) {
      result ??= <TypeArgumentIssue>[];
      result.add(new TypeArgumentIssue(argument, parameters[i], null));
    }

    List<TypeArgumentIssue> issues = findTypeArgumentIssues(
        argument, typeEnvironment,
        allowSuperBounded: true);
    if (issues != null) {
      result ??= <TypeArgumentIssue>[];
      result.addAll(issues);
    }
  }
  return result;
}

String getGenericTypeName(DartType type) {
  if (type is InterfaceType) {
    return type.classNode.name;
  } else if (type is TypedefType) {
    return type.typedefNode.name;
  }
  return type.toString();
}

/// Replaces all covariant occurrences of `dynamic`, `Object`, and `void` with
/// [BottomType] and all contravariant occurrences of `Null` and [BottomType]
/// with `Object`.
DartType convertSuperBoundedToRegularBounded(
    TypeEnvironment typeEnvironment, DartType type,
    {bool isCovariant = true}) {
  if ((type is DynamicType ||
          type is VoidType ||
          isObject(typeEnvironment, type)) &&
      isCovariant) {
    return const BottomType();
  } else if ((type is BottomType || isNull(typeEnvironment, type)) &&
      !isCovariant) {
    return typeEnvironment.objectType;
  } else if (type is InterfaceType && type.classNode.typeParameters != null) {
    List<DartType> replacedTypeArguments =
        new List<DartType>(type.typeArguments.length);
    for (int i = 0; i < replacedTypeArguments.length; i++) {
      replacedTypeArguments[i] = convertSuperBoundedToRegularBounded(
          typeEnvironment, type.typeArguments[i],
          isCovariant: isCovariant);
    }
    return new InterfaceType(type.classNode, replacedTypeArguments);
  } else if (type is TypedefType && type.typedefNode.typeParameters != null) {
    List<DartType> replacedTypeArguments =
        new List<DartType>(type.typeArguments.length);
    for (int i = 0; i < replacedTypeArguments.length; i++) {
      replacedTypeArguments[i] = convertSuperBoundedToRegularBounded(
          typeEnvironment, type.typeArguments[i],
          isCovariant: isCovariant);
    }
    return new TypedefType(type.typedefNode, replacedTypeArguments);
  } else if (type is FunctionType) {
    var replacedReturnType = convertSuperBoundedToRegularBounded(
        typeEnvironment, type.returnType,
        isCovariant: isCovariant);
    var replacedPositionalParameters =
        new List<DartType>(type.positionalParameters.length);
    for (int i = 0; i < replacedPositionalParameters.length; i++) {
      replacedPositionalParameters[i] = convertSuperBoundedToRegularBounded(
          typeEnvironment, type.positionalParameters[i],
          isCovariant: !isCovariant);
    }
    var replacedNamedParameters =
        new List<NamedType>(type.namedParameters.length);
    for (int i = 0; i < replacedNamedParameters.length; i++) {
      replacedNamedParameters[i] = new NamedType(
          type.namedParameters[i].name,
          convertSuperBoundedToRegularBounded(
              typeEnvironment, type.namedParameters[i].type,
              isCovariant: !isCovariant));
    }
    return new FunctionType(replacedPositionalParameters, replacedReturnType,
        namedParameters: replacedNamedParameters,
        typeParameters: type.typeParameters,
        requiredParameterCount: type.requiredParameterCount,
        typedefType: type.typedefType);
  }
  return type;
}

bool isObject(TypeEnvironment typeEnvironment, DartType type) {
  return type is InterfaceType &&
      type.classNode == typeEnvironment.objectType.classNode;
}

bool isNull(TypeEnvironment typeEnvironment, DartType type) {
  return type is InterfaceType &&
      type.classNode == typeEnvironment.nullType.classNode;
}
