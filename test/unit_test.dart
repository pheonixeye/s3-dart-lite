
import 'package:test/test.dart';
import 'package:s3_dart_lite/src/helpers.dart';
import 'package:s3_dart_lite/src/signing.dart';

void main() {
  group('Helpers', () {
    test('isValidBucketName', () {
      expect(isValidBucketName('my-bucket'), isTrue);
      // Source implementation allows uppercase, so we expect true
      expect(isValidBucketName('My-Bucket'), isTrue);
      expect(isValidBucketName('my..bucket'), isFalse);
      expect(isValidBucketName('-mybucket'), isFalse);
      expect(isValidBucketName('mybucket-'), isFalse);
    });

    test('makeDateLong', () {
      final d = DateTime.utc(2023, 10, 25, 12, 34, 56);
      expect(makeDateLong(d), '20231025T123456Z');
    });
  });

  group('Signing', () {
    test('getCanonicalRequest', () {
      final method = 'GET';
      final path = '/test.txt';
      final headers = {'host': 'example.com', 'x-amz-date': '20130524T000000Z'};
      final signedHeaders = ['host', 'x-amz-date'];
      final payloadHash = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
      
      final result = getCanonicalRequest(method, path, headers, signedHeaders, payloadHash);
      
      final expected = [
        'GET',
        '/test.txt',
        '',
        'host:example.com',
        'x-amz-date:20130524T000000Z\n',
        'host;x-amz-date',
        payloadHash
      ].join('\n');
      
      expect(result, expected);
    });
    
     test('awsUriEncode', () {
        expect(awsUriEncode('foo bar'), 'foo%20bar');
        expect(awsUriEncode('foo/bar'), 'foo%2Fbar');
        expect(awsUriEncode('foo/bar', true), 'foo/bar');
        expect(awsUriEncode('~._-'), '~._-'); // Unreserved
     });
  });
}
