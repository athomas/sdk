// Copyright (c) 2018, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server_client/handler/notification_handler.dart';
import 'package:analysis_server_client/handler/server_connection_handler.dart';
import 'package:analysis_server_client/protocol.dart';
import 'package:analysis_server_client/server.dart';
import 'package:test/test.dart';

const _debug = false;

void main() {
  test('live', () async {
    final server = _debug ? new TestServer() : new Server();
    await server.start(clientId: 'test', suppressAnalytics: true);

    TestHandler handler = new TestHandler(server);
    server.listenToOutput(notificationProcessor: handler.handleEvent);
    if (!await handler.serverConnected(
        timeLimit: const Duration(seconds: 15))) {
      fail('failed to connect to server');
    }

    Map<String, dynamic> json = await server.send(
        SERVER_REQUEST_GET_VERSION, new ServerGetVersionParams().toJson());
    final result = ServerGetVersionResult.fromJson(
        new ResponseDecoder(null), 'result', json);
    await server.stop();

    expect(result.version, isNotEmpty);
  });
}

class TestHandler with NotificationHandler, ServerConnectionHandler {
  final Server server;

  TestHandler(this.server);
}

class TestServer extends Server {
  @override
  void logMessage(String prefix, String details) {
    print('$prefix $details');
  }
}
