import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:s3_dart_lite/src/helpers.dart';
import 'package:s3_dart_lite/src/errors.dart';

const signV4Algorithm = "AWS4-HMAC-SHA256";

/// Generate the Authorization header required to authenticate an S3/AWS request.
Future<String> signV4({
  required Map<String, String> headers,
  required String method,
  required String path,
  required String accessKey,
  required String secretKey,
  required String region,
  required DateTime date,
}) async {
  if (accessKey.isEmpty) {
    throw AccessKeyRequiredError();
  }
  if (secretKey.isEmpty) {
    throw SecretKeyRequiredError();
  }

  // Ensure headers keys are lower case for processing, but keep values as is (except for trimming later)
  // Headers should be case-insensitive, but for signing we MUST work with lowercase keys in the canonical request.
  final caseInsensitiveHeaders = canonicalizeHeadersMap(headers);

  final sha256sum = caseInsensitiveHeaders["x-amz-content-sha256"];
  if (sha256sum == null) {
    throw Exception(
      "Internal S3 client error - expected x-amz-content-sha256 header, but it's missing.",
    );
  }

  final signedHeaders = getHeadersToSign(caseInsensitiveHeaders);
  final canonicalRequest = getCanonicalRequest(
    method,
    path,
    caseInsensitiveHeaders,
    signedHeaders,
    sha256sum,
  );

  final stringToSign = await getStringToSign(canonicalRequest, date, region);

  final signingKey = await getSigningKey(date, region, secretKey);

  final credential = getCredential(accessKey, region, date);

  var hmac = Hmac(sha256, signingKey);
  var digest = hmac.convert(utf8.encode(stringToSign));
  final signature = digest.toString().toLowerCase();

  return "$signV4Algorithm Credential=$credential, SignedHeaders=${signedHeaders.join(";").toLowerCase()}, Signature=$signature";
}

/// Generate a pre-signed URL
Future<String> presignV4({
  required String protocol,
  required Map<String, String> headers,
  required String method,
  required String path,
  required String accessKey,
  required String secretKey,
  String? sessionToken,
  required String region,
  required DateTime date,
  required int expirySeconds,
}) async {
  if (accessKey.isEmpty) {
    throw AccessKeyRequiredError();
  }
  if (secretKey.isEmpty) {
    throw SecretKeyRequiredError();
  }
  if (expirySeconds < 1 || expirySeconds > 604800) {
    throw InvalidExpiryError();
  }

  final caseInsensitiveHeaders = canonicalizeHeadersMap(headers);
  if (!caseInsensitiveHeaders.containsKey("host")) {
    throw Exception("Internal error: host header missing");
  }

  // Information about the future request that we're going to sign:
  final pathParts = path.split("?");
  final resource = pathParts[0];
  final queryString = pathParts.length > 1 ? pathParts[1] : "";

  final iso8601Date = makeDateLong(date);
  final signedHeaders = getHeadersToSign(caseInsensitiveHeaders);
  final credential = getCredential(accessKey, region, date);
  const hashedPayload = "UNSIGNED-PAYLOAD";

  // Build the query string for our new signed URL:
  final queryParams = Uri.splitQueryString(queryString); // This decodes values
  // We need to construct a map that we will then encode and sort.

  final newQuery = <String, String>{};
  queryParams.forEach((k, v) => newQuery[k] = v);

  newQuery["X-Amz-Algorithm"] = signV4Algorithm;
  newQuery["X-Amz-Credential"] = credential;
  newQuery["X-Amz-Date"] = iso8601Date;
  newQuery["X-Amz-Expires"] = expirySeconds.toString();
  newQuery["X-Amz-SignedHeaders"] = signedHeaders.join(";").toLowerCase();
  if (sessionToken != null) {
    newQuery["X-Amz-Security-Token"] = sessionToken;
  }

  // Canonical query string must be sorted by key
  // And keys/values must be URI encoded.
  // Note: Uri.queryParameters encodes spaces as +, but S3 V4 requires %20.
  // We'll handle this in getCanonicalRequest / manual construction.

  // Construct the query string manually to control encoding perfectly
  final sortedKeys = newQuery.keys.toList()..sort();
  final newQueryStringParts = <String>[];
  for (var key in sortedKeys) {
    final val = newQuery[key]!;
    newQueryStringParts.add("${awsUriEncode(key)}=${awsUriEncode(val)}");
  }
  final newQueryString = newQueryStringParts.join("&");

  final signingPath = "$resource?$newQueryString";

  // resource for canonical request needs to be encoded, except slashes
  // But wait, the path passed to this function is already constructed?
  // In TS version: `const encodedPath = resource.split("/").map((part) => encodeURIComponent(part)).join("/");`
  // We'll do similar logic inside getCanonicalRequest or just here.

  // Let's reproduce the TS logic carefully.
  final encodedPath = resource
      .split("/")
      .map((part) => Uri.encodeComponent(part))
      .join("/");

  final canonicalRequest = getCanonicalRequest(
    method,
    signingPath,
    caseInsensitiveHeaders,
    signedHeaders,
    hashedPayload,
  );

  final stringToSign = await getStringToSign(canonicalRequest, date, region);
  final signingKey = await getSigningKey(date, region, secretKey);

  var hmac = Hmac(sha256, signingKey);
  var digest = hmac.convert(utf8.encode(stringToSign));
  final signature = digest.toString().toLowerCase();

  final host = caseInsensitiveHeaders["host"];
  final proto = protocol.endsWith(":") ? protocol : "$protocol:";
  return "$proto//$host$encodedPath?$newQueryString&X-Amz-Signature=$signature";
}

