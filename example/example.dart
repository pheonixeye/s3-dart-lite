import 'dart:convert';

import 'package:s3_dart_lite/s3_dart_lite.dart';

void main() async {
  // 1. Initialize the Client
  // Replace these with real credentials or a local MinIO setup for actual testing.
  final client = Client(
    ClientOptions(
      endPoint: 's3.us-east-1.amazonaws.com',
      accessKey: 'AKIAIOSFODNN7EXAMPLE',
      secretKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
      bucket: 'my-test-bucket',
      region: 'us-east-1',
      useSSL: true, // Set to false for local testing without https
      // port: 9000, // Uncomment for MinIO
      // pathStyle: true, // Common for MinIO
    ),
  );

  try {
    const objectKey = 'hello-world.txt';
    const content = 'Hello, S3 from Dart!';

    print('--- 1. Putting Object ---');
    // 2. Upload an object
    final uploadInfo = await client.putObject(
      objectKey,
      content,
      metadata: {'x-custom-meta': 'custom-value'},
    );
    print('Uploaded: $objectKey');
    print('ETag: ${uploadInfo.etag}');
    print('VersionID: ${uploadInfo.versionId}');

    print('\n--- 2. Checking Existence ---');
    // 3. Check if it exists
    final exists = await client.exists(objectKey);
    print('Object "$objectKey" exists: $exists');

    if (exists) {
      print('\n--- 3. Listing Objects ---');
      // 4. List objects
      final objects = await client.listObjects(prefix: 'hello');
      for (final obj in objects) {
        print('Found: ${obj.key} (Size: ${obj.size} bytes)');
      }

      print('\n--- 4. Getting Object ---');
      // 5. Download object
      final response = await client.getObject(objectKey);
      final downloadedContent = utf8.decode(response.bodyBytes);
      print('Downloaded content: $downloadedContent');

      print('\n--- 5. Generating Presigned URL ---');
      // 6. Generate presigned URL
      final url = await client.getPresignedUrl(
        'GET',
        objectKey,
        expirySeconds: 3600,
      );
      print('Presigned URL (valid for 1h): $url');

      print('\n--- 6. Deleting Object ---');
      // 7. Delete object
      await client.deleteObject(objectKey);
      print('Deleted: $objectKey');

      final existsAfterDelete = await client.exists(objectKey);
      print('Object exists after delete: $existsAfterDelete');
    }
  } catch (e) {
    print('Error occurred: $e');
  } finally {
    // 8. Close the client
    client.close();
  }
}
