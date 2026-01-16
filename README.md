# s3-dart-lite

A lightweight S3 client for Dart, ported from the excellent TypeScript [s3-lite-client](https://github.com/bradenmacdonald/s3-lite-client).

> [!WARNING]
> **ALPHA STAGE**: This project is currently in the alpha stage and is NOT ready for production use. APIs may change, and not all features from the original client are implemented or fully tested. Use with specific caution.

## Features

- **Lightweight**: Minimal dependencies, focused on core S3 functionality.
- **S3 Compatible**: Works with AWS S3, MinIO, DigitalOcean Spaces, and other S3-compatible storage providers.
- **Dart Native**: Built with Dart idioms, supporting `Stream<List<int>>` for efficient uploads and downloads.

## Documentation

- [**API Reference**](doc/api/index.html) (Generated via `dart doc`)
- [**Project Documentation**](md/index.md) (Guides and Tutorials)


## Project Structure

- **`lib/src/client.dart`**: The main `Client` class handling request orchestration and configuration.
- **`lib/src/signing.dart`**: Implementation of AWS Signature V4 for request signing.
- **`lib/src/object_uploader.dart`**: Handles smart uploads (automatically switching between single-part and multipart based on stream analysis).
- **`lib/src/helpers.dart`**: Validation and formatting utilities.
- **`lib/src/errors.dart`**: Custom error types and XML error response parsing.

## Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  s3_dart_lite: ^0.0.2
```

## Usage

### Initialization

```dart
import 'package:s3_dart_lite/s3_dart_lite.dart';

final client = Client(
  ClientOptions(
    endPoint: 's3.us-east-1.amazonaws.com', // or your custom endpoint
    region: 'us-east-1',
    accessKey: 'YOUR_ACCESS_KEY',
    secretKey: 'YOUR_SECRET_KEY',
    useSSL: true, // defaults to true
  ),
);
```

### Uploading a File

You can upload files using `Stream<List<int>>`, `List<int>` bytes, or `String` content.

```dart
import 'dart:io';

// ... client init ...

final file = File('hello.txt');
final stream = file.openRead();

try {
  await client.putObject(
    'hello.txt',
    stream,
    bucketName: 'my-bucket',
  );
  print('Upload complete');
} catch (e) {
  print('Upload failed: $e');
}
```

### Downloading a File

```dart
import 'dart:io';

// ... client init ...

try {
  final response = await client.getObject(
    'hello.txt', 
    bucketName: 'my-bucket'
  );
  
  // Save to file
  await File('downloaded_hello.txt').writeAsBytes(response.bodyBytes);
  print('Download complete');
} catch (e) {
  print('Download failed: $e');
}
```

## Credits

This project is a port of [s3-lite-client](https://github.com/bradenmacdonald/s3-lite-client) by [Braden MacDonald](https://github.com/bradenmacdonald). Huge thanks to the original authors for the solid foundation and design.

## License

MIT
