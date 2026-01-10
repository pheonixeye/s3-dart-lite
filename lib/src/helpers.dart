import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'dart:convert';

typedef Uint8Array = Uint8List;

bool isValidPort(int port) {
  // Verify if port is in range.
  return port >= 1 && port <= 65535;
}

/// Validate a bucket name.
///
/// This is pretty minimal, general validation. We let the remote
/// S3 server do detailed validation.
///
/// https://docs.aws.amazon.com/AmazonS3/latest/userguide/bucketnamingrules.html
bool isValidBucketName(String bucket) {
  if (bucket.isEmpty) {
    return false;
  }
  // Generally the bucket name length limit is 63, but
  // "Before March 1, 2018, buckets created in the US East (N. Virginia)
  //  Region could have names that were up to 255 characters long"
  if (bucket.length > 255) {
    return false;
  }
  // "Bucket names must not contain two adjacent periods."
  if (bucket.contains("..")) {
    return false;
  }
  // "Bucket names must begin and end with a letter or number."
  // "Bucket names can consist only of lowercase letters, numbers,
  //  periods (.), and hyphens (-)."
  // -> Most S3 servers require lowercase bucket names but some allow
  // uppercase (Backblaze, AWS us-east buckets created before 2018)
  return RegExp(r"^[a-zA-Z0-9][a-zA-Z0-9.-]+[a-zA-Z0-9]$").hasMatch(bucket);
}

/// check if objectName is a valid object name
/// http://docs.aws.amazon.com/AmazonS3/latest/dev/UsingMetadata.html
bool isValidObjectName(String objectName) {
  if (!isValidPrefix(objectName)) return false;
  if (objectName.isEmpty) return false;
  return true;
}

// check if prefix is valid
bool isValidPrefix(String prefix) {
  if (prefix.length > 1024) return false;
  return true;
}

/// Convert some binary data to a hex string
String bin2hex(Uint8List binary) {
  return binary.map((b) => b.toRadixString(16).padLeft(2, "0")).join("");
}

String sanitizeETag(String etag) {
  const replaceChars = {
    '"': "",
    "&quot;": "",
    "&#34;": "",
    "&QUOT;": "",
    "&#x00022": "",
  };
  return etag.replaceAllMapped(
    RegExp(r'^("|&quot;|&#34;)|("|&quot;|&#34;)$'),
    (m) => replaceChars[m.group(0)!] ?? "",
  );
}

String? getVersionId(Map<String, String> headers) {
  // Field names are case-insensitive in HTTP, but typically we receive standard casing.
  // We'll standardise lookup if needed, but for now assuming caller provides map that handles case or exact match.
  // For safety with package:http, headers are case-insensitive.
  return headers["x-amz-version-id"];
}

/// Create a Date string with format: 'YYYYMMDDTHHmmss' + Z
String makeDateLong(DateTime date) {
  final dateStr = date.toUtc().toIso8601String();
  // dateStr is like "2017-08-07T16:28:59.889Z"
  // We want "20170807T162859Z"
  
  return "${dateStr.substring(0, 4)}${dateStr.substring(5, 7)}${dateStr.substring(8, 13)}${dateStr.substring(14, 16)}${dateStr.substring(17, 19)}Z";
}

/// Create a Date string with format: 'YYYYMMDD'
String makeDateShort(DateTime date) {
  return makeDateLong(date).substring(0, 8);
}

String getScope(String region, DateTime date) {
  return "${makeDateShort(date)}/$region/s3/aws4_request";
}

Future<String> sha256digestHex(dynamic data) async {
  List<int> bytes;
  if (data is Uint8List) {
    bytes = data;
  } else if (data is String) {
    bytes = utf8.encode(data);
  } else if (data is List<int>) {
    bytes = data;
  } else {
    throw ArgumentError("Invalid data type for sha256digestHex");
  }
  
  var digest = sha256.convert(bytes);
  return digest.toString();
}
