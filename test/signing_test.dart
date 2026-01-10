// ignore_for_file: prefer_adjacent_string_concatenation

import 'package:test/test.dart';
import 'package:s3_dart_lite/src/signing.dart';
import 'package:s3_dart_lite/src/helpers.dart';
import 'dart:convert';
import 'dart:typed_data';

void main() {
  group('signV4', () {
    test('test 1', () async {
      final authHeaderActual = await signV4(
        method: "POST",
        path: "/bucket/object",
        headers: {
          "host": "localhost:9000",
          "x-amz-content-sha256":
              "3a6eb0790f39ac87c94f3856b2dd2c5d110e6811602261a9a923d3bb23adc8b7",
        },
        accessKey: "AKIA_TEST_ACCESS_KEY",
        secretKey: "ThisIsTheSecret",
        region: "ca-central-1",
        date: DateTime.parse("2021-10-26T18:07:28.492Z"),
      );
      expect(
        authHeaderActual,
        "AWS4-HMAC-SHA256 Credential=AKIA_TEST_ACCESS_KEY/20211026/ca-central-1/s3/aws4_request, SignedHeaders=host;x-amz-content-sha256, Signature=29a1fe12b9d7ae705af5e01614deaacaf435fe2081949e05b02d4fd7b4bc82a9",
      );
    });

    test('test 2', () async {
      final authHeaderActual = await signV4(
        method: "GET",
        path: "/object/key/here?query1=test&query2=234567",
        headers: {
          "Host": "s3.amazonaws.com",
          "Content-Type": "image/svg+xml",
          "Cache-Control": "public, max-age=604800, immutable",
          "Content-Disposition": 'attachment; filename="image.svg"',
          "x-amz-storage-class": "GLACIER",
          "x-amz-content-sha256":
              "3a6eb0790f39ac87c94f3856b2dd2c5d110e6811602261a9a923d3bb23adc8b7",
        },
        accessKey: "accesskey123",
        secretKey: "#\$*&!#@%&(#@\$(*",
        region: "test-region",
        date: DateTime.parse("2020-05-13T12:09:14.377Z"),
      );
      expect(
        authHeaderActual,
        "AWS4-HMAC-SHA256 Credential=accesskey123/20200513/test-region/s3/aws4_request, SignedHeaders=cache-control;content-disposition;host;x-amz-content-sha256;x-amz-storage-class, Signature=0fcf3962ff9c6ddcfd31d7cdfb42cd70e187790a16fba5402854417a1ac83ba5",
      );
    });
  });

  group('presignV4', () {
    test('test 1', () async {
      final urlActual = await presignV4(
        protocol: "https",
        method: "POST",
        path: "/bucket/object",
        headers: {"host": "localhost:9000"},
        accessKey: "AKIA_TEST_ACCESS_KEY",
        secretKey: "ThisIsTheSecret",
        region: "ca-central-1",
        date: DateTime.parse("2021-10-26T18:07:28.492Z"),
        expirySeconds: 60 * 60,
      );
      expect(
        urlActual,
        "https://localhost:9000/bucket/object?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIA_TEST_ACCESS_KEY%2F20211026%2Fca-central-1%2Fs3%2Faws4_request&X-Amz-Date=20211026T180728Z&X-Amz-Expires=3600&X-Amz-SignedHeaders=host&X-Amz-Signature=def1ddcb522798495b6b72970222eceef7d6070f131d12d819b81fb308503dfe",
      );
    });
  });

  group('presignPostV4', () {
    test('test 1', () async {
      final result = await presignPostV4(
        protocol: "https",
        objectKey: "object/key",
        host: "localhost:9000",
        bucket: "bucket",
        accessKey: "AKIA_TEST_ACCESS_KEY",
        secretKey: "ThisIsTheSecret",
        region: "ca-central-1",
        date: DateTime.parse("2021-10-26T18:07:28.492Z"),
        expirySeconds: 60 * 60,
      );
      expect(result, {
        "url": "https://localhost:9000/bucket",
        "fields": {
          "X-Amz-Algorithm": "AWS4-HMAC-SHA256",
          "X-Amz-Credential":
              "AKIA_TEST_ACCESS_KEY/20211026/ca-central-1/s3/aws4_request",
          "X-Amz-Date": "20211026T180728Z",
          "X-Amz-Signature":
              "dcb50728314b09118100a74c8093dc0b5861ffa79666382c79df5ecc66c978d8",
          "key": "object/key",
          "policy":
              "eyJleHBpcmF0aW9uIjoiMjAyMS0xMC0yNlQxOTowNzoyOC40OTJaIiwiY29uZGl0aW9ucyI6W3siYnVja2V0IjoiYnVja2V0In0seyJrZXkiOiJvYmplY3Qva2V5In0seyJYLUFtei1BbGdvcml0aG0iOiJBV1M0LUhNQUMtU0hBMjU2In0seyJYLUFtei1DcmVkZW50aWFsIjoiQUtJQV9URVNUX0FDQ0VTU19LRVkvMjAyMTEwMjYvY2EtY2VudHJhbC0xL3MzL2F3czRfcmVxdWVzdCJ9LHsiWC1BbXotRGF0ZSI6IjIwMjExMDI2VDE4MDcyOFoifV19",
        },
      });
    });

    test('test 2', () async {
      final result = await presignPostV4(
        protocol: "https",
        objectKey: "foo/bar/tribble",
        host: "localhost:9000",
        bucket: "bucket",
        accessKey: "AKIA_TEST_ACCESS_KEY",
        secretKey: "ThisIsTheSecret",
        region: "ca-central-1",
        date: DateTime.parse("2021-10-26T18:07:28.492Z"),
        expirySeconds: 60 * 60,
        fields: {"custom-field1": "cf1-value"},
        conditions: [
          ["starts-with", "\$key", "foo/bar"],
        ],
      );
      expect(result, {
        "url": "https://localhost:9000/bucket",
        "fields": {
          "X-Amz-Algorithm": "AWS4-HMAC-SHA256",
          "X-Amz-Credential":
              "AKIA_TEST_ACCESS_KEY/20211026/ca-central-1/s3/aws4_request",
          "X-Amz-Date": "20211026T180728Z",
          "X-Amz-Signature":
              "f93baf6c6f2973cd7a96912345a968420e72df398fc95526f44c3d936abba6e6",
          "custom-field1": "cf1-value",
          "key": "foo/bar/tribble",
          "policy":
              "eyJleHBpcmF0aW9uIjoiMjAyMS0xMC0yNlQxOTowNzoyOC40OTJaIiwiY29uZGl0aW9ucyI6W3siYnVja2V0IjoiYnVja2V0In0seyJrZXkiOiJmb28vYmFyL3RyaWJibGUifSx7IlgtQW16LUFsZ29yaXRobSI6IkFXUzQtSE1BQy1TSEEyNTYifSx7IlgtQW16LUNyZWRlbnRpYWwiOiJBS0lBX1RFU1RfQUNDRVNTX0tFWS8yMDIxMTAyNi9jYS1jZW50cmFsLTEvczMvYXdzNF9yZXF1ZXN0In0seyJYLUFtei1EYXRlIjoiMjAyMTEwMjZUMTgwNzI4WiJ9LFsic3RhcnRzLXdpdGgiLCIka2V5IiwiZm9vL2JhciJdLHsiY3VzdG9tLWZpZWxkMSI6ImNmMS12YWx1ZSJ9XX0=",
        },
      });
    });
  });

  group('getHeadersToSign', () {
    test('filters and sorts headers', () {
      expect(
        getHeadersToSign({
          "Host": "s3.amazonaws.com",
          "Content-Length": "89327523384",
          "User-Agent": "Deno S3 Lite Client",
          "Content-Type": "image/svg+xml",
          "Cache-Control": "public, max-age=604800, immutable",
          "Content-Disposition": 'attachment; filename="image.svg"',
          "x-amz-storage-class": "GLACIER",
        }),
        ["cache-control", "content-disposition", "host", "x-amz-storage-class"],
      );
    });
  });

  group('getCanonicalRequest', () {
    test('test 1', () {
      expect(
        getCanonicalRequest(
          "POST",
          "/bucket/object123",
          {
            "sign-me": "yes",
            "dont-sign-me": "no",
          }, // Keys must be lowercase as per signV4 usage
          ["sign-me"],
          "3a6eb0790f39ac87c94f3856b2dd2c5d110e6811602261a9a923d3bb23adc8b7",
        ),
        "POST\n" +
            "/bucket/object123\n" +
            "\n" + // no query string
            "sign-me:yes\n" + // first header key + value
            "\n" + // end of headers
            "sign-me\n" + // list of signed headers
            "3a6eb0790f39ac87c94f3856b2dd2c5d110e6811602261a9a923d3bb23adc8b7", // hash of the payload
      );
    });

    test('test 2', () {
      expect(
        getCanonicalRequest(
          "GET",
          "/object123?query1=present",
          {
            "other-header": "value2",
            "third-header": "3",
            "host": "mybucket.mycompany.com",
          },
          ["host", "other-header", "third-header"],
          "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        ),
        "GET\n" +
            "/object123\n" +
            "query1=present\n" +
            "host:mybucket.mycompany.com\n" +
            "other-header:value2\n" +
            "third-header:3\n" +
            "\n" +
            "host;other-header;third-header\n" +
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      );
    });

    test('test 3', () {
      final params = {"ሴ": "bar", "unreserved": "-._~"};
      final queryString = "?${Uri(queryParameters: params).query}";

      expect(
        getCanonicalRequest(
          "GET",
          "/object123$queryString",
          {},
          [],
          "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        ),
        "GET\n" +
            "/object123\n" +
            "%E1%88%B4=bar&unreserved=-._~\n" +
            "\n" +
            "\n" +
            "\n" +
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      );
    });
  });

  group('getStringToSign', () {
    test('test 1', () async {
      expect(
        await getStringToSign(
          "canonical\nrequest\nhere",
          DateTime.parse("2021-10-26T18:07:28.492Z"),
          "us-gov-east-1",
        ),
        "AWS4-HMAC-SHA256\n" +
            "20211026T180728Z\n" +
            "20211026/us-gov-east-1/s3/aws4_request\n" +
            "473235b6e64747e5ee3adb25c3422d7f98d2d62c025011dfe8d94f6d7104a9fc",
      );
    });

    test('test 2', () async {
      expect(
        await getStringToSign(
          "some\nother\nREQUEST\nhere!@#!"
              r"$",
          DateTime.parse("2017-08-11T17:26:34.935Z"),
          "ca-central-1",
        ),
        "AWS4-HMAC-SHA256\n" +
            "20170811T172634Z\n" +
            "20170811/ca-central-1/s3/aws4_request\n" +
            "7d9363dc00f13c30e5621589e1d842ad9d0a7170daa0830d221628e95100a6d4",
      );
    });
  });

  group('getSigningKey', () {
    test('test 1', () async {
      expect(
        bin2hex(
          Uint8List.fromList(
            await getSigningKey(
              DateTime.parse("2017-08-11T17:26:34.935Z"),
              "eu-west-3",
              "SECRETd17n298wnqe",
            ),
          ),
        ),
        "f1ba68876e273e5b3dd2477639df79587d894fa12eae1eb0df1d17852874abf3",
      );
    });
    test('test 2', () async {
      expect(
        bin2hex(
          Uint8List.fromList(
            await getSigningKey(
              DateTime.parse("2021-10-26T18:07:28.492Z"),
              "ca-central-1",
              "ThisIsTheSecret",
            ),
          ),
        ),
        "76174baea77bcc266f63ed893b2bb07c1ebc59a02f55303f85d99fc68f568094",
      );
    });
  });

  group('getCredential', () {
    test('test 1', () {
      expect(
        getCredential(
          "AKIA_ACCESS_KEY",
          "us-west-2",
          DateTime.parse("2017-08-11T17:26:34.935Z"),
        ),
        "AKIA_ACCESS_KEY/20170811/us-west-2/s3/aws4_request",
      );
    });
  });

  group('sha256hmac', () {
    test('hmac matching', () async {
      expect(
        bin2hex(
          Uint8List.fromList(
            await sha256hmac(
              utf8.encode("secret"),
              utf8.encode("this is the data"),
            ),
          ),
        ),
        "d856191c41ef073996cd1dc468b8e8534fae720a52cf06d47ba4466a21995d28",
      );
    });
  });

  group('awsUriEncode', () {
    test('encoding', () {
      expect(awsUriEncode("foo/bar", true), "foo/bar");
      expect(awsUriEncode("foo/bar", false), "foo%2Fbar");
      expect(
        awsUriEncode("ABC-XYZ-abc-xyz-012-789!"),
        "ABC-XYZ-abc-xyz-012-789%21",
      );
      expect(awsUriEncode("a.b-c_d~e"), "a.b-c_d~e");
      expect(awsUriEncode("words with spaces"), "words%20with%20spaces");
      // Check cyrillic encoding
      // "файл" -> "%D1%84%D0%B0%D0%B9%D0%BB"
      expect(awsUriEncode("файл"), "%D1%84%D0%B0%D0%B9%D0%BB");
    });
  });
}