/// Helper to ensure headers map is lowercase keys
Map<String, String> canonicalizeHeadersMap(Map<String, String> headers) {
  return headers.map((key, value) => MapEntry(key.toLowerCase(), value));
}

List<String> getHeadersToSign(Map<String, String> headers) {
  const ignoredHeaders = [
    "authorization",
    "content-length",
    "content-type",
    "user-agent",
  ];
  final headersToSign = <String>[];
  for (final key in headers.keys) {
    if (ignoredHeaders.contains(key.toLowerCase())) {
      continue;
    }
    headersToSign.add(key.toLowerCase());
  }
  headersToSign.sort();
  return headersToSign;
}

const allowableBytes = [45, 46, 95, 126]; // - . _ ~

/// Canonical URI encoding for signing
String awsUriEncode(String string, [bool allowSlashes = false]) {
  final bytes = utf8.encode(string);
  final result = StringBuffer();

  for (final byte in bytes) {
    if ((byte >= 65 && byte <= 90) || // A-Z
        (byte >= 97 && byte <= 122) || // a-z
        (byte >= 48 && byte <= 57) || // 0-9
        allowableBytes.contains(byte) ||
        (byte == 47 && allowSlashes)) {
      // /
      result.writeCharCode(byte);
    } else {
      result.write("%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}");
    }
  }
  return result.toString();
}

String getCanonicalRequest(
  String method,
  String path,
  Map<String, String> headers,
  List<String> headersToSign,
  String payloadHash,
) {
  final headersList = <String>[];
  for (final headerKey in headersToSign) {
    final val = headers[headerKey]?.replaceAll(RegExp(r' +'), ' ') ?? "";
    headersList.add("$headerKey:$val");
  }

  final pathParts = path.split("?");
  final requestResource = pathParts[0];
  var requestQuery = pathParts.length > 1 ? pathParts[1] : "";

  if (requestQuery.isNotEmpty) {
    // Split, decode, then re-encode and sort.
    // We will parse it manually to avoid issues with standard parsers eating duplicates or reordering
    // But map doesn't support duplicates. S3 query params generally don't duplicate keys for signing purposes often?
    // The TS version maps strictly from string split.

    final sortedEncodedParams = requestQuery.split("&").map((element) {
      final parts = element.split("=");
      final key = parts[0];
      final val = parts.length > 1 ? parts[1] : "";
      return "${awsUriEncode(Uri.decodeComponent(key))}=${awsUriEncode(Uri.decodeComponent(val))}";
    }).toList()..sort();

    requestQuery = sortedEncodedParams.join("&");
  }

  return [
    method.toUpperCase(),
    awsUriEncode(requestResource, true),
    requestQuery,
    "${headersList.join('\n')}\n",
    headersToSign.join(";").toLowerCase(),
    payloadHash,
  ].join("\n");
}

