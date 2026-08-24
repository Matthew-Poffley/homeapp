/// A minimal, hand-rolled HTTP/1.1 client used instead of dart:io's
/// HttpClient.
///
/// Some Tapo plugs run TP-Link's own minimal embedded HTTP server
/// ("SHIP 2.0"), which does case-sensitive header name matching — a spec
/// violation (RFC 7230 requires header names to be treated
/// case-insensitively), but real firmware behavior we have to work around.
/// dart:io's HttpClient always lowercases outgoing header names with no way
/// to override it, which makes that server reject every request with 400.
/// Writing the request by hand lets us send canonical-case headers
/// ("Host", "Content-Length") that this firmware actually accepts.
///
/// Responses are read until [Content-Length] bytes of body have arrived,
/// rather than waiting for the server to close the connection — some
/// firmware doesn't honor `Connection: close` and keeps the socket open,
/// which would otherwise hang forever.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class RawHttpResponse {
  final int statusCode;
  final Map<String, String> headers; // lowercase keys
  final List<String> setCookieHeaders;
  final Uint8List body;

  RawHttpResponse({
    required this.statusCode,
    required this.headers,
    required this.setCookieHeaders,
    required this.body,
  });
}

int _findHeaderEnd(Uint8List data) {
  for (var i = 0; i + 3 < data.length; i++) {
    if (data[i] == 13 && data[i + 1] == 10 && data[i + 2] == 13 && data[i + 3] == 10) {
      return i;
    }
  }
  return -1;
}

int? _parseContentLength(String headerText) {
  for (final line in headerText.split('\r\n').skip(1)) {
    final idx = line.indexOf(':');
    if (idx == -1) continue;
    if (line.substring(0, idx).trim().toLowerCase() == 'content-length') {
      return int.tryParse(line.substring(idx + 1).trim());
    }
  }
  return null;
}

/// Sends a POST request with canonical-case headers over a fresh TCP
/// connection, and returns the parsed response. Stops reading as soon as
/// the full body (per Content-Length) has arrived; throws
/// [TimeoutException] if that doesn't happen within [timeout].
Future<RawHttpResponse> rawHttpPost({
  required String host,
  required int port,
  required String path,
  required Uint8List body,
  String? cookieHeader,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final socket = await Socket.connect(host, port, timeout: timeout);
  try {
    final requestHead = StringBuffer()
      ..write('POST $path HTTP/1.1\r\n')
      ..write('Host: $host:$port\r\n')
      ..write('Content-Length: ${body.length}\r\n');
    if (cookieHeader != null) {
      requestHead.write('Cookie: $cookieHeader\r\n');
    }
    requestHead.write('Connection: close\r\n');
    requestHead.write('\r\n');

    socket.add(ascii.encode(requestHead.toString()));
    socket.add(body);
    await socket.flush();

    final builder = BytesBuilder();
    int? expectedTotalLength;
    final responseComplete = Completer<Uint8List>();
    late final StreamSubscription<Uint8List> subscription;

    subscription = socket.listen(
      (chunk) {
        builder.add(chunk);
        final received = builder.toBytes();

        if (expectedTotalLength == null) {
          final headerEnd = _findHeaderEnd(received);
          if (headerEnd != -1) {
            final headerText = ascii.decode(received.sublist(0, headerEnd), allowInvalid: true);
            final contentLength = _parseContentLength(headerText) ?? 0;
            expectedTotalLength = headerEnd + 4 + contentLength;
          }
        }

        final total = expectedTotalLength;
        if (total != null && received.length >= total && !responseComplete.isCompleted) {
          responseComplete.complete(received);
          subscription.cancel();
        }
      },
      onDone: () {
        if (!responseComplete.isCompleted) {
          responseComplete.complete(builder.toBytes());
        }
      },
      onError: (Object e) {
        if (!responseComplete.isCompleted) {
          responseComplete.completeError(e);
        }
      },
      cancelOnError: true,
    );

    final raw = await responseComplete.future.timeout(
      timeout,
      onTimeout: () {
        subscription.cancel();
        throw TimeoutException(
          'Timed out waiting for a response from $host:$port$path',
          timeout,
        );
      },
    );

    final headerEnd = _findHeaderEnd(raw);
    if (headerEnd == -1) {
      throw const FormatException('Malformed HTTP response: no header terminator found');
    }
    final headerText = ascii.decode(raw.sublist(0, headerEnd), allowInvalid: true);
    final responseBody = raw.sublist(headerEnd + 4);

    final lines = headerText.split('\r\n');
    final statusParts = lines.first.split(' ');
    final statusCode = int.parse(statusParts[1]);

    final headers = <String, String>{};
    final setCookies = <String>[];
    for (final line in lines.skip(1)) {
      if (line.isEmpty) continue;
      final idx = line.indexOf(':');
      if (idx == -1) continue;
      final name = line.substring(0, idx).trim().toLowerCase();
      final value = line.substring(idx + 1).trim();
      if (name == 'set-cookie') {
        setCookies.add(value);
      } else {
        headers[name] = value;
      }
    }

    return RawHttpResponse(
      statusCode: statusCode,
      headers: headers,
      setCookieHeaders: setCookies,
      body: responseBody,
    );
  } finally {
    unawaited(socket.close());
  }
}
