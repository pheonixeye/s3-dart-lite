import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'package:s3_dart_lite/src/errors.dart';
import 'package:s3_dart_lite/src/helpers.dart';
import 'package:s3_dart_lite/src/signing.dart';
import 'package:s3_dart_lite/src/object_uploader.dart';

/// Contains information about an object uploaded to S3.
class UploadedObjectInfo {
  /// The ETag of the uploaded object.
  final String etag;

  /// The version ID of the uploaded object, if versioning is enabled on the bucket.
  final String? versionId;

  /// Creates a new [UploadedObjectInfo] instance.
  UploadedObjectInfo(this.etag, this.versionId);

  @override
  String toString() => 'UploadedObjectInfo(etag: $etag, versionId: $versionId)';
}

/// Standard Metadata (headers) that can be set when interacting with an object.
const metadataKeys = [
  "Content-Type",
  "Cache-Control",
  "Content-Disposition",
  "Content-Encoding",
  "Content-Language",
  "Expires",
  "x-amz-item-checksum-sha256",
  // ... add others as needed
];

/// Configuration options for the S3 client.
class ClientOptions {
  /// The S3 endpoint URL (e.g., 'https://s3.amazonaws.com' or 'your-minio-server.com').
  final String endPoint;

  /// The access key for authentication.
  final String? accessKey;

  /// The secret key for authentication.
  final String? secretKey;

  /// The session token for temporary credentials (optional).
  final String? sessionToken;

  /// The default bucket to use for requests if not specified in the method call.
  final String? bucket;

  /// The AWS region (e.g., 'us-east-1').
  final String region;

  /// Whether to use path-style access (default: true).
  /// If true, accessing `https://endpoint/bucket/key`.
  /// If false, accessing `https://bucket.endpoint/key` (virtual-hosted style).
  final bool pathStyle;

  /// Whether to use SSL (HTTPS). Default is true.
  final bool useSSL;

  /// Explicit port number to connect to. Overrides the default port derived from scheme/useSSL.
  final int? port;

  /// Specific path prefix to append to the endpoint URL (e.g. for some proxy-ed setups).
  final String? pathPrefix;

  /// Creates a new [ClientOptions] instance.
  ClientOptions({
    required this.endPoint,
    required this.region,
    this.accessKey,
    this.secretKey,
    this.sessionToken,
    this.bucket,
    this.pathStyle = true,
    this.useSSL = true,
    this.port,
    this.pathPrefix,
  });
}

/// Represents an object stored in S3.
class S3Object {
  /// The key (path) of the object.
  final String key;

  /// The last modified timestamp of the object.
  final DateTime? lastModified;

  /// The ETag of the object.
  final String? etag;

  /// The size of the object in bytes.
  final int size;

  /// Creates a new [S3Object] instance.
  S3Object({
    required this.key,
    this.lastModified,
    this.etag,
    required this.size,
  });

  @override
  String toString() => 'S3Object(key: $key, size: $size, etag: $etag)';
}

/// Represents a common prefix (subdirectory) in a list objects response.
class CommonPrefix {
  /// The prefix string.
  final String prefix;
  CommonPrefix(this.prefix);
}

/// A client for interacting with S3-compatible storage services.
class Client {
  late final String host;
  late final int port;
  late final String protocol;
  final String? accessKey;
  final String secretKey;
  final String? sessionToken;
  final String? defaultBucket;
  final String region;
  final bool pathStyle;
  final String pathPrefix;

  // Use a persistent client for keep-alive
  final http.Client _httpClient;

