/// All the errors which can be thrown by this S3 client.
/// Every error is a subclass of [S3Error].
library;

import 'package:xml/xml.dart';

/// Base class for all errors raised by this S3 client.
class S3Error extends Error {
  final String message;

  S3Error(this.message);

  @override
  String toString() => "S3Error: $message";
}

/// An argument or configuration parameter was invalid.
class InvalidArgumentError extends S3Error {
  InvalidArgumentError(super.message);
}

/// InvalidEndpointError is generated when an invalid end point value is
/// provided which does not follow domain standards.
class InvalidEndpointError extends S3Error {
  /// Creates a new [InvalidEndpointError] with the given [message].
  InvalidEndpointError(super.message);
}

/// InvalidBucketNameError is generated when an invalid bucket name is
/// provided which does not follow AWS S3 specifications.
///
/// See: http://docs.aws.amazon.com/AmazonS3/latest/dev/BucketRestrictions.html
class InvalidBucketNameError extends S3Error {
  final String bucketName;
  InvalidBucketNameError(this.bucketName)
    : super("Invalid bucket name: $bucketName");
}

/// InvalidObjectNameError is generated when an invalid object name is
/// provided which does not follow AWS S3 specifications.
///
/// See: http://docs.aws.amazon.com/AmazonS3/latest/dev/UsingMetadata.html
class InvalidObjectNameError extends S3Error {
  final String objectName;
  InvalidObjectNameError(this.objectName)
    : super("Invalid object name: $objectName");
}

/// The request cannot be made without an access key to authenticate it.
class AccessKeyRequiredError extends S3Error {
  /// Creates a new [AccessKeyRequiredError].
  AccessKeyRequiredError() : super("accessKey is required");
}

/// The request cannot be made without a secret key to authenticate it.
class SecretKeyRequiredError extends S3Error {
  /// Creates a new [SecretKeyRequiredError].
  SecretKeyRequiredError() : super("secretKey is required");
}

/// The expiration time for the request is invalid
class InvalidExpiryError extends S3Error {
  InvalidExpiryError()
    : super("expirySeconds cannot be less than 1 second or more than 7 days");
}

/// Any error thrown by the server.
/// Contains the status code, error code, and detailed message.
class ServerError extends S3Error {
  /// HTTP status code returned by the server.
  final int statusCode;

  /// S3 error code (e.g. 'NoSuchKey').
  final String code;

  /// The Key of the object involved in the error, if applicable.
  final String? key;

  /// The BucketName involved in the error, if applicable.
  final String? bucketName;

  /// The Resource involved in the error, if applicable.
  final String? resource;

  /// The Region where the error occurred, if applicable.
  final String? region;

  /// Creates a new [ServerError].
  ServerError(
    this.statusCode,
    this.code,
    String message, {
    this.key,
    this.bucketName,
    this.resource,
    this.region,
  }) : super(message);

  @override
  String toString() => "ServerError: $code (Status $statusCode): $message";
}

/// Helper function to parse an error returned by the S3 server.
Future<ServerError> parseServerError(
  int statusCode,
  String responseBody,
) async {
  try {
    final document = XmlDocument.parse(responseBody);
    final errorRoot = document.rootElement;

    if (errorRoot.name.local != "Error") {
      throw FormatException("Invalid root, expected <Error>");
    }

    final code =
        errorRoot.findElements("Code").firstOrNull?.innerText ??
        "UnknownErrorCode";
    final message =
        errorRoot.findElements("Message").firstOrNull?.innerText ??
        "The error message could not be determined.";
    final key = errorRoot.findElements("Key").firstOrNull?.innerText;
    final bucketName = errorRoot
        .findElements("BucketName")
        .firstOrNull
        ?.innerText;
    final resource = errorRoot.findElements("Resource").firstOrNull?.innerText;
    final region = errorRoot.findElements("Region").firstOrNull?.innerText;

    return ServerError(
      statusCode,
      code,
      message,
      key: key,
      bucketName: bucketName,
      resource: resource,
      region: region,
    );
  } catch (e) {
    return ServerError(
      statusCode,
      "UnrecognizedError",
      "Error: Unexpected response code $statusCode. Unable to parse response as XML. Original error: $e",
    );
  }
}
