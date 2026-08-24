/// Cryptographic primitives for TP-Link's KLAP local protocol, used by
/// Tapo "SMART" devices (P100/P110/P115 plugs, L-series bulbs, etc.).
///
/// Ported faithfully from python-kasa's `kasa/transports/klaptransport.py`
/// (https://github.com/python-kasa/python-kasa), which is the reference
/// implementation this app relies on for exact byte-for-byte compatibility.
/// There are two hash variants depending on firmware age; both are tried
/// during handshake since the device tells us which one it expects via the
/// hash it returns.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart' as pc;

Uint8List _sha256(List<int> data) => Uint8List.fromList(sha256.convert(data).bytes);
Uint8List _sha1(List<int> data) => Uint8List.fromList(sha1.convert(data).bytes);
Uint8List _md5(List<int> data) => Uint8List.fromList(md5.convert(data).bytes);

Uint8List _concat(List<List<int>> parts) {
  final builder = BytesBuilder();
  for (final part in parts) {
    builder.add(part);
  }
  return builder.toBytes();
}

/// KLAP protocol version, determined during handshake by matching the
/// device's response hash against candidates computed with each version's
/// auth-hash algorithm.
enum KlapVersion { v1, v2 }

class KlapAuthHash {
  /// v1: auth_hash = md5(md5(username) + md5(password))
  static Uint8List v1(String username, String password) {
    return _md5(_concat([_md5(utf8.encode(username)), _md5(utf8.encode(password))]));
  }

  /// v2: auth_hash = sha256(sha1(username) + sha1(password))
  static Uint8List v2(String username, String password) {
    return _sha256(_concat([_sha1(utf8.encode(username)), _sha1(utf8.encode(password))]));
  }

  static Uint8List forVersion(KlapVersion version, String username, String password) {
    return version == KlapVersion.v1 ? v1(username, password) : v2(username, password);
  }

  /// handshake1 response hash the device is expected to send back.
  static Uint8List handshake1Hash(
    KlapVersion version,
    Uint8List localSeed,
    Uint8List remoteSeed,
    Uint8List authHash,
  ) {
    if (version == KlapVersion.v1) {
      return _sha256(_concat([localSeed, authHash]));
    }
    return _sha256(_concat([localSeed, remoteSeed, authHash]));
  }

  /// handshake2 payload sent to the device to complete authentication.
  static Uint8List handshake2Payload(
    KlapVersion version,
    Uint8List localSeed,
    Uint8List remoteSeed,
    Uint8List authHash,
  ) {
    if (version == KlapVersion.v1) {
      return _sha256(_concat([remoteSeed, authHash]));
    }
    return _sha256(_concat([remoteSeed, localSeed, authHash]));
  }
}

/// Represents an authenticated KLAP session: derives the AES key/IV/signature
/// material from the two handshake seeds and the auth hash, then encrypts
/// and decrypts request/response payloads, tracking the sequence number the
/// device expects to see incremented on every request.
class KlapEncryptionSession {
  final Uint8List _key;
  final Uint8List _ivBase; // first 12 bytes; last 4 bytes of iv are the seq
  final Uint8List _sig;
  int _seq;

  KlapEncryptionSession._(this._key, this._ivBase, this._sig, this._seq);

  factory KlapEncryptionSession(
    Uint8List localSeed,
    Uint8List remoteSeed,
    Uint8List userHash,
  ) {
    final key = _sha256(_concat([utf8.encode('lsk'), localSeed, remoteSeed, userHash]))
        .sublist(0, 16);

    final fullIv = _sha256(_concat([utf8.encode('iv'), localSeed, remoteSeed, userHash]));
    final ivBase = fullIv.sublist(0, 12);
    final seq = ByteData.sublistView(fullIv, 12, 16).getInt32(0, Endian.big);

    final sig = _sha256(_concat([utf8.encode('ldk'), localSeed, remoteSeed, userHash]))
        .sublist(0, 28);

    return KlapEncryptionSession._(key, ivBase, sig, seq);
  }

  Uint8List _ivForSeq(int seq) {
    final seqBytes = ByteData(4)..setInt32(0, seq, Endian.big);
    return _concat([_ivBase, seqBytes.buffer.asUint8List()]);
  }

  static Uint8List _pkcs7Pad(Uint8List data, int blockSize) {
    final padLen = blockSize - (data.length % blockSize);
    final padded = Uint8List(data.length + padLen);
    padded.setRange(0, data.length, data);
    padded.fillRange(data.length, padded.length, padLen);
    return padded;
  }

  static Uint8List _pkcs7Unpad(Uint8List data) {
    if (data.isEmpty) return data;
    final padLen = data.last;
    if (padLen <= 0 || padLen > data.length) return data;
    return data.sublist(0, data.length - padLen);
  }

  /// Encrypts [msg], increments the sequence number, and returns the
  /// signed ciphertext (32-byte sha256 signature + AES-CBC ciphertext)
  /// along with the sequence number to send as the `seq` query parameter.
  (Uint8List payload, int seq) encrypt(Uint8List msg) {
    _seq += 1;
    final iv = _ivForSeq(_seq);

    final padded = _pkcs7Pad(msg, 16);
    final cipher = pc.CBCBlockCipher(pc.AESEngine())
      ..init(true, pc.ParametersWithIV<pc.KeyParameter>(pc.KeyParameter(_key), iv));

    final ciphertext = Uint8List(padded.length);
    for (var offset = 0; offset < padded.length; offset += 16) {
      cipher.processBlock(padded, offset, ciphertext, offset);
    }

    final seqBytes = ByteData(4)..setInt32(0, _seq, Endian.big);
    final signature = _sha256(_concat([_sig, seqBytes.buffer.asUint8List(), ciphertext]));

    return (_concat([signature, ciphertext]), _seq);
  }

  /// Decrypts a device response using the current sequence number's IV.
  String decrypt(Uint8List responseBody) {
    final ciphertext = responseBody.sublist(32);
    final iv = _ivForSeq(_seq);

    final cipher = pc.CBCBlockCipher(pc.AESEngine())
      ..init(false, pc.ParametersWithIV<pc.KeyParameter>(pc.KeyParameter(_key), iv));

    final decrypted = Uint8List(ciphertext.length);
    for (var offset = 0; offset < ciphertext.length; offset += 16) {
      cipher.processBlock(ciphertext, offset, decrypted, offset);
    }

    return utf8.decode(_pkcs7Unpad(decrypted));
  }
}
