import 'dart:async';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:s3_dart_lite/src/client.dart';

void main() {
  group('ObjectUploader', () {
    final clientOptions = ClientOptions(
      endPoint: 's3.example.com',
      region: 'us-east-1',
      bucket: 'test-bucket',
      accessKey: 'key',
      secretKey: 'secret',
    );

    test('Single part upload (small payload)', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'PUT');
        expect(request.url.path, '/test-bucket/hello.txt');
        expect(request.body, 'Hello');
        return http.Response('', 200, headers: {'ETag': '"etag1"'});
      });

      final client = Client(clientOptions, httpClient: mockClient);
      final result = await client.putObject('hello.txt', 'Hello');
      expect(result.etag, 'etag1');
    });

    test('Multipart upload (stream splitting)', () async {
      // Logic:
      // 1. Initiate Multipart
      // 2. Upload Part 1 (size = partSize)
      // 3. Upload Part 2 (remaining)
      // 4. Complete Multipart

      final partSize = 5; // Very small part size for testing
      final data = Uint8List.fromList(
        List.generate(8, (i) => i),
      ); // 8 bytes: [0,1,2,3,4,5,6,7]
      // Part 1: [0,1,2,3,4]
      // Part 2: [5,6,7]

      var initCalled = false;
      var part1Called = false;
      var part2Called = false;
      var completeCalled = false;
      String? uploadId;

      final mockClient = MockClient((request) async {
        if (request.method == 'POST' &&
            request.url.queryParameters.containsKey('uploads')) {
          initCalled = true;
          uploadId = "upload-123";
          return http.Response(
            '<?xml version="1.0" encoding="UTF-8"?><InitiateMultipartUploadResult><UploadId>$uploadId</UploadId></InitiateMultipartUploadResult>',
            200,
          );
        } else if (request.method == 'PUT' &&
            request.url.queryParameters.containsKey('partNumber')) {
          final partNum = request.url.queryParameters['partNumber'];
          if (partNum == '1') {
            expect(request.bodyBytes.length, 5);
            expect(request.bodyBytes[0], 0);
            part1Called = true;
            return http.Response('', 200, headers: {'ETag': '"etag-p1"'});
          } else if (partNum == '2') {
            expect(request.bodyBytes.length, 3);
            expect(request.bodyBytes[0], 5);
            part2Called = true;
            return http.Response('', 200, headers: {'ETag': '"etag-p2"'});
          }
        } else if (request.method == 'POST' &&
            request.url.queryParameters.containsKey('uploadId')) {
          completeCalled = true;
          // Verify XML body contains etags?
          expect(request.body, contains('etag-p1'));
          expect(request.body, contains('etag-p2'));
          return http.Response(
            '<?xml version="1.0" encoding="UTF-8"?><CompleteMultipartUploadResult><ETag>"etag-final"</ETag></CompleteMultipartUploadResult>',
            200,
          );
        }
        return http.Response('Error', 400);
      });

      final client = Client(clientOptions, httpClient: mockClient);

      // Feed stream byte by byte to test buffering
      final stream = Stream<List<int>>.fromIterable(data.map((b) => [b]));

      final result = await client.putObject(
        'multipart.bin',
        stream,
        partSize: partSize,
      );

      expect(initCalled, isTrue);
      expect(part1Called, isTrue);
      expect(part2Called, isTrue);
      expect(completeCalled, isTrue);
      expect(result.etag, 'etag-final');
    });
  });
}
