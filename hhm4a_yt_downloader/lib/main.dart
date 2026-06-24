import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:file_picker/file_picker.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
  };
  runApp(const HHM4aYTDownloaderApp());
}

class HHM4aYTDownloaderApp extends StatelessWidget {
  const HHM4aYTDownloaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HH.M4a YT Downloader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0F1E),
        primaryColor: const Color(0xFFE52D27),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE52D27),
          secondary: Color(0xFFB31010),
        ),
      ),
      home: const DownloaderRoot(),
    );
  }
}

class DownloaderRoot extends StatefulWidget {
  const DownloaderRoot({super.key});

  @override
  State<DownloaderRoot> createState() => _DownloaderRootState();
}

class _DownloaderRootState extends State<DownloaderRoot> {
  final TextEditingController _urlController = TextEditingController();
  final YoutubeExplode _yt = YoutubeExplode();

  String _downloadPath = "Fetching default path...";
  String _statusText = "Ready";
  
  String _videoTitle = "Video Title";
  String _videoDuration = "-- min";
  String _videoAuthor = "Channel Name";
  String _thumbnailUrl = "";
  String? _selectedDirectory;
  String _typeSpinnerValue = "MP4";
  String _qualitySpinnerValue = "Auto";
  List<String> _qualityOptions = ["Auto"];
  
  double _progressValue = 0.0;
  bool _isDownloading = false;
  bool _isFetchDisabled = false;
  bool _isDownloadDisabled = true;

  Video? _currentVideoInfo;
  StreamManifest? _currentManifest;

  @override
  void initState() {
    super.initState();
    _initDefaultDownloadPath();
  }

