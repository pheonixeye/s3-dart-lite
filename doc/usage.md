# Usage

## Initialization

Initialize the client with your S3 compatible service credentials.

```dart
import 'package:s3_dart_lite/s3_dart_lite.dart';

final client = Client(ClientOptions(
  endPoint: 's3.us-east-1.amazonaws.com',
  region: 'us-east-1',
  accessKey: 'YOUR_ACCESS_KEY',
  secretKey: 'YOUR_SECRET_KEY',
));
```

## Uploading Objects

`s3-dart-lite` supports streaming uploads, which is efficient for large files.

```dart
import 'dart:io';

final file = File('large-video.mp4');
final stream = file.openRead();

await client.putObject(
  'videos/large-video.mp4',
  stream,
  bucketName: 'my-bucket',
);
```

You can also upload simple strings or byte lists:

```dart
await client.putObject('notes.txt', 'Hello World', bucketName: 'my-bucket');
```

## Downloading Objects

```dart
final response = await client.getObject('notes.txt', bucketName: 'my-bucket');
print(response.body);
```

## List Objects

```dart
final objects = await client.listObjects(bucketName: 'my-bucket', prefix: 'videos/');
for (final obj in objects) {
  print('${obj.key} - ${obj.size} bytes');
}
```

## Presigned URLs

Generate a URL to allow temporary access to an object without credentials.

```dart
final url = await client.getPresignedUrl('GET', 'videos/secret.mp4', expirySeconds: 3600);
print('Share this URL: $url');
```
