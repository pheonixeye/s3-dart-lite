import 'dart:async';
import 'dart:typed_data';

import 'package:s3_dart_lite/src/client.dart';
import 'package:s3_dart_lite/src/helpers.dart';
import 'package:xml/xml.dart';

// Metadata headers that must be included in each part of a multi-part upload
const multipartTagAlongMetadataKeys = [
  "x-amz-server-side-encryption-customer-algorithm",
  "x-amz-server-side-encryption-customer-key",
  "x-amz-server-side-encryption-customer-key-MD5",
];

/// The minimum allowed part size for multi-part uploads.
const minimumPartSize = 5 * 1024 * 1024;

/// The maximum allowed part size for multi-part uploads.
const maximumPartSize = 5 * 1024 * 1024 * 1024;

class ObjectUploader {
  final Client client;
  final String bucketName;
  final String objectName;
  final int partSize;
  final Map<String, String> metadata;

  // We accumulate chunks until they reach partSize
  final _buffer = <int>[];
  int _partNumber = 1;
  String? _uploadId;
  final _etags = <Map<String, dynamic>>[];

  // For tracking parallel uploads
  final _uploads = <Future<void>>[];
  Object? _error;

  ObjectUploader({
    required this.client,
    required this.bucketName,
    required this.objectName,
    required this.partSize,
    required this.metadata,
  });

  /// Consume the stream and upload
  Future<UploadedObjectInfo> upload(Stream<List<int>> stream) async {
    try {
      await for (final chunk in stream) {
        _buffer.addAll(chunk);

        while (_buffer.length >= partSize) {
          // We have enough data for a part
          // Take exactly partSize
          final partData = Uint8List.fromList(_buffer.sublist(0, partSize));
          _buffer.removeRange(0, partSize);

          await _uploadPart(partData, false);
        }
      }

      // Upload remaining data
      await _uploadPart(Uint8List.fromList(_buffer), true);

      // Wait for all uploads to complete
      await Future.wait(_uploads);

      if (_error != null) {
        throw _error!;
      }

      if (_uploadId == null) {
        // Single part upload happened
        if (_singleUploadResult == null) {
          throw Exception(
            "No data uploaded (Single upload failed via internal logic mismatch)",
          );
        }
        // Return result below
      } else {
        // Complete multipart
        _etags.sort((a, b) => (a['part'] as int).compareTo(b['part'] as int));
        return await _completeMultipartUpload();
      }

      return _singleUploadResult!;
    } catch (e) {
      if (_uploadId != null) {
        // Abort multipart?
        // S3 client doesn't abort automatically usually, but good practice.
      }
      rethrow;
    }
  }

  UploadedObjectInfo? _singleUploadResult;

  Future<void> _uploadPart(Uint8List data, bool isLast) async {
    if (_error != null) return;

    final currentPartNumber = _partNumber++;

    // Check if we can do single upload
    if (currentPartNumber == 1 && isLast) {
      // Single upload
      final response = await client.makeRequest(
        method: "PUT",
        bucketName: bucketName,
        objectName: objectName,
        headers: {...metadata, "Content-Length": data.length.toString()},
        payload: data,
        expectedStatusCode: 200,
      );

      _singleUploadResult = UploadedObjectInfo(
        sanitizeETag(
          response.headers['etag'] ?? response.headers['ETag'] ?? "",
        ),
        getVersionId(response.headers),
      );
      return;
    }

    // Multipart logic
    _uploadId ??= await _initiateNewMultipartUpload();

    final uploadId = _uploadId!;

    // If we are here, we are uploading a part.
    // We should run this concurrently if possible, but keep order of partNumbers logic simplicity.
    // We spawning a future.

    final future = Future(() async {
      try {
        final partHeaders = <String, String>{
          "Content-Length": data.length.toString(),
        };
        for (final key in multipartTagAlongMetadataKeys) {
          if (metadata.containsKey(key)) {
            partHeaders[key] = metadata[key]!;
          }
        }

        final response = await client.makeRequest(
          method: "PUT",
          bucketName: bucketName,
          objectName: objectName,
          query: {
            "partNumber": currentPartNumber.toString(),
            "uploadId": uploadId,
          },
          headers: partHeaders,
          payload: data,
          expectedStatusCode: 200,
        );

        String etag =
            response.headers['etag'] ?? response.headers['ETag'] ?? "";
        etag = etag.replaceAll(RegExp(r'^"|"$'), ""); // Strip quotes

        _etags.add({"part": currentPartNumber, "etag": etag});
      } catch (e) {
        _error ??= e;
        rethrow;
      }
    });

    _uploads.add(future);
  }

  Future<String> _initiateNewMultipartUpload() async {
    final response = await client.makeRequest(
      method: "POST",
      bucketName: bucketName,
      objectName: objectName,
      query: {"uploads": ""},
      headers: metadata,
      expectedStatusCode: 200,
    );

    final document = XmlDocument.parse(response.body);
    final uploadId = document.findAllElements("UploadId").first.innerText;
    return uploadId;
  }

  Future<UploadedObjectInfo> _completeMultipartUpload() async {
    final partsXml = _etags
        .map(
          (e) =>
              "<Part><PartNumber>${e['part']}</PartNumber><ETag>${e['etag']}</ETag></Part>",
        )
        .join("");

    final payload =
        '<CompleteMultipartUpload xmlns="http://s3.amazonaws.com/doc/2006-03-01/">$partsXml</CompleteMultipartUpload>';

    final response = await client.makeRequest(
      method: "POST",
      bucketName: bucketName,
      objectName: objectName,
      query: {"uploadId": _uploadId!},
      payload: payload,
      expectedStatusCode: 200,
    );

    final document = XmlDocument.parse(response.body);
    // Might need to check for Error in body even if 200 OK (S3 oddity)
    if (document.rootElement.name.local == "Error") {
      throw Exception("S3 Error despite 200 OK: ${response.body}");
    }

    final etag = document.findAllElements("ETag").first.innerText;
    final versionId = getVersionId(response.headers);

    return UploadedObjectInfo(sanitizeETag(etag), versionId);
  }
}
