/// Enum representing the type of a P2P message.
enum P2pMessageType {
  /// Message contains a data payload (text and/or files).
  payload,

  /// Message contains an updated list of connected clients.
  clientList,

  /// Message contains an update on file download progress.
  fileProgressUpdate,

  /// Message type is unknown or cannot be determined.
  unknown,
}

/// Enum representing the state of a file that can be received.
enum ReceivableFileState {
  /// The file is available for download, but no download is in progress.
  idle,

  /// The file is currently being downloaded.
  downloading,

  /// The file download has completed successfully.
  completed,

  /// An error occurred during the file download.
  error,
}
