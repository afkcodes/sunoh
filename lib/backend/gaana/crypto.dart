// Gaana stream URLs arrive AES-128-CBC encrypted (src/gaana/crypto.ts).
// The message is: one digit N, then the IV starting at index N (the digit
// counts, so N-1 filler chars follow it), then base64 ciphertext. The IV is
// 16 chars used as raw UTF-8 bytes. The key is fixed and public in the web
// player.
import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

// The four big-endian 32-bit words CryptoJS builds the key from.
const _keyWords = [1735995764, 593641578, 1814585892, 2004118885];

final Uint8List _key = () {
  final b = ByteData(16);
  for (var i = 0; i < 4; i++) {
    b.setUint32(i * 4, _keyWords[i]);
  }
  return b.buffer.asUint8List();
}();

/// Decrypts one `urls.<quality>.message` value; '' on any failure, like the
/// server (a bad URL must drop one quality, not the whole song).
String decryptGaanaUrl(String? message) {
  if (message == null || message.isEmpty) return '';
  try {
    final offset = int.parse(message[0]);
    const block = 16;
    if (message.length < offset + block) return '';
    final iv = utf8.encode(message.substring(offset, offset + block));
    if (iv.length != block) return '';
    final cipherText = base64.decode(
      base64.normalize(message.substring(offset + block)),
    );
    final cipher =
        PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
          ..init(
            false,
            PaddedBlockCipherParameters(
              ParametersWithIV(KeyParameter(_key), Uint8List.fromList(iv)),
              null,
            ),
          );
    return utf8.decode(cipher.process(cipherText));
  } catch (_) {
    return '';
  }
}