  @override
  void dispose() {
    _yt.close();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _selectFolder() async {
    String? selectedPath = await FilePicker.platform.getDirectoryPath();

    if (selectedPath != null) {
      setState(() {
        _selectedDirectory = selectedPath;
      });
    }
  }

  // Fallback path heuristic mirroring default_download_path()
  Future<void> _initDefaultDownloadPath() async {
    String path = "";
    try {
      if (Platform.isAndroid) {
        final dir = Directory('/storage/emulated/0/Download');
        if (await dir.exists()) {
          path = dir.path;
        } else {
          final extDirs = await getExternalStorageDirectories(type: StorageDirectory.downloads);
          if (extDirs != null && extDirs.isNotEmpty) {
            path = extDirs.first.path;
          } else {
            path = (await getApplicationDocumentsDirectory()).path;
          }
        }
      } else if (Platform.isIOS) {
        path = (await getApplicationDocumentsDirectory()).path;
      } else {
        // Desktop platforms (Windows, macOS, Linux)
        final downloadDir = await getDownloadsDirectory();
        if (downloadDir != null) {
          path = downloadDir.path;
        } else {
          path = (await getApplicationDocumentsDirectory()).path;
        }
      }
    } catch (e) {
      path = "Error getting path";
    }
    setState(() {
      _downloadPath = path;
    });
  }

  Future<void> _requestStoragePermissions() async {
    if (Platform.isAndroid) {
      if (await Permission.manageExternalStorage.request().isGranted) return;
      await [Permission.storage].request();
    }
  }

  void _updateOptions() {
    if (_currentManifest == null) return;

    if (_typeSpinnerValue == "MP3") {
      _qualityOptions = ["320 kbps", "192 kbps", "128 kbps"];
    } else {
      // Collect heights from both muxed AND videoOnly streams to get HD options
      final allVideoStreams = [..._currentManifest!.muxed, ..._currentManifest!.videoOnly];
      
      final heights = allVideoStreams
          .map((s) => s.videoQualityLabel.replaceAll(RegExp(r'\D'), ''))
          .where((label) => label.isNotEmpty)
          .map((label) => int.parse(label))
          .toSet()
          .toList();
      
      heights.sort((a, b) => b.compareTo(a)); // Higher qualities first (4K, 1080p...)

      _qualityOptions = heights.map((h) => "${h}p").toList();
      if (_qualityOptions.isEmpty) {
        _qualityOptions = ["Auto"];
      }
    }

    setState(() {
      _qualitySpinnerValue = _qualityOptions.first;
    });
  }

  String _sanitizeFilename(String name, {String replacement = "_"}) {
    final validChars = RegExp(r'[^a-zA-Z0-9.\- _()]');
    String cleaned = name.replaceAll(validChars, replacement).trim();
    if (cleaned.length > 200) {
      cleaned = cleaned.substring(0, 200);
    }
    return cleaned.isEmpty ? "downloaded_media" : cleaned;
  }
  
  // 1. Updated Fetch Info using unthrottled mobile/VR backends
  Future<void> _fetchInfo() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _statusText = "Enter a URL");
      return;
    }
    
    final regExp = RegExp(r"(https?://)?(www\.)?(youtube\.com|youtu\.be)/.+");
    if (!regExp.hasMatch(url)) {
      setState(() => _statusText = "Invalid URL");
      return;
    }

    setState(() {
      _statusText = "Fetching info...";
      _isFetchDisabled = true;
    });

    try {
      final video = await _yt.videos.get(url);
      
      // FIX: Request unthrottled streams using specific non-web client backends
      final manifest = await _yt.videos.streams.getManifest(
        video.id,
        ytClients: [
          YoutubeApiClient.ios,
          YoutubeApiClient.androidVr,
          YoutubeApiClient.tv,
        ],
      );

      _currentVideoInfo = video;
      _currentManifest = manifest;

      setState(() {
        _videoTitle = video.title;
        _thumbnailUrl = video.thumbnails.mediumResUrl;
        _videoAuthor = video.author;
        final minutes = (video.duration?.inSeconds ?? 0) / 60;
        _videoDuration = video.duration != null ? "${minutes.toStringAsFixed(2)} min" : "Unknown duration";
        _isDownloadDisabled = false;
        _isFetchDisabled = false;
        _statusText = "Ready";
        _updateOptions();
      });
    } catch (e) {
      setState(() {
        _statusText = "Error: ${e.toString()}";
        _isFetchDisabled = false;
      });
    }
  }

  // Reusable stream piece downloader with shared real-time speed tracking
  Future<void> _downloadStreamToFile(
    StreamInfo streamInfo, 
    File file, 
    String label, 
    int overallTotalBytes, 
    int initialDownloadedBytes,
    int startTime,
  ) async {
    final downloadStream = _yt.videos.streams.get(streamInfo);
    final output = file.openWrite(mode: FileMode.write);
    
    int streamDownloadedBytes = 0;

    await for (final data in downloadStream) {
      streamDownloadedBytes += data.length;
      output.add(data);

      final int totalDownloadedSoFar = initialDownloadedBytes + streamDownloadedBytes;
      final double percent = (totalDownloadedSoFar / overallTotalBytes) * 100;
      final int now = DateTime.now().millisecondsSinceEpoch;
      final double durationSec = (now - startTime) / 1000;
      
      String etaText = "";
      if (durationSec > 0) {
        final double speed = totalDownloadedSoFar / durationSec;
        final int eta = ((overallTotalBytes - totalDownloadedSoFar) / speed).round();
        etaText = " — ETA ${eta}s";
      }

      setState(() {
        _progressValue = percent / 100;
        _statusText = "$label ${percent.toStringAsFixed(1)}%$etaText (${(totalDownloadedSoFar / 1024 / 1024).toStringAsFixed(1)} MB)";
      });
    }

    await output.flush();
    await output.close();
  }

  // The complete adaptive multiplexing download loop
  Future<void> _startDownload() async {
    if (_currentVideoInfo == null || _currentManifest == null) {
      setState(() => _statusText = "Fetch info first");
      return;
    }

    final String saveDirectory = _selectedDirectory ?? _downloadPath;

    if (!await Directory(saveDirectory).exists()) {
      setState(() => _statusText = "Error: Directory does not exist");
      return;
    }

    if (_isDownloading) {
      return;
    }

    setState(() {
      _isDownloading = true;
      _isDownloadDisabled = true;
      _progressValue = 0.0;
      _statusText = "Starting...";
    });

    try {
      await _requestStoragePermissions();
      final safeTitle = _sanitizeFilename(_currentVideoInfo!.title);
      final ext = _typeSpinnerValue == "MP3" ? "mp3" : "mp4";
      final fullPath = "$saveDirectory/${safeTitle}.$ext";
      final file = File(fullPath);

      // Target selection streams
      StreamInfo videoStreamInfo;
      StreamInfo? audioStreamInfo;
      bool needsAudioMerge = false;

      if (_typeSpinnerValue == "MP3") {
        videoStreamInfo = _currentManifest!.audioOnly.withHighestBitrate();
      } else {
        if (_qualitySpinnerValue == "Auto") {
          videoStreamInfo = _currentManifest!.muxed.sortByVideoQuality().last;
        } else {
          final targetHeight = int.tryParse(_qualitySpinnerValue.replaceAll(RegExp(r'\D'), '')) ?? 0;
          var muxedStream = _currentManifest!.muxed.where((s) => s.videoQualityLabel.contains("$targetHeight"));
          
          if (muxedStream.isNotEmpty) {
            videoStreamInfo = muxedStream.first;
          } else {
            // Target is high-definition video-only stream track
            videoStreamInfo = _currentManifest!.videoOnly.firstWhere(
              (s) => s.videoQualityLabel.contains("$targetHeight"),
              orElse: () => _currentManifest!.videoOnly.sortByVideoQuality().last
            );
            needsAudioMerge = true;
            audioStreamInfo = _currentManifest!.audioOnly.withHighestBitrate();
          }
        }
      }

      final int startTime = DateTime.now().millisecondsSinceEpoch;

      if (!needsAudioMerge) {
        // Direct standard conversion stream path (Audio-only or pre-merged low-res)
        final int totalBytes = videoStreamInfo.size.totalBytes;
        if (await file.exists()) await file.delete();
        
        await _downloadStreamToFile(videoStreamInfo, file, "Downloading:", totalBytes, 0, startTime);
        setState(() => _statusText = "Completed ✓");
      } else {
        // High-Definition layout tracking split streams merge sequence (1080p+)
        final int videoBytes = videoStreamInfo.size.totalBytes;
        final int audioBytes = audioStreamInfo!.size.totalBytes;
        final int totalBytes = videoBytes + audioBytes;

        final tempDir = await getTemporaryDirectory();
        final tempVideoFile = File("${tempDir.path}/temp_video_${DateTime.now().millisecondsSinceEpoch}.mp4");
        final tempAudioFile = File("${tempDir.path}/temp_audio_${DateTime.now().millisecondsSinceEpoch}.m4a");

        if (await tempVideoFile.exists()) await tempVideoFile.delete();
        if (await tempAudioFile.exists()) await tempAudioFile.delete();
        if (await file.exists()) await file.delete();

        // 1. Fetch Video Layer
        await _downloadStreamToFile(videoStreamInfo, tempVideoFile, "Downloading Video:", totalBytes, 0, startTime);

        // 2. Fetch Audio Layer
        await _downloadStreamToFile(audioStreamInfo, tempAudioFile, "Downloading Audio:", totalBytes, videoBytes, startTime);

        // 3. Core Native Muxing Execution
        // 3. Core Native Muxing Execution
        setState(() => _statusText = "Stitching High-Def files, Please Wait.....!");
        
        try {
          // Fix: Pass parameters via explicit string arguments to prevent filename space syntax breaks
          final session = await FFmpegKit.executeWithArguments([
            '-i', tempVideoFile.path,
            '-i', tempAudioFile.path,
            '-c:v', 'copy',  // Clones raw frame data directly without rendering lag
            '-c:a', 'aac',   // Encodes audio to universal clear AAC spec
            '-y',            // Force overwrite check safety
            fullPath         // Clean target path string
          ]);
          
          final returnCode = await session.getReturnCode();

          if (ReturnCode.isSuccess(returnCode)) {
            setState(() => _statusText = "Completed ✓");
          } else {
            final failStackTrace = await session.getFailStackTrace();
            setState(() => _statusText = "Stitch failed. Internal processing error.");
            print("FFmpeg Fail Log: $failStackTrace");
          }
        } catch (e) {
          // Expanded error display to catch explicit system-level exceptions
          setState(() => _statusText = "Error: ${e.toString()}");
        } finally {
          // Clear file buffer temporary artifacts securely
          if (await tempVideoFile.exists()) await tempVideoFile.delete();
          if (await tempAudioFile.exists()) await tempAudioFile.delete();
        }
      }
    } catch (e) {
      setState(() {
        _statusText = "Error: ${e.toString()}";
      });
    } finally {
      setState(() {
        _isDownloading = false;
        _isDownloadDisabled = false;
      });
    }
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: const Color(0xFF0D0D1B).withOpacity(0.65),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withOpacity(0.06), width: 1.2),
    );
  }

  Future<void> _pasteUrlWithConfirmation() async {
    ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF111122),
          title: const Text("Paste URL", style: TextStyle(color: Colors.white)),
          content: Text("Do you want to paste: \n${data.text}", style: const TextStyle(color: Colors.white70)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Paste")),
          ],
        ),
      );
      if (confirmed == true) {
        _urlController.text = data.text!;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/background1.png', fit: BoxFit.cover, errorBuilder: (c, e, s) {
              return Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF14142B), Color(0xFF080811)], begin: Alignment.topCenter, end: Alignment.bottomCenter)));
            }),
          ),
          Positioned.fill(child: Container(color: Colors.black.withOpacity(0.2))),
          Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 700),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: ListView(
                physics: const BouncingScrollPhysics(),
                children: [
                  const SizedBox(height: 20),
                  
                  // HEADER
                  Row(
                    children: [
                      Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFFE52D27).withOpacity(0.15), shape: BoxShape.circle), child: const Icon(Icons.play_arrow_rounded, size: 36, color: Color(0xFFE52D27))),
                      const SizedBox(width: 14),
                      const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("HH.M4a YT Downloader", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white))])),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // 1. URL INPUT
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: _cardDecoration(),
                    child: TextField(
                      controller: _urlController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(hintText: "Paste YouTube URL here...", hintStyle: TextStyle(color: Colors.grey[500]), border: InputBorder.none, suffixIcon: IconButton(icon: const Icon(Icons.paste, color: Colors.white54), onPressed: _pasteUrlWithConfirmation)),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 2. FETCH INFO BUTTON
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _isFetchDisabled ? null : _fetchInfo,
                      icon: const Icon(Icons.search),
                      label: const Text("Fetch Info"),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE52D27), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    ),
                  ),

                  // CONDITIONAL DETAILS
                  if (_videoTitle.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: _cardDecoration(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 3. THUMBNAIL
                          ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(_thumbnailUrl, width: double.infinity, height: 200, fit: BoxFit.cover)),
                          const SizedBox(height: 16),
                          // 4. TITLE
                          Text(_videoTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                          const SizedBox(height: 10),
                          // 5. AUTHOR
                          Text("Channel: $_videoAuthor", style: TextStyle(color: Colors.grey[300])),
                          const SizedBox(height: 6),
                          // 6. DURATION
                          Text("Duration: $_videoDuration", style: TextStyle(color: Colors.grey[300])),
                          const SizedBox(height: 6),
                          // FORMATS
                          const Text("Available Formats: MP4 • MP3", style: TextStyle(color: Color(0xFFE52D27), fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [const Icon(Icons.description_outlined, size: 14, color: Color(0xFFE52D27)), const SizedBox(width: 6), Text("Type", style: TextStyle(color: Colors.grey[300], fontSize: 13, fontWeight: FontWeight.w500))]),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: _typeSpinnerValue,
                              dropdownColor: const Color(0xFF111122),
                              decoration: InputDecoration(
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                filled: true,
                                fillColor: Colors.black.withOpacity(0.3),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              ),
                              items: ["MP4", "MP3"].map((String val) {
                                return DropdownMenuItem<String>(value: val, child: Text(val, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)));
                              }).toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() {
                                    _typeSpinnerValue = value;
                                    _updateOptions();
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [const Icon(Icons.hd_outlined, size: 14, color: Color(0xFFE52D27)), const SizedBox(width: 6), Text("Resolution", style: TextStyle(color: Colors.grey[300], fontSize: 13, fontWeight: FontWeight.w500))]),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: _qualitySpinnerValue,
                              dropdownColor: const Color(0xFF111122),
                              decoration: InputDecoration(
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                filled: true,
                                fillColor: Colors.black.withOpacity(0.3),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              ),
                              items: _qualityOptions.map((String val) {
                                bool isSelected = val == _qualitySpinnerValue;
                                return DropdownMenuItem<String>(
                                  value: val,
                                  child: Text(val, style: TextStyle(fontSize: 14, color: isSelected ? const Color(0xFFE52D27) : Colors.white)),
                                );
                              }).toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _qualitySpinnerValue = value);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Inside your build method, look for the "Download Location" section:
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.25), 
                                border: Border.all(color: Colors.white10), 
                                borderRadius: BorderRadius.circular(12)
                              ),
                              child: Text(
                                _selectedDirectory ?? _downloadPath, 
                                overflow: TextOverflow.ellipsis, 
                                style: TextStyle(color: Colors.grey[300], fontSize: 13, fontFamily: 'monospace')
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            onPressed: _selectFolder, // This now points to your FilePicker version
                            icon: const Icon(Icons.folder_open, color: Colors.redAccent),
                            tooltip: "Choose Folder",
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: _cardDecoration(),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(children: [const Icon(Icons.adjust_rounded, size: 15, color: Color(0xFFE52D27)), const SizedBox(width: 6), const Text("Download Progress Info", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14))]),
                            Text("${(_progressValue * 100).toStringAsFixed(1)} %", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(value: _progressValue, color: const Color(0xFFE52D27), backgroundColor: Colors.white12, minHeight: 5),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                _statusText.startsWith("Downloading") ? _statusText : "Status: $_statusText", 
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w400, fontFamily: 'monospace'),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _isDownloadDisabled ? null : _startDownload,
                      icon: _isDownloading 
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.file_download_outlined, size: 20),
                      label: Text(_isDownloading ? "Downloading..." : "Download", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE52D27),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.white10,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("Made with ", style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                      const Icon(Icons.favorite, color: Color(0xFFE52D27), size: 14),
                      Text(" by ", style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                      const Text("HH.M4a", style: TextStyle(color: Color(0xFFE52D27), fontSize: 13, fontWeight: FontWeight.w500)),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                ],
            ),
          )
        ),
      ],
    ),
  );
  }
}