Future<String> getStringToSign(
  String canonicalRequest,
  DateTime requestDate,
  String region,
) async {
  final hash = await sha256digestHex(canonicalRequest);
  final scope = getScope(region, requestDate);
  return [signV4Algorithm, makeDateLong(requestDate), scope, hash].join("\n");
}

Future<List<int>> getSigningKey(
  DateTime date,
  String region,
  String secretKey,
) async {
  final dateLine = makeDateShort(date);
  final hmac1 = await sha256hmac(
    utf8.encode("AWS4$secretKey"),
    utf8.encode(dateLine),
  );
  final hmac2 = await sha256hmac(hmac1, utf8.encode(region));
  final hmac3 = await sha256hmac(hmac2, utf8.encode("s3"));
  return await sha256hmac(hmac3, utf8.encode("aws4_request"));
}

String getCredential(String accessKey, String region, DateTime requestDate) {
  return "$accessKey/${getScope(region, requestDate)}";
}

Future<List<int>> sha256hmac(List<int> key, List<int> data) async {
  var hmac = Hmac(sha256, key);
  return hmac.convert(data).bytes;
}

/// Standard S3 policy condition type (simplified for Dart)
typedef PolicyCondition = Map<String, dynamic>;
// Note: In TS it was Record<string, unknown> | string[].
// In Dart, we can use Map<String, dynamic> for objects, and List<dynamic> for ["starts-with", ...]

/// Generate a presigned POST policy that can be used to allow direct uploads to S3.
Future<Map<String, dynamic>> presignPostV4({
  required String host,
  required String protocol,
  required String bucket,
  required String objectKey,
  required String accessKey,
  required String secretKey,
  required String region,
  required DateTime date,
  required int expirySeconds,
  List<dynamic>? conditions,
  Map<String, String>? fields,
}) async {
  if (accessKey.isEmpty) {
    throw AccessKeyRequiredError();
  }
  if (secretKey.isEmpty) {
    throw SecretKeyRequiredError();
  }
  if (expirySeconds < 1 || expirySeconds > 604800) {
    throw InvalidExpiryError();
  }

  final expiration = date.add(Duration(seconds: expirySeconds));
  final credential = getCredential(accessKey, region, date);
  final iso8601Date = makeDateLong(date);

  // Default required policy fields
  final policyFields = <String, String>{
    "X-Amz-Algorithm": signV4Algorithm,
    "X-Amz-Credential": credential,
    "X-Amz-Date": iso8601Date,
    "key": objectKey,
  };

  if (fields != null) {
    policyFields.addAll(fields);
  }

  // Build policy document
  final policyConditions = <dynamic>[
    {"bucket": bucket},
    {"key": objectKey},
    {"X-Amz-Algorithm": signV4Algorithm},
    {"X-Amz-Credential": credential},
    {"X-Amz-Date": iso8601Date},
  ];

  // Add any additional conditions provided by the user
  if (conditions != null) {
    policyConditions.addAll(conditions);
  }

  // Add additional fields as conditions
  if (fields != null) {
    for (final entry in fields.entries) {
      if ([
        "key",
        "X-Amz-Algorithm",
        "X-Amz-Credential",
        "X-Amz-Date",
      ].contains(entry.key)) {
        continue;
      }
      policyConditions.add({entry.key: entry.value});
    }
  }

  final policy = {
    "expiration": expiration.toUtc().toIso8601String(),
    "conditions": policyConditions,
  };

  // Convert policy to base64
  final policyJson = jsonEncode(policy);
  final policyBytes = utf8.encode(policyJson);
  final base64Policy = base64.encode(policyBytes);

  policyFields["policy"] = base64Policy;

  // Calculate signature
  final stringToSign = base64Policy;
  final signingKey = await getSigningKey(date, region, secretKey);
  final signature = bin2hex(
    Uint8List.fromList(await sha256hmac(signingKey, utf8.encode(stringToSign))),
  ).toLowerCase();

  policyFields["X-Amz-Signature"] = signature;

  // Construct the URL
  // Ensure protocol has colon if missing (Client passes "https" or "http")
  final proto = protocol.endsWith(":") ? protocol : "$protocol:";
  final url = "$proto//$host/$bucket";

  return {"url": url, "fields": policyFields};
}
