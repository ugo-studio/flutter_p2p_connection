import 'dart:io';
import 'package:flutter/foundation.dart';

import 'transport_file_models.dart'; // For HostedFileInfo

/// Mixin providing common file request handling logic for HTTP servers
/// that serve files in the P2P network.
mixin FileRequestServerMixin {
  /// A map of hosted files, where the key is the file ID.
  Map<String, HostedFileInfo> get hostedFiles;

  /// The username of the transport (host or client) for logging purposes.
  String get transportUsername; // For logging prefix
  static const String _logPrefixBase = "P2P FileServer";

  /// Handles an incoming HTTP request for a file.
  ///
  /// This method processes requests to the `/file` endpoint, supporting
  /// full file downloads and byte range requests.
  Future<void> handleFileRequest(HttpRequest request) async {
    final logPrefix = "$_logPrefixBase [$transportUsername]";
    final fileId = request.uri.queryParameters['id'];

    if (fileId == null || fileId.isEmpty) {
      debugPrint("$logPrefix: File request missing ID.");
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('File ID parameter is required.')
        ..close();
      return;
    }

    final hostedFile = hostedFiles[fileId];
    if (hostedFile == null) {
      debugPrint(
          "$logPrefix: Requested file ID not found or not hosted: $fileId");
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('File not found or access denied.')
        ..close();
      return;
    }

    final filePath = hostedFile.localPath;
    final file = File(filePath);
    if (!await file.exists()) {
      debugPrint(
          "$logPrefix: Hosted file path not found on disk: $filePath (ID: $fileId)");
      hostedFiles.remove(fileId);
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..write('File data is unavailable.')
        ..close();
      return;
    }

    final fileStat = await file.stat();
    final totalSize = fileStat.size;
    final response = request.response;

    response.headers.contentType = ContentType.binary;
    response.headers.add(HttpHeaders.contentDisposition,
        'attachment; filename="${Uri.encodeComponent(hostedFile.info.name)}"');
    response.headers.add(HttpHeaders.acceptRangesHeader, 'bytes');

    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    int rangeStart = 0;
    int? rangeEnd;

    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      try {
        final rangeValues = rangeHeader.substring(6).split('-');
        rangeStart = int.parse(rangeValues[0]);
        if (rangeValues[1].isNotEmpty) {
          rangeEnd = int.parse(rangeValues[1]);
        }

        if (rangeStart < 0 ||
            rangeStart >= totalSize ||
            (rangeEnd != null &&
                (rangeEnd < rangeStart || rangeEnd >= totalSize))) {
          throw const FormatException('Invalid range');
        }
        rangeEnd ??= totalSize - 1;
        final rangeLength = (rangeEnd - rangeStart) + 1;

        debugPrint(
            "$logPrefix: Serving range $rangeStart-$rangeEnd (length $rangeLength) for file $fileId");
        response.statusCode = HttpStatus.partialContent;
        response.headers.contentLength = rangeLength;
        response.headers.add(HttpHeaders.contentRangeHeader,
            'bytes $rangeStart-$rangeEnd/$totalSize');
        final stream = file.openRead(rangeStart, rangeEnd + 1);
        await response.addStream(stream);
      } catch (e) {
        debugPrint("$logPrefix: Invalid Range header '$rangeHeader': $e");
        response
          ..statusCode = HttpStatus.requestedRangeNotSatisfiable
          ..headers.add(HttpHeaders.contentRangeHeader, 'bytes */$totalSize')
          ..write('Invalid byte range requested.')
          ..close();
        return;
      }
    } else {
      debugPrint(
          "$logPrefix: Serving full file $fileId (${hostedFile.info.name})");
      response.statusCode = HttpStatus.ok;
      response.headers.contentLength = totalSize;
      final stream = file.openRead();
      await response.addStream(stream);
    }

    try {
      await response.close();
      debugPrint("$logPrefix: Finished sending file/range for $fileId.");
    } catch (e) {
      debugPrint("$logPrefix: Error closing response stream for $fileId: $e");
    }
  }
}
