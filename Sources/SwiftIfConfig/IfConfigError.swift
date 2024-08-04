//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder

/// Describes the kinds of errors that can occur when processing #if conditions.
enum IfConfigError: Error, CustomStringConvertible {
  case unknownExpression(ExprSyntax)
  case unhandledFunction(name: String, syntax: ExprSyntax)
  case requiresUnlabeledArgument(name: String, role: String, syntax: ExprSyntax)
  case unsupportedVersionOperator(name: String, operator: TokenSyntax)
  case invalidVersionOperand(name: String, syntax: ExprSyntax)
  case emptyVersionComponent(syntax: ExprSyntax)
  case compilerVersionOutOfRange(value: Int, upperLimit: Int, syntax: ExprSyntax)
  case compilerVersionSecondComponentNotWildcard(syntax: ExprSyntax)
  case compilerVersionTooManyComponents(syntax: ExprSyntax)
  case canImportMissingModule(syntax: ExprSyntax)
  case canImportLabel(syntax: ExprSyntax)
  case canImportTwoParameters(syntax: ExprSyntax)
  case ignoredTrailingComponents(version: VersionTuple, syntax: ExprSyntax)
  case integerLiteralCondition(syntax: ExprSyntax, replacement: Bool)
  case likelySimulatorPlatform(syntax: ExprSyntax)

  var description: String {
    switch self {
    case .unknownExpression:
      return "invalid conditional compilation expression"

    case .unhandledFunction(name: let name, syntax: _):
      return "build configuration cannot handle '\(name)'"

    case .requiresUnlabeledArgument(name: let name, role: let role, syntax: _):
      return "\(name) requires a single unlabeled argument for the \(role)"

    case .unsupportedVersionOperator(name: let name, operator: let op):
      return "'\(name)' version check does not support operator '\(op.trimmedDescription)'"

    case .invalidVersionOperand(name: let name, syntax: let version):
      return "'\(name)' version check has invalid version '\(version.trimmedDescription)'"

    case .emptyVersionComponent(syntax: _):
      return "found empty version component"

    case .compilerVersionOutOfRange(value: _, upperLimit: let upperLimit, syntax: _):
      // FIXME: This matches the C++ implementation, but it would be more useful to
      // provide the actual value as-written and avoid the mathy [0, N] syntax.
      return "compiler version component out of range: must be in [0, \(upperLimit)]"

    case .compilerVersionSecondComponentNotWildcard(syntax: _):
      return "the second version component is not used for comparison in legacy compiler versions"

    case .compilerVersionTooManyComponents(syntax: _):
      return "compiler version must not have more than five components"

    case .canImportMissingModule(syntax: _):
      return "canImport requires a module name"

    case .canImportLabel(syntax: _):
      return "second parameter of canImport should be labeled as _version or _underlyingVersion"

    case .canImportTwoParameters(syntax: _):
      return "canImport can take only two parameters"

    case .ignoredTrailingComponents(version: let version, syntax: _):
      return "trailing components of version '\(version.description)' are ignored"

    case .integerLiteralCondition(syntax: let syntax, replacement: let replacement):
      return "'\(syntax.trimmedDescription)' is not a valid conditional compilation expression, use '\(replacement)'"

    case .likelySimulatorPlatform:
      return
        "platform condition appears to be testing for simulator environment; use 'targetEnvironment(simulator)' instead"
    }
  }

  /// Retrieve the syntax node associated with this error.
  var syntax: Syntax {
    switch self {
    case .unknownExpression(let syntax),
      .unhandledFunction(name: _, syntax: let syntax),
      .requiresUnlabeledArgument(name: _, role: _, syntax: let syntax),
      .invalidVersionOperand(name: _, syntax: let syntax),
      .emptyVersionComponent(syntax: let syntax),
      .compilerVersionOutOfRange(value: _, upperLimit: _, syntax: let syntax),
      .compilerVersionTooManyComponents(syntax: let syntax),
      .compilerVersionSecondComponentNotWildcard(syntax: let syntax),
      .canImportMissingModule(syntax: let syntax),
      .canImportLabel(syntax: let syntax),
      .canImportTwoParameters(syntax: let syntax),
      .ignoredTrailingComponents(version: _, syntax: let syntax),
      .integerLiteralCondition(syntax: let syntax, replacement: _),
      .likelySimulatorPlatform(syntax: let syntax):
      return Syntax(syntax)

    case .unsupportedVersionOperator(name: _, operator: let op):
      return Syntax(op)
    }
  }
}

extension IfConfigError: DiagnosticMessage {
  var message: String { description }

  var diagnosticID: MessageID {
    .init(domain: "SwiftIfConfig", id: "IfConfigError")
  }

  var severity: SwiftDiagnostics.DiagnosticSeverity {
    switch self {
    case .ignoredTrailingComponents, .likelySimulatorPlatform: return .warning
    default: return .error
    }
  }

  private struct SimpleFixItMessage: FixItMessage {
    var message: String

    var fixItID: MessageID {
      .init(domain: "SwiftIfConfig", id: "IfConfigFixIt")
    }
  }

  var asDiagnostic: Diagnostic {
    // For the integer literal condition we have a Fix-It.
    if case .integerLiteralCondition(let syntax, let replacement) = self {
      return Diagnostic(
        node: syntax,
        message: self,
        fixIt: .replace(
          message: SimpleFixItMessage(
            message: "replace with Boolean literal '\(replacement)'"
          ),
          oldNode: syntax,
          newNode: BooleanLiteralExprSyntax(
            literal: .keyword(replacement ? .true : .false)
          )
        )
      )
    }

    // For the likely targetEnvironment(simulator) condition we have a Fix-It.
    if case .likelySimulatorPlatform(let syntax) = self {
      return Diagnostic(
        node: syntax,
        message: self,
        fixIt: .replace(
          message: SimpleFixItMessage(
            message: "replace with 'targetEnvironment(simulator)'"
          ),
          oldNode: syntax,
          newNode: "targetEnvironment(simulator)" as ExprSyntax
        )
      )
    }

    return Diagnostic(node: syntax, message: self)
  }
}
