import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:s3_dart_lite/src/helpers.dart';

void main() {
  group('isValidPort', () {
    test('invalid ports', () {
      expect(isValidPort(-50), isFalse);
      expect(isValidPort(0), isFalse);
      expect(isValidPort(90000), isFalse);
    });

    test('valid ports', () {
      expect(isValidPort(123), isTrue);
      expect(isValidPort(80), isTrue);
      expect(isValidPort(443), isTrue);
      expect(isValidPort(9000), isTrue);
    });
  });

  group('isValidBucketName', () {
    test('invalid bucket names', () async {
      final invalidNames = [
        "",
        "ab", // too short
        "has_underscore", // no underscores
        "test..bar", // double periods
        "propellane-possesses-omniphilic-reactivity-anions-and-radicals-add-towards-the-interbridgehead-bond-because-the-tridimensional-vacuum-constant-is-weaker-in-the-magnetic-flux-from-the-pseudo-electromagnetic-field-generated-by-the-subspace-distortion-of-the-integrated-hypercapacitor", // too long
        "-hyphen-", // must start/end with letters/numbers
      ];

      for (final invalidName in invalidNames) {
        expect(
          isValidBucketName(invalidName),
          isFalse,
          reason: '"$invalidName" should be invalid',
        );
      }
    });

    test('valid bucket names', () async {
      final validNames = [
        "bucket",
        "bucket-23",
        "test.bucket.com",
        "Capitalized.Backblaze.Bucket", // Our implementation allows caps
      ];

      for (final validName in validNames) {
        expect(
          isValidBucketName(validName),
          isTrue,
          reason: '"$validName" should be valid',
        );
      }
    });
  });

  group('makeDateShort', () {
    test('returns YYYYMMDD', () {
      final date = DateTime.utc(2012, 12, 03, 17, 25, 36, 331);
      expect(makeDateShort(date), "20121203");
    });
  });

  group('makeDateLong', () {
    test('returns YYYYMMDDTHHmmssZ', () {
      final date = DateTime.utc(2017, 08, 11, 17, 26, 34, 935);
      expect(makeDateLong(date), "20170811T172634Z");
    });
  });

  group('bin2hex', () {
    test('converts bytes to hex string', () {
      final data = Uint8List.fromList([
        0xab,
        0xcd,
        0x00,
        0x01,
        0x00,
        0xc0,
        0xff,
        0xee,
      ]);
      expect(bin2hex(data), "abcd000100c0ffee");
    });
  });

  group('sha256digestHex', () {
    test('hashes data correctly', () async {
      expect(
        await sha256digestHex("data"),
        "3a6eb0790f39ac87c94f3856b2dd2c5d110e6811602261a9a923d3bb23adc8b7",
      );
      expect(
        await sha256digestHex(""),
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      );
    });
  });
}
