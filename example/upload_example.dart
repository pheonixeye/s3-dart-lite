import 'dart:io';

import 'package:s3_dart_lite/s3_dart_lite.dart';

Future<void> main() async {
  final client = Client(
    ClientOptions(endPoint: '', region: '', accessKey: '', secretKey: ''),
  );
  // define file
  final file = File('./hello.txt');
  // Upload
  await client.putObject(
    file.uri.toFilePath().split('/').last,
    file.openRead(),
    bucketName: '',
  );
  // List
  final objects = await client.listObjects(bucketName: '');
  for (var obj in objects) {
    print(obj.key);
  }

  client.close();
}
