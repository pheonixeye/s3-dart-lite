import 'dart:io';

import 'package:s3_dart_lite/s3_dart_lite.dart';

Future<void> main() async {
  final client = Client(
    ClientOptions(endPoint: '', region: '', accessKey: '', secretKey: ''),
  );

  final bucketName = '';
  final objectName = 'hello.txt';

  print('Downloading $objectName from $bucketName...');

  try {
    // Get object
    final response = await client.getObject(objectName, bucketName: bucketName);

    // Save to file
    final localFile = File('downloaded_$objectName');
    await localFile.writeAsBytes(response.bodyBytes);

    print('Successfully downloaded to ${localFile.path}');
    print('Content:');
    print(response.body);
  } catch (e) {
    print('Error downloading object: $e');
  } finally {
    client.close();
  }
}
