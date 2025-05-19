import 'transport_data_models.dart'; // For P2pFileInfo
import 'transport_enums.dart'; // For ReceivableFileState

/// Manages information about a file being hosted (shared) by the local client.
class HostedFileInfo {
  /// Information about the file being hosted.
  final P2pFileInfo info;

  /// The local path to the file on the host's system.
  final String localPath;

  ReceivableFileState _state = ReceivableFileState.idle;

  final Map<String, int> _downloadProgressBytes;

  /// The current state of the file (e.g., idle, downloading, completed).
  ReceivableFileState get state => _state;

  /// A list of client IDs who are recipients of this file.
  List<String> get receiverIds => _downloadProgressBytes.keys.toList();

  /// Creates a [HostedFileInfo] instance.
  ///
  /// [info] is the general P2P file information.
  /// [localPath] is the path to the file on the local filesystem.
  /// [recipientIds] is a list of client IDs intended to receive this file.
  HostedFileInfo({
    required this.info,
    required this.localPath,
    required List<String> recipientIds,
  }) : _downloadProgressBytes = {for (var id in recipientIds) id: 0};

  /// Gets the download progress percentage for a specific receiver.
  ///
  /// Returns 0.0 if the file size is 0, or if the receiver ID is not found.
  double getProgressPercent(String receiverId) {
    final bytes = _downloadProgressBytes[receiverId];
    if (info.size == 0 || bytes == null) return 0.0;
    return (bytes / info.size) * 100.0;
  }

  /// Updates the download progress for a specific receiver.
  ///
  /// Only updates if the new [bytes] value is greater than the current progress.
  void updateProgress(
      String receiverId, int bytes, ReceivableFileState newState) {
    final currentBytes = _downloadProgressBytes[receiverId] ?? 0;
    if (bytes > currentBytes) {
      _downloadProgressBytes[receiverId] = bytes;
    }
    // upate state of file
    if (newState != _state) {
      _state = newState;
    }
  }
}

/// Manages information about a file that can be received by the local client.
class ReceivableFileInfo {
  /// Information about the file that can be received.
  final P2pFileInfo info;

  /// The current state of the file (e.g., idle, downloading, completed).
  ReceivableFileState state;

  /// The download progress percentage (0.0 to 100.0).
  double downloadProgressPercent;

  /// The local path where the file will be/is saved.
  String? savePath;

  /// Creates a [ReceivableFileInfo] instance.
  ReceivableFileInfo({
    required this.info,
    this.state = ReceivableFileState.idle,
    this.downloadProgressPercent = 0.0,
    this.savePath,
  });
}

/// Represents an update on the progress of a file download operation.
class FileDownloadProgressUpdate {
  /// The ID of the file being downloaded.
  final String fileId;

  /// The download progress as a percentage (0.0 to 100.0).
  final double progressPercent;

  /// The number of bytes downloaded so far.
  final int bytesDownloaded;

  /// The total size of the file in bytes.
  final int totalSize;

  /// The local path where the file is being saved.
  final String savePath;

  /// Creates a [FileDownloadProgressUpdate] instance.
  FileDownloadProgressUpdate({
    required this.fileId,
    required this.progressPercent,
    required this.bytesDownloaded,
    required this.totalSize,
    required this.savePath,
  });

  @override
  String toString() =>
      'FileDownloadProgressUpdate(fileId: $fileId, progress: ${progressPercent.toStringAsFixed(1)}%, path: $savePath)';
}
