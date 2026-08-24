import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Buffers bytes from a stream so callers can await an exact number of
/// bytes at a time, similar to asyncio's `StreamReader.readexactly` — which
/// dart:io's [Socket] has no equivalent for.
class ByteStreamReader {
  Uint8List _buffer = Uint8List(0);
  Completer<void>? _dataArrived;
  bool _closed = false;
  Object? _error;
  late final StreamSubscription<Uint8List> _subscription;

  ByteStreamReader(Stream<Uint8List> stream) {
    _subscription = stream.listen(
      (chunk) {
        final merged = Uint8List(_buffer.length + chunk.length);
        merged.setRange(0, _buffer.length, _buffer);
        merged.setRange(_buffer.length, merged.length, chunk);
        _buffer = merged;
        _dataArrived?.complete();
      },
      onDone: () {
        _closed = true;
        _dataArrived?.complete();
      },
      onError: (Object e) {
        _error = e;
        _dataArrived?.complete();
      },
    );
  }

  Future<Uint8List> readExactly(int n) async {
    while (_buffer.length < n) {
      if (_error != null) throw _error!;
      if (_closed) {
        throw const SocketException('Connection closed before enough data arrived');
      }
      _dataArrived = Completer<void>();
      await _dataArrived!.future;
    }
    final result = _buffer.sublist(0, n);
    _buffer = _buffer.sublist(n);
    return result;
  }

  void dispose() => _subscription.cancel();
}