  /// Creates a new [Client] with the given [options].
  ///
  /// Optionally provide a custom [httpClient] for testing or advanced configuration.
  Client(ClientOptions options, {http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client(),
      accessKey = options.accessKey,
      secretKey = options.secretKey ?? "",
      sessionToken = options.sessionToken,
      region = options.region,
      defaultBucket = options.bucket,
      pathStyle = options.pathStyle,
      pathPrefix = options.pathPrefix ?? "" {
    // Determine protocol and port
    if (options.endPoint.startsWith("http://")) {
      if (options.useSSL == true) {
        // Conflict logic ignored for now to match behavior
      }
      protocol = "http";
      port = options.port ?? 80;
    } else if (options.endPoint.startsWith("https://")) {
      protocol = "https";
      port = options.port ?? 443;
    } else {
      protocol = options.useSSL ? "https" : "http";
      port = options.port ?? (options.useSSL ? 443 : 80);
    }

    // Parse host
    String parsedHost;
    if (options.endPoint.contains("://")) {
      parsedHost = Uri.parse(options.endPoint).host;
    } else {
      parsedHost = options.endPoint;
    }

    // If explicit port is provided, append to host to match test expectation "s3...:5432"
    // But don't append if it's the default port for the protocol
    bool isDefaultPort =
        (protocol == "http" && port == 80) ||
        (protocol == "https" && port == 443);
    if (options.port != null && !isDefaultPort) {
      host = "$parsedHost:$port";
    } else {
      host = parsedHost;
    }
  }

  /// Closes the underlying HTTP client.
  void close() {
    _httpClient.close();
  }

  String _getBucketName(String? bucketName) {
    final b = bucketName ?? defaultBucket;
    if (b == null || !isValidBucketName(b)) {
      throw InvalidBucketNameError(b ?? "");
    }
    return b;
  }

  static String _encodeObjectName(String objectName) {
    // Encode every path segment but keep slashes
    return objectName.split('/').map(Uri.encodeComponent).join('/');
  }

  /// Make a raw request to S3.
  ///
  /// [method]: The HTTP method (GET, PUT, POST, DELETE, HEAD).
  /// [objectName]: The key of the object.
  /// [bucketName]: The bucket name (overrides default bucket).
  /// [headers]: Additional headers to send.
  /// [query]: Query parameters.
  /// [payload]: Body content (String, List<int>, or null).
  /// [expectedStatusCode]: If set, throws [ServerError] if response status doesn't match.
  Future<http.Response> makeRequest({
    required String method,
    String objectName = "",
    String? bucketName,
    Map<String, String>? headers,
    Map<String, String>? query,
    // Payload can be bytes or string
    dynamic payload,
    int? expectedStatusCode,
  }) async {
    final bucket = _getBucketName(bucketName);

    // Construct Path
    String path;
    String hostHeader;

    final encodedObject = _encodeObjectName(objectName);

    if (pathStyle) {
      hostHeader = host;
      path = "$pathPrefix/$bucket/$encodedObject";
    } else {
      hostHeader = "$bucket.$host";
      path = "/$encodedObject";
    }

    // Prepare headers
    final reqHeaders = <String, String>{};
    if (headers != null) {
      reqHeaders.addAll(headers);
    }
    reqHeaders["host"] = hostHeader;

    // Prepare payload
    Uint8List bodyBytes;
    if (payload == null) {
      bodyBytes = Uint8List(0);
    } else if (payload is String) {
      bodyBytes = utf8.encode(payload);
    } else if (payload is List<int>) {
      bodyBytes = Uint8List.fromList(payload);
    } else {
      throw ArgumentError("Invalid payload type");
    }

    if (method == "POST" || method == "PUT" || method == "DELETE") {
      reqHeaders["Content-Length"] = bodyBytes.length.toString();
    }

    // Date and Signature
    final date = DateTime.now();
    final sha256sum = await sha256digestHex(bodyBytes);

    reqHeaders["x-amz-date"] = makeDateLong(date);
    reqHeaders["x-amz-content-sha256"] = sha256sum;

    if (accessKey != null) {
      if (sessionToken != null) {
        reqHeaders["x-amz-security-token"] = sessionToken!;
      }

      String resourcePath = path;
      String queryString = "";
      if (query != null && query.isNotEmpty) {
        final uriParams = Uri(queryParameters: query).query;
        queryString = uriParams;

        if (queryString.isNotEmpty) {
          resourcePath += "?$queryString";
        }
      }

      reqHeaders["authorization"] = await signV4(
        headers: reqHeaders,
        method: method,
        path: resourcePath,
        accessKey: accessKey!,
        secretKey: secretKey,
        region: region,
        date: date,
      );
    }

    // Execute Request
    Uri finalUri;
    if (pathStyle) {
      finalUri = Uri.parse(
        "$protocol://$host$path",
      ).replace(queryParameters: query);
    } else {
      finalUri = Uri.parse(
        "$protocol://$bucket.$host$path",
      ).replace(queryParameters: query);
    }

    final finalRequest = http.Request(method, finalUri);
    finalRequest.headers.addAll(reqHeaders);
    finalRequest.bodyBytes = bodyBytes;

    final streamedResponse = await _httpClient.send(finalRequest);
    final response = await http.Response.fromStream(streamedResponse);

    if (expectedStatusCode != null &&
        response.statusCode != expectedStatusCode) {
      // Parse error
      final err = await parseServerError(response.statusCode, response.body);
      throw err;
    }

    if (response.statusCode >= 400) {
      final err = await parseServerError(response.statusCode, response.body);
      throw err;
    }

    return response;
  }

  /// Checks if an object exists in the specified [bucketName].
  /// Returns `true` if it exists, `false` otherwise.
  Future<bool> exists(String objectName, {String? bucketName}) async {
    try {
      await makeRequest(
        method: "HEAD",
        objectName: objectName,
        bucketName: bucketName,
        expectedStatusCode: 200,
      );
      return true;
    } catch (e) {
      if (e is ServerError && e.statusCode == 404) {
        return false;
      }
      rethrow;
    }
  }

  /// Deletes an object from the specified [bucketName].
  Future<void> deleteObject(String objectName, {String? bucketName}) async {
    await makeRequest(
      method: "DELETE",
      objectName: objectName,
      bucketName: bucketName,
      expectedStatusCode: 204,
    );
  }

  /// Lists objects in the specified [bucketName].
  ///
  /// [prefix]: Filter results to objects starting with this prefix.
  /// [maxResults]: Maximum number of items to return.
  Future<List<S3Object>> listObjects({
    String? bucketName,
    String? prefix,
    int? maxResults,
  }) async {
    final bucket = _getBucketName(bucketName);

    final query = <String, String>{
      "list-type": "2",
      if (prefix != null) "prefix": prefix,
    };

    if (maxResults != null) {
      query["max-keys"] = maxResults.toString();
    }

    final response = await makeRequest(
      method: "GET",
      bucketName: bucket,
      query: query,
    );

    // Parse XML
    final document = XmlDocument.parse(response.body);
    final contents = document.findAllElements("Contents");

    final results = <S3Object>[];
    for (final element in contents) {
      final key = element.findElements("Key").first.innerText;
      final size = int.parse(element.findElements("Size").first.innerText);
      final etag = element.findElements("ETag").firstOrNull?.innerText;
      final lm = element.findElements("LastModified").firstOrNull?.innerText;

      results.add(
        S3Object(
          key: key,
          size: size,
          etag: etag != null ? sanitizeETag(etag) : null,
          lastModified: lm != null ? DateTime.parse(lm) : null,
        ),
      );
    }

    return results;
  }

  /// Uploads an object to S3.
  ///
  /// [objectName]: The key/path for the object.
  /// [payload]: The content to upload. Can be `String`, `List<int>`, or `Stream<List<int>>`.
  /// [partSize]: Size of parts for multipart uploads (default 5MB).
  /// [metadata]: Custom metadata to store with the object.
  Future<UploadedObjectInfo> putObject(
    String objectName,
    dynamic payload, {
    String? bucketName,
    int? partSize,
    Map<String, String>? metadata,
  }) async {
    final bucket = _getBucketName(bucketName);

    Stream<List<int>> stream;
    if (payload is Stream<List<int>>) {
      stream = payload;
    } else if (payload is List<int>) {
      stream = Stream.value(payload);
    } else if (payload is String) {
      stream = Stream.value(utf8.encode(payload));
    } else {
      throw ArgumentError(
        "Invalid payload type. Expected Stream<List<int>>, List<int>, or String.",
      );
    }

    final uploader = ObjectUploader(
      client: this,
      bucketName: bucket,
      objectName: objectName,
      partSize: partSize ?? (5 * 1024 * 1024), // Default 5MB
      metadata: metadata ?? {},
    );

    return await uploader.upload(stream);
  }

  /// Retrieves an object from S3.
  ///
  /// Returns the raw [http.Response]. The body can be accessed via `response.bodyBytes`.
  Future<http.Response> getObject(
    String objectName, {
    String? bucketName,
  }) async {
    return await makeRequest(
      method: "GET",
      objectName: objectName,
      bucketName: bucketName,
      expectedStatusCode: 200,
    );
  }

  /// Generates a presigned URL for an object.
  ///
  /// [method]: The HTTP method to allow (e.g. GET, PUT).
  /// [expirySeconds]: How long the URL is valid for (default 7 days).
  /// [parameters]: Additional query parameters.
  /// [requestDate]: The date the request is signed (default now).
  Future<String> getPresignedUrl(
    String method,
    String objectName, {
    String? bucketName,
    int expirySeconds = 86400 * 7,
    Map<String, String>? parameters,
    DateTime? requestDate,
  }) async {
    final bucket = _getBucketName(bucketName);

    String path;
    String hostHeader;

    // For presigned URL, presignV4 handles encoding. Pass raw path segments.
    // However, presignV4 splits by slash and encodes segments?
    // If we rely on presignV4, we should pass raw objectName.
    // But we need to construct the full path prefix/bucket/object logic.
    // presignV4 (and awsUriEncode) simply encodes the string.

    if (pathStyle) {
      hostHeader = host;
      path = "$pathPrefix/$bucket/$objectName";
    } else {
      hostHeader = "$bucket.$host";
      path = "/$objectName";
    }

    final queryParams = <String, String>{};
    if (parameters != null) {
      queryParams.addAll(parameters);
    }

    // Construct query string for presignV4 inputs
    String queryString = "";
    if (queryParams.isNotEmpty) {
      queryString = "?${Uri(queryParameters: queryParams).query}";
    }

    final headers = <String, String>{"host": hostHeader};

    return await presignV4(
      protocol: protocol,
      headers: headers,
      method: method,
      path: path + queryString,
      accessKey: accessKey!,
      secretKey: secretKey,
      region: region,
      date: requestDate ?? DateTime.now(),
      expirySeconds: expirySeconds,
    );
  }
}
