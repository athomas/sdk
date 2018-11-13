// Copyright (c) 2018, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:analysis_server_client/handler/notification_handler.dart';
import 'package:analysis_server_client/handler/server_connection_handler.dart';
import 'package:analysis_server_client/protocol.dart';
import 'package:analysis_server_client/server.dart';
import 'package:cli_util/cli_logging.dart';
import 'package:dartfix/handler/analysis_complete_handler.dart';
import 'package:dartfix/src/context.dart';
import 'package:dartfix/src/options.dart';
import 'package:dartfix/src/util.dart';
import 'package:dartfix/src/verbose_server.dart';
import 'package:pub_semver/pub_semver.dart';

class Driver {
  Context context;
  _Handler handler;
  Logger logger;
  Server server;

  bool force;
  bool overwrite;
  List<String> targets;

  Ansi get ansi => logger.ansi;

  Future start(List<String> args) async {
    final Options options = Options.parse(args);

    force = options.force;
    overwrite = options.overwrite;
    targets = options.targets;
    context = options.context;
    logger = options.logger;
    server = logger.isVerbose ? new VerboseServer(logger) : new Server();
    handler = new _Handler(this);

    if (!await startServer(options)) {
      context.exit(15);
    }

    EditDartfixResult result;
    try {
      final progress = await setupAnalysis(options);
      result = await requestFixes(options, progress);
    } finally {
      await server.stop();
    }
    if (result != null) {
      applyFixes(result);
    }
  }

  Future<bool> startServer(Options options) async {
    if (options.verbose) {
      logger.trace('Dart SDK version ${Platform.version}');
      logger.trace('  ${Platform.resolvedExecutable}');
      logger.trace('dartfix');
      logger.trace('  ${Platform.script.toFilePath()}');
    }
    // Automatically run analysis server from source
    // if this command line tool is being run from source within the SDK repo.
    String serverPath = findServerPath();
    await server.start(
      clientId: 'dartfix',
      clientVersion: pubspecVersion,
      sdkPath: options.sdkPath,
      serverPath: serverPath,
    );
    server.listenToOutput(notificationProcessor: handler.handleEvent);
    return handler.serverConnected(timeLimit: const Duration(seconds: 15));
  }

  Future<Progress> setupAnalysis(Options options) async {
    final progress = logger.progress('${ansi.emphasized('Calculating fixes')}');
    logger.trace('');
    logger.trace('Setup analysis');
    await server.send(SERVER_REQUEST_SET_SUBSCRIPTIONS,
        new ServerSetSubscriptionsParams([ServerService.STATUS]).toJson());
    await server.send(
        ANALYSIS_REQUEST_SET_ANALYSIS_ROOTS,
        new AnalysisSetAnalysisRootsParams(
          options.targets,
          const [],
        ).toJson());
    return progress;
  }

  Future<EditDartfixResult> requestFixes(
      Options options, Progress progress) async {
    logger.trace('Requesting fixes');
    Future isAnalysisComplete = handler.analysisComplete();
    Map<String, dynamic> json = await server.send(
        EDIT_REQUEST_DARTFIX, new EditDartfixParams(options.targets).toJson());

    // TODO(danrubel): This is imprecise signal for determining when all
    // analysis error notifications have been received. Consider adding a new
    // notification indicating that the server is idle (all requests processed,
    // all analysis complete, all notifications sent).
    await isAnalysisComplete;

    progress.finish(showTiming: true);
    ResponseDecoder decoder = new ResponseDecoder(null);
    return EditDartfixResult.fromJson(decoder, 'result', json);
  }

  Future applyFixes(EditDartfixResult result) async {
    showDescriptions('Recommended changes', result.suggestions);
    showDescriptions('Recommended changes that cannot be automatically applied',
        result.otherSuggestions);
    if (result.suggestions.isEmpty) {
      logger.stdout('');
      logger.stdout(result.otherSuggestions.isNotEmpty
          ? 'None of the recommended changes can be automatically applied.'
          : 'No recommended changes.');
      return;
    }
    logger.stdout('');
    logger.stdout(ansi.emphasized('Files to be changed:'));
    for (SourceFileEdit fileEdit in result.edits) {
      logger.stdout('  ${relativePath(fileEdit.file)}');
    }
    if (shouldApplyChanges(result)) {
      for (SourceFileEdit fileEdit in result.edits) {
        final file = new File(fileEdit.file);
        String code = await file.readAsString();
        for (SourceEdit edit in fileEdit.edits) {
          code = edit.apply(code);
        }
        await file.writeAsString(code);
      }
      logger.stdout(ansi.emphasized('Changes applied.'));
    }
  }

  void showDescriptions(String title, List<DartFixSuggestion> suggestions) {
    if (suggestions.isNotEmpty) {
      logger.stdout('');
      logger.stdout(ansi.emphasized('$title:'));
      List<DartFixSuggestion> sorted = new List.from(suggestions)
        ..sort(compareSuggestions);
      for (DartFixSuggestion suggestion in sorted) {
        final msg = new StringBuffer();
        msg.write('  ${toSentenceFragment(suggestion.description)}');
        final loc = suggestion.location;
        if (loc != null) {
          msg.write(' • ${relativePath(loc.file)}');
          msg.write(' • ${loc.startLine}:${loc.startColumn}');
        }
        logger.stdout(msg.toString());
      }
    }
  }

  bool shouldApplyChanges(EditDartfixResult result) {
    logger.stdout('');
    if (result.hasErrors) {
      logger.stdout('WARNING: The analyzed source contains errors'
          ' that may affect the accuracy of these changes.');
      logger.stdout('');
      if (!force) {
        logger.stdout('Rerun with --$forceOption to apply these changes.');
        return false;
      }
    } else if (!overwrite && !force) {
      logger.stdout('Rerun with --$overwriteOption to apply these changes.');
      return false;
    }
    return true;
  }

  String relativePath(String filePath) {
    for (String target in targets) {
      if (filePath.startsWith(target)) {
        return filePath.substring(target.length + 1);
      }
    }
    return filePath;
  }
}

class _Handler
    with NotificationHandler, ServerConnectionHandler, AnalysisCompleteHandler {
  final Driver driver;
  final Logger logger;
  final Server server;

  _Handler(this.driver)
      : logger = driver.logger,
        server = driver.server;

  @override
  void handleFailedToConnect() {
    logger.stderr('Failed to connect to server');
  }

  @override
  void handleProtocolNotSupported(Version version) {
    logger.stderr('Expected protocol version $PROTOCOL_VERSION,'
        ' but found $version');
  }

  @override
  void handleServerError(String error, String trace) {
    logger.stderr('Server Error: $error');
    if (trace != null) {
      logger.stderr(trace);
    }
  }

  @override
  void onAnalysisErrors(AnalysisErrorsParams params) {
    List<AnalysisError> errors = params.errors;
    bool foundAtLeastOneError = false;
    for (AnalysisError error in errors) {
      if (shouldShowError(error)) {
        if (!foundAtLeastOneError) {
          foundAtLeastOneError = true;
          logger.stdout('${driver.relativePath(params.file)}:');
        }
        Location loc = error.location;
        logger.stdout('  ${toSentenceFragment(error.message)}'
            ' • ${loc.startLine}:${loc.startColumn}');
      }
    }
  }
}
